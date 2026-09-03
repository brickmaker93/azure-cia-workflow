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

### 2.1 Orchestration: Azure Logic Apps or Durable Functions

**Recommendation: Azure Logic Apps** (with fallback to Durable Functions for complex scenarios)

| Aspect | Logic Apps | Durable Functions | Winner |
|--------|-----------|-------------------|--------|
| Visual Design | Native workflow designer | Code-based | Logic Apps (visual clarity) |
| Daily Scheduling | Built-in recurrence trigger | Manual implementation | Logic Apps ✓ |
| Error Handling | Retry policies, error actions | Try-catch, retry logic | Tie |
| Monitoring | Application Insights integration | Full telemetry | Tie |
| Cost | Per action execution | Per execution + function calls | Functions (lower cost at scale) |
| Team Familiarity | Low-code, less DevOps | Requires coding | Logic Apps (accessibility) |

**Decision: Logic Apps** (easier management + visual workflows + built-in Teams integration)

---

### 2.2 Source System Integration

**Recommendation: Azure Data Factory or Logic App Connectors**

For 5 different source systems:
- **Option A**: Use Logic App's built-in connectors (SAP, Salesforce, SQL, REST, etc.)
- **Option B**: Azure Data Factory with REST/custom activities
- **Option C**: Azure Functions with custom SDK integrations

**Decision: Logic App Connectors** (native support for most enterprise systems + retry/throttling built-in)

**Change Detection Strategy**:
```
Each source system call retrieves:
- Last successful run timestamp (stored in Azure Table Storage)
- Only records modified since that timestamp
- Store run completion timestamp atomically with result processing
- Implement idempotency key for duplicate handling
```

---

### 2.3 CIA Computation Service

**Recommendation: Azure Container Instances (ACI) with auto-scaling via Orchestrator**

| Option | Pros | Cons | Use Case |
|--------|------|------|----------|
| **Azure Functions (Python)** | Serverless, cheap, fast startup | 15-min timeout limitation | Small, lightweight analysis |
| **Container Instances** | Full control, longer execution, packaged Python | Pay-per-second, cold starts | Medium analysis, 30+ min jobs |
| **App Service** | Always-on, predictable cost | Overkill for periodic runs | Not recommended |
| **Kubernetes (AKS)** | Maximum scalability, enterprise | Operational overhead | Not needed for this scale |

**Decision: Azure Container Instances** 
- Supports long-running AI computations
- Python ecosystem fully supported
- Cost-effective for periodic execution
- Deploy via Helm or ARM templates

**Architecture Pattern**:
```python
# CIA Service Container
POST /compute-cia
{
  "change_id": "CHG-12345",
  "source_system": "SAP",
  "change_data": {...},
  "ai_model_version": "v2.1"
}

Response:
{
  "cia_id": "CIA-98765",
  "impacted_items": [
    {
      "item_id": "ITEM-001",
      "impact_level": "high",
      "affected_systems": ["CRM", "Inventory"],
      "assignees": ["user1@company.com", "user2@company.com"]
    },
    ...
  ],
  "execution_time_ms": 4521,
  "ai_confidence": 0.94
}
```

---

### 2.4 Data Persistence: .NET API & Database

**Recommendation: Azure SQL Database with .NET 6+ Web API (App Service)**

**Database Schema**:
```sql
-- Changes table
CREATE TABLE Changes (
    ChangeId VARCHAR(50) PRIMARY KEY,
    SourceSystem VARCHAR(50),
    ChangeData NVARCHAR(MAX),
    ProcessedAt DATETIME2,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE()
);

-- CIA records
CREATE TABLE ChangeImpactAnalysis (
    CiaId VARCHAR(50) PRIMARY KEY,
    ChangeId VARCHAR(50) FOREIGN KEY REFERENCES Changes(ChangeId),
    ComputedAt DATETIME2,
    AiModel VARCHAR(50),
    AiConfidence FLOAT,
    ExecutionTimeMs INT,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE()
);

-- Impacted items
CREATE TABLE ImpactedItems (
    ImpactedItemId INT PRIMARY KEY IDENTITY,
    CiaId VARCHAR(50) FOREIGN KEY REFERENCES ChangeImpactAnalysis(CiaId),
    ItemId VARCHAR(50),
    ImpactLevel VARCHAR(20), -- high, medium, low
    AffectedSystems NVARCHAR(MAX), -- JSON array
    AssigneeCount INT,
    CreatedAt DATETIME2 DEFAULT GETUTCDATE()
);

-- Item assignees
CREATE TABLE ItemAssignees (
    AssigneeId INT PRIMARY KEY IDENTITY,
    ImpactedItemId INT FOREIGN KEY REFERENCES ImpactedItems(ImpactedItemId),
    UserEmail VARCHAR(255),
    UserObjectId VARCHAR(255), -- Azure AD Object ID
    NotificationSent BIT DEFAULT 0,
    NotificationSentAt DATETIME2,
    UNIQUE(ImpactedItemId, UserEmail)
);

-- Audit log
CREATE TABLE AuditLog (
    LogId BIGINT PRIMARY KEY IDENTITY,
    Operation VARCHAR(50),
    EntityType VARCHAR(50),
    EntityId VARCHAR(50),
    ChangeData NVARCHAR(MAX),
    UserId VARCHAR(255),
    CreatedAt DATETIME2 DEFAULT GETUTCDATE()
);
```

**API Endpoints** (.NET):
```csharp
// POST /api/cia/compute-result
public class ComputeResultRequest
{
    public string CiaId { get; set; }
    public string ChangeId { get; set; }
    public string SourceSystem { get; set; }
    public ImpactedItem[] ImpactedItems { get; set; }
    public float AiConfidence { get; set; }
}

// GET /api/cia/user/{userEmail}/impacted-items
// Returns: List<UserImpactSummary> for Teams tab app

// GET /api/cia/{ciaId}/details
// Returns: Full CIA with all impacted items and assignees
```

---

### 2.5 Notification Service

**Recommendation: Logic App with Teams Connector + Adaptive Cards**

**Flow**:
1. Query database for all unique assignees across impacted items
2. For each assignee, build personalized Adaptive Card
3. Send Teams message with card + link to Teams tab app
4. Mark notification as sent in database

**Adaptive Card Example**:
```json
{
  "type": "message",
  "attachments": [
    {
      "contentType": "application/vnd.microsoft.card.adaptive",
      "contentUrl": null,
      "content": {
        "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
        "type": "AdaptiveCard",
        "version": "1.4",
        "body": [
          {
            "type": "TextBlock",
            "text": "⚠️ Change Impact Analysis Alert",
            "weight": "bolder",
            "size": "large"
          },
          {
            "type": "TextBlock",
            "text": "You have 3 impacted items from recent system changes",
            "wrap": true
          },
          {
            "type": "FactSet",
            "facts": [
              {"name": "High Impact Items:", "value": "2"},
              {"name": "Medium Impact Items:", "value": "1"},
              {"name": "Analysis Date:", "value": "2026-09-03"}
            ]
          }
        ],
        "actions": [
          {
            "type": "Action.OpenUrl",
            "title": "Review in Teams Tab",
            "url": "https://teams.microsoft.com/l/app/[APP-ID]?context={tab-context}"
          }
        ]
      }
    }
  ]
}
```

---

### 2.6 Teams Tab App

**Recommendation: React + Microsoft Teams SDK + Azure AD Authentication**

**Architecture**:
```
Teams Tab App (React)
├── Authentication (MSAL)
├── Pages:
│   ├── Dashboard: User's impacted items
│   ├── CIA Detail: Full impact analysis
│   └── History: Previous analyses
├── API Layer: Calls .NET backend
└── Styling: Fluent UI components
```

**Key Endpoint for Tab App**:
```typescript
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

### 3.1 Daily Execution Flow

```
[09:00 UTC] Timer Trigger fires
    ↓
[Logic App] Retrieve last run timestamp from Table Storage
    ↓
[Parallel Execution - 5 branches]
    ├─→ Source System 1: GET changes since last run
    ├─→ Source System 2: GET changes since last run
    ├─→ Source System 3: GET changes since last run
    ├─→ Source System 4: GET changes since last run
    └─→ Source System 5: GET changes since last run
    ↓
[Aggregation] Combine all changes, deduplicate (N items)
    ↓
[Batch Processing - Chunked by 10]
    FOR EACH change:
        ├─→ Call Python CIA API (Container Instance)
        │   └─→ Receives: change_id, change_data, AI model version
        │   └─→ Returns: cia_id, impacted_items[], ai_confidence
        ├─→ Call .NET Persistence API
        │   └─→ Receives: CIA record + impacted items + assignees
        │   └─→ Stores: In Azure SQL with audit log
        └─→ On Error:
            ├─→ Retry 3 times with exponential backoff
            ├─→ Log to Application Insights
            └─→ If all retries fail: Add to dead-letter queue
    ↓
[Notification Phase]
    ├─→ Query unique assignees across all impacted items
    ├─→ Build personalized Teams cards for each user
    ├─→ Send Teams messages in parallel (rate-limited)
    └─→ Update notification status in DB
    ↓
[Completion]
    ├─→ Store run completion timestamp in Table Storage
    ├─→ Send summary to admin Teams channel
    └─→ Log metrics to Application Insights
```

### 3.2 Error Handling Strategy

```
Level 1: Transient Errors (Network, Timeouts)
└─→ Retry with exponential backoff: 1s, 2s, 4s, 8s (max 3 retries)

Level 2: Source System Failures
└─→ Skip failed source, log warning, continue with others
└─→ Alert DevOps team

Level 3: CIA Computation Failures
└─→ Move to dead-letter queue (Table Storage)
└─→ Alert ML team for investigation
└─→ Manual review required

Level 4: Persistence Failures
└─→ Rollback transaction
└─→ Retry entire CIA record
└─→ If persistent: escalate to DBA

Level 5: Notification Failures
└─→ Retry notification later (hourly for 24h)
└─→ Log to audit trail
└─→ Dashboard shows "notification pending"
```

---

## 4. Security Architecture

### 4.1 Authentication & Authorization

```
┌─────────────────────────────────────────────────────────┐
│           Azure AD / Microsoft Entra                    │
├─────────────────────────────────────────────────────────┤
│  ├─ Service Principals (Logic App, Functions, APIs)   │
│  ├─ User Identities (Teams Tab users)                 │
│  └─ Application Registrations (Teams Tab App)         │
└─────────────────────────────────────────────────────────┘

Service-to-Service Communication:
├─ Logic App → Source Systems: Managed Identity or stored credentials
├─ Logic App → Python CIA API: Container auth (ACR pull)
├─ Logic App → .NET API: Managed Identity (RBAC)
├─ .NET API → Azure SQL: Managed Identity (Azure AD auth)
└─ .NET API → Application Insights: Instrumentation key

Teams App → Backend:
├─ OAuth 2.0 flow with Azure AD
├─ Access tokens in Authorization headers
└─ Token validation in .NET API middleware
```

### 4.2 Network Security

```
Recommended: Private Endpoints + NSGs

Azure SQL Database
    └─→ Private Endpoint (no public access)
    └─→ VNet integration from App Service

Python CIA Container
    └─→ Run in Container Instance with private IP
    └─→ Access via Logic App (same VNet)
    └─→ No direct internet exposure

.NET API (App Service)
    └─→ Private Endpoint for Teams Tab app access
    └─→ IP restrictions for Logic App + Teams
    └─→ HTTPS only (TLS 1.2+)

Logic App
    └─→ ISE (Integration Service Environment) optional
    └─→ Managed connections with encryption
```

### 4.3 Data Protection

```
At Rest:
├─ Azure SQL: Transparent Data Encryption (TDE)
├─ Table Storage: Server-side encryption
├─ Soft delete enabled on all resources

In Transit:
├─ TLS 1.2+ for all API calls
├─ Mutual TLS for Container communication
├─ No secrets in logs/UI

Secrets Management:
├─ Use Azure Key Vault for:
│  ├─ Database connection strings
│  ├─ Source system credentials
│  ├─ API keys
│  └─ AI model access tokens
├─ Managed Identities for service-to-service
└─ Never commit secrets to repo
```

### 4.4 Audit & Compliance

```
Audit Trail:
├─ All CIA computations logged (with timestamp, user, model version)
├─ All database changes captured (AuditLog table)
├─ All notifications tracked (with send timestamp)
├─ Application Insights for performance metrics
├─ Log Analytics for security events
└─ Azure AD sign-in logs for Teams app access

Retention:
├─ CIA records: 7 years (regulatory)
├─ Audit logs: 3 years
├─ Application Insights: 90 days (configurable)
└─ Teams message history: As per org policy
```

---

## 5. Resilience & Disaster Recovery

### 5.1 Resilience Patterns

```
Idempotency:
├─ All operations use idempotency keys (CiaId, ChangeId)
├─ Database uniqueness constraints prevent duplicates
├─ Retry-safe API design (GET/POST idempotent)

Circuit Breaker:
├─ For source system calls (if repeated failures → skip)
├─ For Python CIA API (if container unhealthy → queue for retry)
├─ For .NET API (if DB unavailable → queue and retry)

Bulkhead Pattern:
├─ Logic App actions run in isolated contexts
├─ Container instances auto-scaled (max 50 concurrent)
├─ Database connection pooling (100 connections max)
├─ Application Insights sampling (10% in production)

Graceful Degradation:
├─ If 1-2 source systems fail → continue with others
├─ If CI computation timeout → use cached result + flag
├─ If notification fails → retry asynchronously
```

### 5.2 Backup & Recovery

```
Database Backups:
├─ Automated daily full backups (7-day retention)
├─ Hourly differential backups
├─ Point-in-time restore available
├─ Geo-replicated to secondary region

Infrastructure as Code:
├─ All resources defined in Bicep templates
├─ Version controlled in Git
├─ Automated deployment via GitHub Actions/DevOps
├─ Disaster recovery region pre-deployed (cold standby)

Application Recovery:
├─ Failed workflow executions logged for re-run
├─ Dead-letter queue for manual intervention
├─ Run history retained (searchable in Logic App)
├─ Teams notifications stored in conversation history
```

---

## 6. Monitoring & Observability

### 6.1 Key Metrics

```
Business Metrics:
├─ Daily changes detected (by source system)
├─ CIAs computed successfully/failed (rate)
├─ Average time to compute CIA (milliseconds)
├─ Users notified per run
├─ Engagement rate (Teams app clicks)

Technical Metrics:
├─ Logic App action success rate (%)
├─ Source system API latency (p50, p95, p99)
├─ Python API response time (ms)
├─ .NET API endpoint latency (ms)
├─ Database query performance (execution plans)
├─ Container instance startup time (s)

Reliability Metrics:
├─ Workflow completion rate (%)
├─ Retry attempts per run
├─ Dead-letter queue item count
├─ Notification delivery success rate
├─ API error rates by status code
```

### 6.2 Dashboards & Alerts

```
Application Insights:
├─ Overall workflow status dashboard
├─ CIA computation performance trends
├─ Error rate & exception tracking
├─ Dependency health (source systems, APIs)
└─ Custom events (workflow start, CIA created, notification sent)

Alert Rules (Action Group triggers):
├─ Workflow failure rate > 5% (24h window)
├─ Source system unavailable (30 min)
├─ CIA computation avg time > 5 min
├─ Database CPU > 80% (sustained 10 min)
├─ Dead-letter queue > 10 items
└─ Notification delivery success < 95%

Log Analytics:
├─ KQL queries for troubleshooting
├─ Performance trend analysis
├─ Security event detection
└─ Compliance reporting
```

### 6.3 Structured Logging

```json
{
  "timestamp": "2026-09-03T09:15:30.123Z",
  "workflowId": "wf-abc123",
  "runId": "run-xyz789",
  "level": "Information",
  "message": "CIA computation started",
  "properties": {
    "changeId": "CHG-12345",
    "sourceSystem": "SAP",
    "ciaId": "CIA-98765",
    "executionTimeMs": 4521,
    "aiModel": "v2.1",
    "impactedItemCount": 5,
    "assigneeCount": 8,
    "userId": "system",
    "correlationId": "corr-123"
  }
}
```

---

## 7. Cost Optimization

### 7.1 Service Cost Breakdown (Estimated Monthly)

```
Service                    | Tier              | Est. Cost | Notes
---------------------------|-------------------|-----------|----------
Logic App                  | Standard (500k)   | $150      | 500k actions/month
Azure Container Instances  | 10 vCPU-h/month   | $100      | 100 changes/day
.NET App Service           | B2 (Medium)       | $80       | 1 instance
Azure SQL Database         | Standard S1       | $30       | 10GB, auto-scaling
Table Storage              | Pay-as-you-go    | $5        | Change tracking
Application Insights       | Pay-as-you-go    | $20       | Sampling enabled
Azure Key Vault            | Standard          | $0.50     | Per 10k ops
Teams Integration          | (Included)        | $0        | Part of M365

Total Estimated Monthly:                        ~$385/month
```

### 7.2 Cost Optimization Strategies

```
1. Batch Processing:
   └─→ Process multiple changes per container invocation
   └─→ Reduce container startup overhead

2. Auto-scaling:
   └─→ App Service: Scale-down during off-peak hours
   └─→ Container Instances: Only run during scheduled windows

3. Reserved Capacity:
   └─→ 3-year RI for Azure SQL Database (40% savings)
   └─→ 1-year commitment for App Service (30% savings)

4. Caching:
   └─→ Cache CIA results for 24h (reduce recomputation)
   └─→ Cache user/assignee lookups in distributed cache (Redis)

5. Monitoring Sampling:
   └─→ Application Insights: 10% sampling in production
   └─→ Structured logging with appropriate levels
```

---

## 8. Implementation Roadmap

### Phase 1: Foundation (Weeks 1-3)
- [ ] Set up Azure resources (Resource Groups, networking)
- [ ] Create Azure SQL Database with schema
- [ ] Build .NET Persistence API (CRUD operations)
- [ ] Deploy to App Service with Managed Identity

### Phase 2: Orchestration (Weeks 4-6)
- [ ] Create Logic App with daily timer trigger
- [ ] Implement source system connectors (REST, SOAP, SQL)
- [ ] Build change aggregation logic
- [ ] Implement error handling & retry policies

### Phase 3: AI/CIA Computation (Weeks 7-9)
- [ ] Package Python AI model into Docker container
- [ ] Deploy to Azure Container Instances
- [ ] Create REST API wrapper for CIA computation
- [ ] Integrate with orchestrator

### Phase 4: Notifications (Weeks 10-11)
- [ ] Build notification logic in Logic App
- [ ] Create Adaptive Card templates
- [ ] Implement assignee deduplication
- [ ] Test Teams message delivery

### Phase 5: Teams Tab App (Weeks 12-14)
- [ ] Create React app with Teams SDK
- [ ] Implement Azure AD authentication
- [ ] Build UI for impacted items list
- [ ] Deploy to static web app or App Service

### Phase 6: Monitoring & Hardening (Weeks 15-16)
- [ ] Set up Application Insights dashboards
- [ ] Configure alert rules
- [ ] Implement audit logging
- [ ] Security review & penetration testing
- [ ] Load testing & performance tuning

### Phase 7: Launch Preparation (Weeks 17-18)
- [ ] Documentation & runbooks
- [ ] Training for operations team
- [ ] Pilot run with limited users
- [ ] Go/No-go decision

---

## 9. Technology Stack Summary

```
Orchestration:        Azure Logic Apps
Scheduling:           Recurrence Trigger (built-in)
Source Integration:   REST/SQL connectors + custom actions
Data Processing:      Azure Functions (if needed)
AI Computation:       Python + Azure Container Instances
API Layer:            .NET 6+ Web API + App Service
Database:             Azure SQL Database
Secrets:              Azure Key Vault
Caching:              Azure Cache for Redis (optional)
Messaging:            Teams API + Adaptive Cards
Authentication:       Azure AD / Entra ID + MSAL
Monitoring:           Application Insights + Log Analytics
Infrastructure:       Bicep templates
CI/CD:                GitHub Actions or Azure Pipelines
Version Control:      Git (GitHub/Azure Repos)
```

---

## 10. Sample Code References

See companion directories:
- `/python-cia-api/` - Python container for CIA computation
- `/dotnet-persistence-api/` - .NET Web API for data persistence
- `/logic-app-workflows/` - Logic App ARM templates
- `/teams-tab-app/` - React Teams Tab application
- `/infrastructure/` - Bicep IaC templates
- `/documentation/` - Detailed runbooks & guides

---

## Appendix: Decision Matrix

| Decision | Option A | Option B | Option C | Selected | Rationale |
|----------|----------|----------|----------|----------|-----------|
| Orchestration | Logic Apps | Durable Functions | Step Functions | **Logic Apps** | Visual UX + Teams integration |
| AI Service | Functions | Container Instances | AKS | **Container Instances** | Balance of control & cost |
| Database | SQL Server | Cosmos DB | PostgreSQL | **Azure SQL** | ACID compliance + audit requirements |
| App Hosting | App Service | Kubernetes | Container Instances | **App Service** | Simplicity + auto-scaling |
| Authentication | Azure AD | Auth0 | Custom JWT | **Azure AD** | First-party integration |
| Notifications | Logic Apps | Event Grid + Functions | SendGrid | **Logic Apps** | Native Teams connector |

---

## Contact & Support

- **Architecture Review**: Contact your Azure Solutions Architect
- **Implementation Help**: Engage Azure FastTrack for eligible organizations
- **Support**: Open Azure Support case for production issues

---

**Document Version**: 1.0  
**Last Updated**: 2026-09-03  
**Owner**: Cloud Architecture Team