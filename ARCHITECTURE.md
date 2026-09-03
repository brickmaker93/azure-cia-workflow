# Azure Change Impact Analysis (CIA) Workflow Architecture

## Executive Summary

This document outlines a resilient, scalable Azure architecture for a Change Impact Analysis system that:
- Triggers daily to identify changes across 5 source systems
- Executes AI-powered Python APIs to compute impact analysis
- Persists results via a .NET API service
- Notifies stakeholders via Teams with actionable insights
- Provides a Teams tab app for impact review

---

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          AZURE CHANGE IMPACT ANALYSIS WORKFLOW              │
└─────────────────────────────────────────────────────────────────────────────┘

        ┌──────────────┐
        │  Timer Trigger│ (Daily @ HH:MM UTC)
        │   (Logic App) │
        └────────┬─────┘
                 │
        ┌────────▼──────────────┐
        │  Orchestrator Service │ (Durable Functions / Logic App)
        │  - Coordinate flow    │
        │  - Error handling     │
        │  - Retry logic        │
        └────────┬──────────────┘
                 │
    ┌────────────┼────────────┬──────────────┐
    │            │            │              │
┌───▼──┐    ┌───▼──┐    ┌───▼──┐       ┌───▼──┐
│Source│    │Source│    │Source│  ...  │Source│
│Sys 1 │    │Sys 2 │    │Sys 3 │       │Sys 5 │
└───┬──┘    └───┬──┘    └───┬──┘       └───┬──┘
    │           │           │              │
    └───────────┼───────────┼──────────────┘
                │
        ┌───────▼────────────────┐
        │  Change Aggregator     │
        │  (Azure Function)      │
        └───────┬────────────────┘
                │
        ┌───────▼────────────────────────┐
        │  CIA Computation Service       │
        │  (Python API - Container/Func) │
        │  - AI-powered analysis         │
        │  - Batch processing            │
        └───────┬────────────────────────┘
                │
        ┌───────▼────────────────┐
        │  CIA Persistence API   │
        │  (.NET - App Service)  │
        │  - Data validation     │
        │  - DB operations       │
        └───────┬────────────────┘
                │
        ┌───────▼────────────────┐
        │  Azure SQL Database    │
        │  - CIA records         │
        │  - Impacted items      │
        │  - Audit logs          │
        └───────┬────────────────┘
                │
        ┌───────▼────────────────────┐
        │  Notification Service      │
        │  (Logic App / Function)    │
        │  - Deduplication logic     │
        │  - Adaptive card creation  │
        └───────┬────────────────────┘
                │
        ┌───────▼────────────────┐
        │  Microsoft Teams       │
        │  - Notifications       │
        │  - Tab App Integration │
        └────────────────────────┘
```

---

## 2. Service Selection & Rationale

### 2.1 Orchestration: Azure Logic Apps

**Recommendation: Azure Logic Apps**
- Native visual workflow designer
- Built-in recurrence trigger for daily scheduling
- Integrated retry policies and error handling
- Native Microsoft Teams connector
- Low-code approach for fast deployment

**Alternative**: Azure Durable Functions for complex scenarios with longer execution times

---

### 2.2 Source System Integration

**Recommendation: Logic App Connectors + Azure Data Factory (optional)**

Use native Logic App connectors for:
- SAP (SAP Connector)
- Salesforce (Salesforce Connector)
- SQL Server (SQL Server Connector)
- REST APIs (HTTP Connector)
- Custom systems (Custom Connectors)

**Change Detection Strategy**:
- Store last successful run timestamp in Azure Table Storage
- Query each source system for changes since that timestamp
- Implement idempotency keys for duplicate handling
- Atomic update of run completion timestamp

---

### 2.3 CIA Computation Service

**Recommendation: Azure Container Instances (ACI) with Python**

| Option | Pros | Cons | Decision |
|--------|------|------|----------|
| **Azure Functions** | Serverless, cheap | 15-min timeout limit | Not suitable |
| **Container Instances** | Full control, long execution | Pay-per-second | ✓ Selected |
| **App Service** | Always-on | Overkill for periodic runs | Consider for high volume |
| **AKS** | Full scalability | Operational overhead | Too complex |

**Why Container Instances**:
- Supports AI/ML workloads with long execution times (30+ minutes)
- Full Python ecosystem support
- Cost-effective for periodic execution (pay only when running)
- Easy Docker packaging and deployment
- Auto-cleanup of completed instances

**Deployment Model**:
```
Docker Image (Python + AI Model)
  └─→ Push to Azure Container Registry (ACR)
  └─→ Deploy to Container Instances
  └─→ Expose REST API endpoint
  └─→ Called by Logic App orchestrator
```

---

### 2.4 Data Persistence: .NET API & Azure SQL

**Recommendation: .NET 6+ Web API on App Service + Azure SQL Database**

**Why Azure SQL**:
- ACID compliance for transactional integrity
- Audit trail requirements met via change tracking
- Managed backups and PITR
- Built-in security features (TDE, Advanced Threat Protection)
- Cost-effective for structured data

**Why .NET API**:
- Strong type safety for data validation
- Entity Framework Core for ORM
- Built-in dependency injection
- Native Azure AD integration via MSAL
- High performance for API workloads

**Database Schema**:
```sql
CHANGES
├─ ChangeId (PK)
├─ SourceSystem
├─ ChangeData (JSON)
└─ ProcessedAt

CHANGE_IMPACT_ANALYSIS
├─ CiaId (PK)
├─ ChangeId (FK)
├─ ComputedAt
├─ AiModel
├─ AiConfidence
└─ ExecutionTimeMs

IMPACTED_ITEMS
├─ ImpactedItemId (PK)
├─ CiaId (FK)
├─ ItemId
├─ ImpactLevel (high/medium/low)
└─ AffectedSystems (JSON)

ITEM_ASSIGNEES
├─ AssigneeId (PK)
├─ ImpactedItemId (FK)
├─ UserEmail
├─ UserObjectId
├─ NotificationSent
└─ NotificationSentAt

AUDIT_LOG
├─ LogId (PK)
├─ Operation
├─ EntityType
├─ EntityId
├─ ChangeData
├─ UserId
└─ CreatedAt
```

---

### 2.5 Notification Service

**Recommendation: Logic App with Teams Connector + Adaptive Cards**

**Flow**:
1. Query database for all unique assignees across impacted items
2. Deduplicate assignees
3. For each assignee, build personalized Adaptive Card
4. Send Teams message with deep link to Teams Tab App
5. Mark notification as sent in database with timestamp

**Adaptive Card Structure**:
```json
{
  "type": "message",
  "attachments": [
    {
      "contentType": "application/vnd.microsoft.card.adaptive",
      "content": {
        "body": [
          {
            "type": "TextBlock",
            "text": "⚠️ Change Impact Analysis Alert",
            "weight": "bolder",
            "size": "large"
          },
          {
            "type": "TextBlock",
            "text": "You have N impacted items from recent system changes"
          },
          {
            "type": "FactSet",
            "facts": [
              {"name": "High Impact:", "value": "2"},
              {"name": "Medium Impact:", "value": "1"}
            ]
          }
        ],
        "actions": [
          {
            "type": "Action.OpenUrl",
            "title": "Review in Teams Tab",
            "url": "https://teams.microsoft.com/l/app/[APP-ID]?context={...}"
          }
        ]
      }
    }
  ]
}
```

---

### 2.6 Teams Tab App

**Recommendation: React + Microsoft Teams SDK + Azure AD Auth**

**Architecture**:
```
React SPA
├─ Authentication: MSAL (Azure AD)
├─ Pages:
│  ├─ Dashboard: User's impacted items (paginated)
│  ├─ Detail: Full CIA analysis for selected item
│  └─ History: Previous analyses
├─ API Layer: Calls .NET backend
├─ Styling: Fluent UI components
└─ Deployment: Azure Static Web Apps or App Service
```

**Key API Endpoint**:
```
GET /api/cia/user/{userEmail}/impacted-items?skip=0&take=50

Response:
{
  "totalCount": 3,
  "items": [
    {
      "ciaId": "CIA-98765",
      "itemId": "ITEM-001",
      "impactLevel": "high",
      "affectedSystems": ["CRM", "Inventory"],
      "changedAt": "2026-09-03T10:30:00Z",
      "sourceSystem": "SAP",
      "deepLink": "/cia/CIA-98765/item/ITEM-001"
    }
  ]
}
```

---

## 3. Data Flow & Processing

### 3.1 Daily Execution Timeline

```
09:00 UTC → Timer Trigger Fires
  ↓
09:01 UTC → Retrieve last run timestamp from Table Storage
  ↓
09:02 UTC → Query 5 source systems in parallel
  ├─→ Source 1: changes since last run
  ├─→ Source 2: changes since last run
  ├─→ Source 3: changes since last run
  ├─→ Source 4: changes since last run
  └─→ Source 5: changes since last run
  ↓
09:05 UTC → Aggregate + deduplicate changes (N items)
  ↓
09:06 UTC → Process in parallel batches (10 items per batch)
  FOR EACH change:
    ├─→ Call Python CIA API
    ├─→ Call .NET Persistence API
    ├─→ Log results
    └─→ Retry 3x on failure (exponential backoff)
  ↓
09:XX UTC → Query unique assignees across all impacted items
  ↓
09:YY UTC → Send Teams notifications to each assignee
  ↓
10:00 UTC → Store run completion timestamp
  ↓
10:01 UTC → Send admin summary report
  ↓
COMPLETE
```

---

## 4. Error Handling & Resilience

### 4.1 Error Handling Strategy

```
Level 1: Transient Errors (Network, Timeouts)
└─→ Retry: 1s → 2s → 4s → 8s (max 3 attempts)

Level 2: Source System Failures
└─→ Skip failed source, continue with others
└─→ Alert operations team
└─→ Log warning to audit trail

Level 3: CIA Computation Failures
└─→ Move to dead-letter queue (Table Storage)
└─→ Alert ML/AI team
└─→ Requires manual investigation & reprocessing

Level 4: Persistence Failures
└─→ Rollback database transaction
└─→ Retry entire CIA record
└─→ Escalate to DBA if persistent

Level 5: Notification Failures
└─→ Retry hourly for 24 hours
└─→ Flag in UI as "Notification Pending"
└─→ Log to audit trail
```

### 4.2 Resilience Patterns

```
✓ Idempotency: All operations use CiaId/ChangeId as idempotency key
✓ Circuit Breaker: Fail-fast for unavailable services
✓ Bulkhead: Isolated resource pools per service
✓ Graceful Degradation: Continue if 1-2 sources fail
✓ Retry with Backoff: Exponential backoff for transient failures
✓ Timeout Handling: Explicit timeouts on all external calls
```

---

## 5. Security Architecture

### 5.1 Authentication & Authorization

```
Service-to-Service:
├─ Logic App → Source Systems: Managed Identity or stored credentials
├─ Logic App → Python API: Container auth + network security
├─ Logic App → .NET API: Managed Identity (RBAC)
└─ .NET API → Azure SQL: Managed Identity (Azure AD auth)

User-to-App:
├─ Teams Tab App → .NET API: OAuth 2.0 (Azure AD)
├─ Teams App Authentication: Teams SSO + MSAL
└─ Role-Based Access Control (RBAC) in .NET API
```

### 5.2 Network Security

```
✓ Azure SQL: Private Endpoint (no public IP)
✓ Container Instances: VNet integration, no internet exposure
✓ App Service: Private Endpoint + IP restrictions
✓ Logic App: Managed Connections (encrypted)
✓ All APIs: HTTPS only (TLS 1.2+)
```

### 5.3 Data Protection

```
At Rest:
├─ Azure SQL: Transparent Data Encryption (TDE)
├─ Table Storage: Server-side encryption
├─ Key Vault: FIPS 140-2 Level 2

In Transit:
├─ TLS 1.2+ for all API calls
├─ Mutual TLS for internal services
└─ No secrets in logs or error messages

Secrets Management:
├─ All credentials in Azure Key Vault
├─ Managed Identities for service auth
├─ Never commit secrets to Git
└─ Rotate credentials quarterly
```

### 5.4 Audit & Compliance

```
✓ Audit Log Table: All CIA operations logged with timestamp
✓ Change Tracking: Azure SQL change tracking enabled
✓ Application Insights: Security event monitoring
✓ Azure AD Logs: User access and authentication attempts
✓ Data Retention: 7 years for CIA records, 3 years for audit
```

---

## 6. Monitoring & Observability

### 6.1 Key Metrics

```
Business Metrics:
├─ Changes processed per day
├─ CIAs computed (success/failure rate)
├─ Average CIA computation time
├─ Users notified per run
├─ Teams app engagement rate

Technical Metrics:
├─ Logic App action success rate (%)
├─ Source system API latency (p50, p95, p99)
├─ CIA computation time (ms)
├─ .NET API endpoint latency (ms)
├─ Database query performance
├─ Container instance startup time
└─ Notification delivery success rate
```

### 6.2 Alert Rules

```
🔴 CRITICAL:
├─ Workflow failure rate > 5% (24h)
├─ Source system unavailable (>30 min)
├─ Database CPU > 80% (sustained 10 min)
└─ Dead-letter queue > 10 items

🟡 WARNING:
├─ CIA computation avg time > 5 min
├─ Notification delivery success < 95%
├─ Logic App action error rate > 2%
└─ Container instance failed to start
```

### 6.3 Application Insights Dashboard

```
Pinned Tiles:
├─ Overall workflow success rate
├─ CIA computation time trend
├─ Error rate by service
├─ Source system dependency health
├─ Notification delivery status
└─ Database performance metrics
```

---

## 7. Cost Optimization

### 7.1 Estimated Monthly Costs

```
Service                    | Configuration      | Est. Cost
---------------------------|-------------------|----------
Logic App                  | 500k actions/mo   | $150
Container Instances        | 10 vCPU-hr/mo     | $100
App Service (Persistence)  | B2 (Medium)       | $80
Azure SQL Database         | Standard S1       | $30
Table Storage (tracking)   | Pay-as-you-go    | $5
Application Insights       | Sampling enabled  | $20
Key Vault                  | Standard          | $0.50
────────────────────────────────────────────────
TOTAL ESTIMATED             | Per Month         | ~$385
```

### 7.2 Cost Optimization Strategies

```
1. Batch Processing
   └─→ Process multiple changes per container run
   └─→ Reduce container startup overhead

2. Auto-Scaling
   └─→ App Service: Scale down during off-peak
   └─→ Container Instances: Only during scheduled windows

3. Reserved Capacity
   └─→ 3-year RI: Azure SQL (-40%)
   └─→ 1-year RI: App Service (-30%)

4. Caching
   └─→ Redis: Cache CIA results for 24h
   └─→ Reduce recomputation of same changes

5. Monitoring Sampling
   └─→ Application Insights: 10% sampling
   └─→ Structured logging with proper levels
```

---

## 8. Implementation Roadmap

### Phase 1: Foundation (Weeks 1-3)
- [ ] Azure Resource Group setup
- [ ] Azure SQL Database creation with schema
- [ ] Build .NET Persistence API (CRUD)
- [ ] Deploy to App Service with Managed Identity
- [ ] Key Vault setup for secrets

### Phase 2: Orchestration (Weeks 4-6)
- [ ] Create Logic App with daily timer
- [ ] Implement source system connectors (5 systems)
- [ ] Build change aggregation logic
- [ ] Implement retry policies & error handling
- [ ] Test with sample data

### Phase 3: AI/CIA Computation (Weeks 7-9)
- [ ] Package Python AI model in Docker
- [ ] Deploy to Azure Container Instances
- [ ] Create REST API wrapper
- [ ] Integrate with orchestrator
- [ ] Performance testing & tuning

### Phase 4: Notifications (Weeks 10-11)
- [ ] Build notification logic in Logic App
- [ ] Create Adaptive Card templates
- [ ] Implement assignee deduplication
- [ ] Test Teams message delivery
- [ ] Verify notification tracking in DB

### Phase 5: Teams Tab App (Weeks 12-14)
- [ ] Create React app with Teams SDK
- [ ] Implement Azure AD authentication
- [ ] Build impacted items list UI
- [ ] Deploy to Static Web Apps
- [ ] UAT with pilot users

### Phase 6: Monitoring & Security (Weeks 15-16)
- [ ] Set up Application Insights dashboards
- [ ] Configure alert rules & action groups
- [ ] Implement audit logging
- [ ] Security review & penetration testing
- [ ] Load testing (1000+ changes/day)

### Phase 7: Launch (Weeks 17-18)
- [ ] Documentation & runbooks
- [ ] Operations team training
- [ ] Pilot run (1 week)
- [ ] Full production launch
- [ ] Post-launch monitoring

---

## 9. Technology Stack

```
Orchestration:        Azure Logic Apps
Scheduling:           Recurrence Trigger
Source Integration:   REST/SQL Connectors
AI Computation:       Python + Azure Container Instances
API Layer:            .NET 6+ Web API + App Service
Database:             Azure SQL Database
Secrets:              Azure Key Vault
Caching:              Azure Cache for Redis (optional)
Messaging:            Teams API + Adaptive Cards
Auth:                 Azure AD + MSAL
Monitoring:           Application Insights + Log Analytics
Infrastructure:       Bicep templates
CI/CD:                GitHub Actions / Azure DevOps
VCS:                  Git
```

---

**Document Version**: 1.0  
**Last Updated**: 2026-09-03  
**Status**: Ready for implementation