# LAB: Monitoring & Observability — App + Database

Azure demo environment showcasing end-to-end observability across a full-stack application with both PaaS and IaaS database workloads.

## Architecture

```
                    ┌──────────────────┐
                    │  Azure Front Door │  ← Edge logs, health probes, WAF logs
                    └────────┬─────────┘
                             │
                ┌────────────┴────────────┐
                │                         │
        ┌───────▼───────┐       ┌─────────▼────────┐
        │  App Service   │       │   App Service     │
        │  (Frontend)    │       │   (Backend API)   │
        └───────┬───────┘       └─────────┬────────┘
                │                         │
                │    ┌────────────────────┤
                │    │                    │
        ┌───────▼────▼──┐       ┌────────▼─────────┐
        │  Application   │       │  Azure SQL DB     │
        │  Insights      │       │  (PaaS)           │
        └───────┬───────┘       └────────┬─────────┘
                │                         │
        ┌───────▼─────────────────────────▼────────┐
        │         Log Analytics Workspace           │
        └───────▲──────────────────────────────────┘
                │
        ┌───────┴─────────┐
        │  Azure VM with   │
        │  SQL Server (IaaS)│  ← Boot diag, AMA, perf counters, event logs
        └─────────────────┘
```

## Resources Deployed

| Resource | Purpose | Observability |
|----------|---------|---------------|
| **Log Analytics Workspace** | Central log sink | KQL queries, workbooks, alerts |
| **Application Insights** | APM for App Services | Requests, dependencies, exceptions, distributed tracing |
| **App Service (Frontend)** | Web frontend | HTTP logs, app logs, platform metrics, health checks |
| **App Service (Backend API)** | REST API | HTTP logs, dependency tracking, SQL call tracing |
| **Azure SQL Database** | PaaS database | Audit logs, query stats, deadlocks, DTU metrics |
| **Azure VM + SQL Server** | IaaS database | Boot diagnostics, perf counters, event logs, SQL metrics |
| **Azure Front Door** | Global load balancer | Access logs, health probes, WAF logs, latency metrics |

## Prerequisites

- Azure subscription
- GitHub account
- Azure CLI installed locally (for Service Principal creation and optional manual deployment)

## Getting Started

### Step 1 — Create an Azure Service Principal

Create a Service Principal with Contributor access to your subscription. Replace the subscription ID with your own if forking this project:

```bash
az login
az account set --subscription <YOUR_SUBSCRIPTION_ID>

az ad sp create-for-rbac \
  --name "github-lab-monitoring" \
  --role Contributor \
  --scopes /subscriptions/<YOUR_SUBSCRIPTION_ID> \
  --sdk-auth
```

> **Save the entire JSON output** — you will need it for the `AZURE_CREDENTIALS` secret.

The output looks like:
```json
{
  "clientId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "clientSecret": "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "subscriptionId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  ...
}
```

### Step 2 — Add GitHub Repository Secrets

Go to **GitHub repo > Settings > Secrets and variables > Actions > New repository secret** and add:

| Secret | Description | Required |
|--------|-------------|----------|
| `AZURE_CREDENTIALS` | The full JSON output from `az ad sp create-for-rbac` | **Yes** |
| `AZURE_SUBSCRIPTION_ID` | Your Azure subscription ID | **Yes** |
| `AZURE_TENANT_ID` | Your Entra ID (Azure AD) tenant ID | **Yes** |
| `VM_ADMIN_PASSWORD` | Password for the SQL VM admin (min 12 chars, 3/4 categories) | **Yes** |
| `SQL_ENTRA_ADMIN_OBJECT_ID` | Entra ID object ID of the SQL admin user or group | **Yes** (if `entraOnly`) |
| `SQL_ENTRA_ADMIN_LOGIN` | Entra ID UPN or group name for SQL admin | **Yes** (if `entraOnly`) |
| `SQL_ADMIN_PASSWORD` | Password for Azure SQL PaaS admin (min 8 chars, 3/4 categories) | Only if `sqlAndEntra` |
| `SQL_AUTH_MODE` | `entraOnly` (default) or `sqlAndEntra` | No |
| `SQL_ADMIN_LOGIN` | Custom SQL admin username (default: `sqladminuser`) | No |
| `VM_ADMIN_USERNAME` | Custom VM admin username (default: `vmadminuser`) | No |

> To find your Entra ID object ID and UPN, run:
> ```bash
> az ad signed-in-user show --query "{objectId:id, upn:userPrincipalName}" -o table
> ```

### Step 3 — Customize Deployment Parameters

All tunable infrastructure values are centralized in **`deploy-config.cfg`** (resource group name, region, SKUs, networking, retention, etc.). Edit this single file to customize your deployment — no need to touch the workflow.

For secrets and identity values, use GitHub Secrets (Step 2).

## Azure SQL Server Authentication

The SQL module supports **two authentication modes**, configurable via the `SQL_AUTH_MODE` secret:

| Mode | Secret Value | Description |
|------|-------------|-------------|
| **Entra ID Only** (default) | `entraOnly` | Uses Microsoft Entra ID exclusively. No SQL username/password. Compliant with corporate policies (e.g., MCAPS). Requires `SQL_ENTRA_ADMIN_OBJECT_ID` and `SQL_ENTRA_ADMIN_LOGIN` secrets. |
| **SQL + Entra ID** | `sqlAndEntra` | Hybrid mode with both SQL authentication and Entra ID admin. Requires `SQL_ADMIN_PASSWORD` (and optionally `SQL_ADMIN_LOGIN`) in addition to the Entra secrets. |

> **Tip:** If your tenant enforces Entra-only authentication via Azure Policy, use `entraOnly` (the default). Set `sqlAndEntra` only in environments that explicitly allow SQL authentication.

## Deployment Options

### Option A — Automatic via Git Push (Default)

The GitHub Actions workflow triggers automatically on every push to `main`:

```bash
git add -A
git commit -m "Deploy monitoring lab"
git push origin main
```

The pipeline will: **Validate** → **Display Parameters** → **Deploy**. Check the **Actions** tab in GitHub to monitor progress.

### Option B — Manual Trigger via GitHub UI

1. Go to **GitHub repo > Actions**
2. Select **"Deploy Azure Monitoring & Observability Lab"**
3. Click **"Run workflow"**
4. Customize: resource group name, location, project prefix, environment
5. Click **"Run workflow"** to start

### Option C — Local CLI Deployment

For local deployment without GitHub Actions:

```bash
# Login to Azure
az login --tenant <YOUR_TENANT_ID>
az account set --subscription <YOUR_SUBSCRIPTION_ID>

# Create resource group
az group create --name rg-lab-monitoring-observability --location centralus

# Set credentials as environment variables
export SQL_ENTRA_ADMIN_OBJECT_ID='<YOUR_ENTRA_OBJECT_ID>'
export SQL_ENTRA_ADMIN_LOGIN='<YOUR_ENTRA_UPN>'
export VM_ADMIN_PASSWORD='An0therStr0ngP@ss!'

# Deploy using the parameters file (uses entraOnly mode by default)
az deployment group create \
  --resource-group rg-lab-monitoring-observability \
  --template-file main.bicep \
  --parameters main.bicepparam

# Or deploy with sqlAndEntra mode (SQL + Entra ID authentication)
export SQL_ADMIN_PASSWORD='YourStr0ngP@ssword!'
az deployment group create \
  --resource-group rg-lab-monitoring-observability \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters sqlAuthMode=sqlAndEntra
```

> **PowerShell users:** Use `$env:VM_ADMIN_PASSWORD = '...'` instead of `export`.

## Cleanup

Delete all resources when the lab is no longer needed:

```bash
az group delete --name rg-lab-monitoring-observability --yes --no-wait
```

## Project Structure

```
├── .github/workflows/
│   └── deploy.yml              # GitHub Actions CI/CD pipeline
├── modules/
│   ├── log-analytics.bicep     # Log Analytics Workspace
│   ├── app-insights.bicep      # Application Insights (workspace-based)
│   ├── app-service-plan.bicep  # Shared App Service Plan
│   ├── app-service-frontend.bicep  # Frontend App Service + diagnostics
│   ├── app-service-backend.bicep   # Backend API App Service + diagnostics
│   ├── sql-database.bicep      # Azure SQL Server + Database + diagnostics (Entra ID / SQL auth)
│   ├── sql-vm.bicep            # VM with SQL Server + AMA + DCR
│   └── front-door.bicep        # Azure Front Door + diagnostics
├── deploy-config.cfg           # ← Single file for all tunable deployment parameters
├── main.bicep                  # Main orchestration template
├── main.bicepparam             # Bicep parameters file (for local CLI deployments)
├── topology.mmd                # Mermaid topology diagram
├── TOPOLOGY.txt                # Plain-text topology description
└── README.md
```

## Observability Features by Layer

### Application Layer (Application Insights)
- Request/response telemetry
- Dependency tracking (SQL, HTTP, etc.)
- Exception and failure logging
- Distributed tracing (correlation across frontend ↔ backend)
- Live Metrics stream
- Application Map (service topology)

### Platform Layer (App Service Diagnostics)
- HTTP request/response logs
- Application console logs
- Platform-level events
- Health check monitoring

### Database Layer — PaaS (Azure SQL Diagnostics)
- SQL audit logs (who did what)
- Query Store runtime & wait statistics
- Automatic tuning recommendations
- Deadlock and timeout detection
- DTU/CPU usage metrics

### Database Layer — IaaS (VM + Azure Monitor Agent)
- Windows performance counters (CPU, memory, disk)
- SQL Server-specific counters (connections, batch requests, buffer cache)
- Windows Event Logs (Application + System)
- Boot diagnostics (screenshots + serial log)

### Edge Layer (Front Door Diagnostics)
- Access logs (every request at the edge)
- Health probe results
- WAF decision logs
- Request latency and origin health metrics

## License

This project is for educational/demo purposes.
