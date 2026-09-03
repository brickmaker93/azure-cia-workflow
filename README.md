# Azure Change Impact Analysis (CIA) Workflow

## Overview

This repository contains the architecture design and implementation guidance for a resilient, Azure-based Change Impact Analysis (CIA) system. The workflow automatically:

1. **Detects changes** across 5 source systems on a daily schedule
2. **Computes impact analysis** using an AI-powered Python API
3. **Persists results** via a .NET Web API to Azure SQL Database
4. **Notifies stakeholders** via Microsoft Teams with actionable summaries
5. **Provides a Teams Tab app** for users to review impacted items

## Quick Start

### Prerequisites

- Azure subscription with appropriate permissions
- .NET 6+ SDK
- Python 3.9+ (for AI service)
- Docker (for containerization)
- Node.js 16+ (for Teams Tab app)
- GitHub or Azure DevOps account

### Architecture Components

```
Timer Trigger (Daily)
    ↓
Logic App Orchestrator
    ↓
Source Systems (5 systems in parallel)
    ↓
Change Aggregator
    ↓
Python CIA Service (Container Instances)
    ↓
.NET Persistence API
    ↓
Azure SQL Database
    ↓
Teams Notification Service
    ↓
Microsoft Teams + Tab App
```

## Documentation

- **[ARCHITECTURE.md](./ARCHITECTURE.md)** - Complete architecture design and service selection
- **[DATABASE_SCHEMA.sql](./DATABASE_SCHEMA.sql)** - Azure SQL schema definition
- **[IMPLEMENTATION_GUIDE.md](./docs/IMPLEMENTATION_GUIDE.md)** - Step-by-step implementation
- **[API_SPECIFICATION.md](./docs/API_SPECIFICATION.md)** - .NET API endpoints
- **[MONITORING_GUIDE.md](./docs/MONITORING_GUIDE.md)** - Application Insights setup
- **[SECURITY_GUIDELINES.md](./docs/SECURITY_GUIDELINES.md)** - Security best practices

## Key Technologies

| Component | Technology |
|-----------|------------|
| **Orchestration** | Azure Logic Apps |
| **AI Computation** | Python + Azure Container Instances |
| **Data Persistence** | .NET 6+ Web API + Azure SQL Database |
| **Notifications** | Microsoft Teams API + Adaptive Cards |
| **User Interface** | React + Microsoft Teams SDK |
| **Authentication** | Azure AD / Entra ID + MSAL |
| **Monitoring** | Application Insights + Log Analytics |
| **Infrastructure** | Bicep (IaC) |

## Project Structure

```
aws-cia-workflow/
├── ARCHITECTURE.md                 # Main architecture document
├── DATABASE_SCHEMA.sql              # SQL schema definition
├── README.md                        # This file
├── docs/
│   ├── IMPLEMENTATION_GUIDE.md      # Step-by-step setup
│   ├── API_SPECIFICATION.md         # .NET API endpoints
│   ├── MONITORING_GUIDE.md          # Observability setup
│   └── SECURITY_GUIDELINES.md       # Security best practices
├── infrastructure/
│   ├── main.bicep                   # Main IaC template
│   ├── parameters.json              # Deployment parameters
│   └── deploy.sh                    # Deployment script
├── dotnet-persistence-api/
│   ├── src/                         # .NET source code
│   ├── Dockerfile                   # Container image
│   └── README.md                    # API documentation
├── python-cia-api/
│   ├── app.py                       # Flask/FastAPI application
│   ├── requirements.txt             # Python dependencies
│   ├── Dockerfile                   # Container image
│   └── README.md                    # CIA service documentation
├── teams-tab-app/
│   ├── src/                         # React source code
│   ├── public/                      # Static assets
│   ├── package.json                 # Node dependencies
│   └── README.md                    # Teams app documentation
└── workflows/
    └── logic-app-definition.json    # Logic App ARM template
```

## Implementation Timeline

- **Phase 1 (Weeks 1-3)**: Foundation & database setup
- **Phase 2 (Weeks 4-6)**: Orchestration & source integration
- **Phase 3 (Weeks 7-9)**: AI/CIA computation service
- **Phase 4 (Weeks 10-11)**: Notifications & Teams integration
- **Phase 5 (Weeks 12-14)**: Teams Tab app development
- **Phase 6 (Weeks 15-16)**: Monitoring & security hardening
- **Phase 7 (Weeks 17-18)**: Launch & go-live

## Estimated Costs

**Monthly Azure costs**: ~$385 (see ARCHITECTURE.md for breakdown)

## Key Features

✅ **Daily automated execution** via Logic App timer trigger  
✅ **Multi-source change detection** with deduplication  
✅ **AI-powered impact analysis** with confidence scores  
✅ **Resilient error handling** with retry policies  
✅ **Teams notifications** with Adaptive Cards  
✅ **Teams Tab app** for impact item review  
✅ **Comprehensive audit logging** for compliance  
✅ **Application Insights monitoring** for observability  
✅ **Managed identities** for secure authentication  
✅ **Infrastructure as Code** (Bicep templates)  

## Security

- All inter-service communication uses Managed Identities
- Azure SQL Database with Transparent Data Encryption (TDE)
- Private Endpoints for all PaaS services
- Azure Key Vault for secrets management
- Azure AD authentication for Teams app
- Full audit trail of all operations
- Network isolation via VNet integration

## Monitoring & Alerts

- Real-time dashboards in Application Insights
- Automated alerts for failures and performance issues
- Log Analytics for troubleshooting and compliance
- Dead-letter queue for failed items
- Email/Teams notifications to operations team

## Contributing

Please refer to [CONTRIBUTING.md](./CONTRIBUTING.md) for guidelines.

## Support

For issues, questions, or feedback:
- Open a GitHub Issue
- Contact the cloud architecture team
- Submit a PR with improvements

## License

This project is licensed under the [MIT License](./LICENSE).

## Next Steps

1. Review [ARCHITECTURE.md](./ARCHITECTURE.md) for complete design details
2. Review [IMPLEMENTATION_GUIDE.md](./docs/IMPLEMENTATION_GUIDE.md) to begin setup
3. Clone this repository and customize for your environment
4. Deploy infrastructure using Bicep templates
5. Implement .NET Persistence API
6. Package and deploy Python CIA Service
7. Configure Logic App workflows
8. Build and deploy Teams Tab app
9. Conduct UAT and testing
10. Launch to production

---

**Version**: 1.0  
**Last Updated**: 2026-09-03  
**Status**: Ready for implementation