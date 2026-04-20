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
        │  App Service  │       │   App Service    │
        │  (Frontend)   │       │   (Backend API)  │
        └───────┬───────┘       └─────────┬────────┘
                │                         │
                │    ┌────────────────────┤
                │    │                    │
        ┌───────▼────▼──┐       ┌────────▼─────────┐
        │  Application  │       │  Azure SQL DB    │
        │  Insights     │       │  (PaaS)          │
        └───────┬───────┘       └────────┬─────────┘
                │                         │
        ┌───────▼─────────────────────────▼────────┐
        │         Log Analytics Workspace           │
        └───────▲──────────────────────────────────┘
                │
        ┌───────┴───────────┐
        │  Azure VM with    │
        │  SQL Server (IaaS)│  ← Boot diag, AMA, perf counters, event logs
        └───────────────────┘
```

## Resources Deployed

| Resource | Purpose | Observability |
|----------|---------|---------------|
| **Log Analytics Workspace** | Central log sink | KQL queries, workbooks, alerts |
| **Application Insights** | APM for App Services | Requests, dependencies, exceptions, distributed tracing |
| **App Service (Frontend)** | Web frontend | HTTP logs, app logs, platform metrics, health checks |
| **App Service (Backend API)** | REST API | HTTP logs, dependency tracking, SQL call tracing |
| **Azure SQL Database** | PaaS database | Audit logs, query stats, deadlocks, DTU metrics |
| **Azure VM + SQL Server** | IaaS database | Boot diagnostics, perf counters, event logs, SQL metrics, NSG/PIP/NIC diagnostics |
| **Azure Front Door** | Global load balancer | Access logs, health probes, WAF logs, latency metrics |
| **Availability Tests** | Proactive uptime monitoring | URL ping tests from 5 global locations (Frontend + Backend API) |
| **Azure Monitor Workbook** | E2E observability dashboard | 8-tab workbook: Edge → App → Dependencies → DB → SLO → Investigations |
| **Azure Monitor Alerts** *(optional)* | Proactive alert rules | 4 log alerts (App Insights KQL) + 2 metric alerts (App Service 5xx) + Action Group |
| **Azure Managed Grafana** *(optional)* | Grafana dashboard | 18-panel dashboard mirroring the workbook (Standard X1 ~$62/mo, X2 ~$124/mo + $6/user) |

> **Cost disclaimer:** All cost estimates in this project (code comments, config files, and this README) are approximate as of April 2026. Azure pricing changes over time — always confirm current pricing at [Azure Pricing](https://azure.microsoft.com/pricing/) before deploying.

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

The Service Principal also needs **User Access Administrator** to create role assignments (e.g., Monitoring Reader for Grafana, SQL Entra admin). Assign it at the resource group scope after the first deployment creates the RG, or at the subscription scope:

```bash
# Get the SP's appId from the JSON output above
SP_APP_ID="<clientId from JSON output>"

# Option A — Subscription scope (broader, simpler)
az role assignment create \
  --assignee "$SP_APP_ID" \
  --role "User Access Administrator" \
  --scope /subscriptions/<YOUR_SUBSCRIPTION_ID>

# Option B — Resource Group scope (narrower, more secure — run after RG is created)
az role assignment create \
  --assignee "$SP_APP_ID" \
  --role "User Access Administrator" \
  --scope /subscriptions/<YOUR_SUBSCRIPTION_ID>/resourceGroups/rg-lab-monitoring-observability
```

> **Why is this needed?** The deployment creates role assignments for managed identities (e.g., Monitoring Reader for Grafana, Grafana Admin for UI access). Without `User Access Administrator`, the pipeline will fail with `Authorization failed for Microsoft.Authorization/roleAssignments/write`.

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
| `ALERT_EMAIL_ADDRESS` | Email address for alert notifications | Only if `DEPLOY_ALERTS=true` |

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
export VM_ADMIN_PASSWORD='<YOUR_STRONG_PASSWORD>'

# Deploy using the parameters file (uses entraOnly mode by default)
az deployment group create \
  --resource-group rg-lab-monitoring-observability \
  --template-file main.bicep \
  --parameters main.bicepparam

# Or deploy with sqlAndEntra mode (SQL + Entra ID authentication)
export SQL_ADMIN_PASSWORD='<YOUR_STRONG_PASSWORD>'
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
│   ├── sql-vm.bicep            # VM with SQL Server + AMA + DCR + NSG/PIP/NIC diagnostics
│   ├── front-door.bicep        # Azure Front Door + diagnostics
│   ├── availability-tests.bicep    # Standard URL ping tests (Frontend + Backend)
│   ├── workbook-v2.bicep       # E2E Observability Workbook (Bicep wrapper)
│   ├── workbook-v2.json        # Workbook definition (raw JSON, 8 tabs)
│   ├── alerts-demo.bicep       # Azure Monitor Alerts (Action Group + Log/Metric alerts)
│   ├── grafana.bicep           # Azure Managed Grafana (optional, incurs cost)
│   └── grafana-dashboard.json  # Grafana dashboard definition (18 panels, 8 rows)
├── src/
│   ├── backend/                # ASP.NET Core 8 Web API (PaaS + IaaS)
│   │   ├── BackendApi.csproj
│   │   ├── Program.cs          # Minimal API: /api/* (PaaS) + /api/vm/* (IaaS)
│   │   └── appsettings.json
│   └── frontend/               # ASP.NET Core 8 Razor Pages dashboard
│       ├── FrontendApp.csproj
│       ├── Program.cs
│       ├── Pages/
│       │   ├── Index.cshtml    # Dashboard — PaaS + IaaS summary cards + tables
│       │   ├── Products.cshtml # Product catalog (PaaS — AdventureWorksLT)
│       │   ├── Customers.cshtml # Customer directory (PaaS)
│       │   ├── Orders.cshtml   # Sales order history (PaaS)
│       │   ├── Employees.cshtml # Employee directory (IaaS — AdventureWorks2022)
│       │   └── Departments.cshtml # Department listing (IaaS)
│       └── wwwroot/css/site.css
├── deploy-config.cfg           # ← Single file for all tunable deployment parameters
├── main.bicep                  # Main orchestration template
├── main.bicepparam             # Bicep parameters file (for local CLI deployments)
├── topology.mmd                # Mermaid topology diagram
├── TOPOLOGY.txt                # Plain-text topology description
└── README.md
```

## Demo Applications

The lab includes two working .NET 8 applications that query **both** the Azure SQL PaaS and SQL VM IaaS databases:

### Application Data Flow

```
Frontend (Razor Pages)
    │
    ▼ HTTP calls
Backend API (.NET 8 Minimal API)
    │
    ├──► Azure SQL PaaS (AdventureWorksLT)       ← ConnectionStrings__DefaultConnection
    │    /api/products, /api/customers,              SQL auth (User ID + Password)
    │    /api/orders, /api/categories
    │
    └──► SQL Server VM (AdventureWorks2022)       ← ConnectionStrings__SqlVmConnection
         /api/vm/employees, /api/vm/departments      SQL auth via VM public IP:1433
```

### Backend API (`src/backend/`)

Minimal ASP.NET Core Web API with endpoints for both databases:

**Azure SQL PaaS (AdventureWorksLT)**

| Endpoint | Description |
|----------|-------------|
| `GET /api/health` | Health check (returns status + timestamp) |
| `GET /api/products` | Top 50 products from `SalesLT.Product` |
| `GET /api/categories` | All product categories from `SalesLT.ProductCategory` |
| `GET /api/customers` | Top 50 customers from `SalesLT.Customer` |
| `GET /api/orders` | Top 50 sales orders from `SalesLT.SalesOrderHeader` |

**SQL Server VM — IaaS (AdventureWorks2022)**

| Endpoint | Description |
|----------|-------------|
| `GET /api/vm/health` | VM SQL health check |
| `GET /api/vm/employees` | Top 50 employees from `HumanResources.Employee` + `Person.Person` |
| `GET /api/vm/departments` | All departments with employee counts from `HumanResources.Department` |

### Frontend App (`src/frontend/`)

ASP.NET Core Razor Pages dashboard with Bootstrap 5 UI:

- **Dashboard** — Summary cards and recent data from both PaaS and IaaS databases
- **Products** — Full product catalog with pricing, colors, and sizes (PaaS)
- **Customers** — Customer directory with email and company info (PaaS)
- **Orders** — Sales order history with status badges and totals (PaaS)
- **Employees** — Employee directory with job titles and departments (IaaS)
- **Departments** — Department listing with employee counts (IaaS)

### Sample Data

| Database | Location | Sample Data |
|----------|----------|-------------|
| Azure SQL Database (PaaS) | `sql-<prefix>-<env>` | **AdventureWorksLT** — Products, Customers, Orders (auto-provisioned via `sampleName`) |
| SQL Server on VM (IaaS) | `vm-sql-<prefix>-<env>` | **AdventureWorks2022** — Full database (restored via CustomScriptExtension) |

### Application URLs (after deployment)

```
Frontend:   https://app-frontend-<PROJECT_PREFIX>-<ENVIRONMENT>.azurewebsites.net
Backend:    https://app-backend-<PROJECT_PREFIX>-<ENVIRONMENT>.azurewebsites.net
API Health: https://app-backend-<PROJECT_PREFIX>-<ENVIRONMENT>.azurewebsites.net/api/health
```

## Azure Monitor Workbook — E2E Observability

The lab includes a custom-built **Azure Monitor Workbook** deployed as Infrastructure-as-Code via Bicep. It provides a single pane of glass across all monitoring layers.

### Workbook Tabs

| Tab | Title | What It Shows |
|-----|-------|---------------|
| **A** | E2E Overview | Health badges per layer, request volume sparklines, latency percentiles, top errors |
| **B** | Edge: Front Door | Request trends, edge latency percentiles, HTTP 4xx/5xx rates, top failing URLs, top edge locations (POP) |
| **C** | Frontend (FE) | Request rate & failures, response time distribution, exceptions, top operations, HTTP logs |
| **D** | Backend (API) | Same as FE plus SQL dependency call breakdown, top API endpoints |
| **E** | Dependencies & Flow | FE→BE HTTP calls, BE→SQL calls, latency waterfall by layer, failed dependency breakdown |
| **F** | Database (SQL) | **PaaS**: DTU/CPU, deadlocks, query wait stats. **IaaS**: CPU/memory, SQL counters, disk I/O, network, Windows events. Both: app-side SQL dependency latency |
| **G** | Availability / SLO | Availability test results (%), success rate SLI, P95 latency vs target, error budget burn |
| **H** | Investigations | Parameter-driven drilldown: operation picker, severity filter, request grid, traces, exceptions, failed dependencies, Windows event log |

### Shared Parameters

All tabs share these parameters:

| Parameter | Type | Description |
|-----------|------|-------------|
| **TimeRange** | Time picker | Default: Last 24 hours. Options: 1h, 4h, 24h, 3d, 7d |
| **Subscription** | Subscription picker | Scopes resource graph queries |
| **Application Insights** | Resource picker | Targets App Insights for APM queries |
| **Log Analytics Workspace** | Resource picker | Targets LAW for infrastructure logs |
| **Front Door Profile** | Resource picker | Targets AFD for edge metrics |

### Data Sources Used

```
Workbook queries pull from:
  ├── Application Insights (APM)
  │    ├── requests          → FE/BE request rate, latency, failures
  │    ├── dependencies      → FE→BE, BE→SQL call metrics
  │    ├── exceptions        → Error tracking
  │    ├── traces            → Application log messages
  │    └── availabilityResults → URL ping test results (SLO)
  │
  └── Log Analytics Workspace (Infrastructure)
       ├── AzureDiagnostics  → Front Door access/probe logs (FrontDoorAccessLog category),
       │                       SQL diagnostics (QueryStoreWaitStatistics, etc.)
       ├── AzureMetrics      → SQL DTU/CPU, connection metrics
       ├── Perf              → VM guest OS counters (CPU, memory, disk, SQL, network)
       ├── Event             → Windows Event Log (errors, warnings)
       └── AppServiceHTTPLogs → App Service HTTP status codes
```

### Accessing the Workbook

After deployment, navigate to:
1. **Azure Portal** → **Monitor** → **Workbooks**
2. Or: **Application Insights** → **Workbooks** → `E2E Observability — <prefix>-<env>`

## Availability Tests

Two standard URL ping tests are deployed, running every 5 minutes from 5 global locations:

| Test | URL | Validation |
|------|-----|------------|
| **Frontend Health** | `https://app-frontend-<prefix>-<env>.azurewebsites.net/` | HTTP 200 + valid SSL |
| **Backend API Health** | `https://app-backend-<prefix>-<env>.azurewebsites.net/api/health` | HTTP 200 + response contains "healthy" + valid SSL |

Results appear in the **Availability / SLO** tab (Tab G) of the workbook and in Application Insights → Availability.

## Azure Monitor Alerts (Optional)

The lab includes an optional set of **Azure Monitor alert rules** that demonstrate both log-based and metric-based alerting. Alerts are **disabled by default** — enable them by setting `DEPLOY_ALERTS=true` in `deploy-config.cfg`.

### Enabling Alerts

1. Set `DEPLOY_ALERTS=true` in `deploy-config.cfg`
2. Add the `ALERT_EMAIL_ADDRESS` secret in GitHub (or set as environment variable for local deployments)
3. Push to trigger deployment

### Alert Rules

| # | Name | Type | Severity | Condition | Frequency / Window |
|---|------|------|----------|-----------|-------------------|
| 1 | **App-ErrorRate-High** | Log (KQL) | Sev2 | Failure rate > 5% (min 20 requests) | PT1M / PT5M |
| 2 | **App-Latency-Avg-High** | Log (KQL) | Sev3 | Avg request duration > 2000 ms | PT1M / PT5M |
| 3 | **Dependency-SQL-Latency-High** | Log (KQL) | Sev2 | Avg SQL dependency duration > 1500 ms (by target) | PT1M / PT5M |
| 4 | **Dependency-SQL-FailureRate-High** | Log (KQL) | Sev2 | SQL dependency failure rate > 2% (by target, min 20 calls) | PT1M / PT5M |
| 5 | **FE-Http5xx-High** | Metric | Sev2 | Frontend App Service HTTP 5xx > 5 (total) | PT1M / PT5M |
| 6 | **BE-Http5xx-High** | Metric | Sev2 | Backend App Service HTTP 5xx > 5 (total) | PT1M / PT5M |

### Action Group

All alerts route to a single Action Group (`ag-alerts-<prefix>-<env>`) with one email receiver. The email address is configured via the `ALERT_EMAIL_ADDRESS` secret.

### Viewing Alerts

- **Azure Portal** → **Monitor** → **Alerts** to see fired alerts
- **Azure Portal** → **Monitor** → **Alert rules** to manage rule definitions
- Log alert KQL queries can also be copied into Workbooks or Log Analytics (see comments in `modules/alerts-demo.bicep`)

## Azure Managed Grafana Dashboard (Optional)

The lab includes an optional **Azure Managed Grafana** dashboard that mirrors the Azure Monitor Workbook v2, providing an alternative visualization experience with Grafana's rich panel ecosystem.

> **Why not Azure Portal Dashboard (native)?** The native Azure Portal Dashboard only supports pinned metric charts and basic Log Analytics query tiles. It cannot render KQL-driven panels with custom visualizations, row-based collapsible layouts, or the full set of chart types (gauge, stat, timeseries, table) required to replicate the 8-tab observability report. Grafana's Azure Monitor data source plugin provides full KQL query support with rich panel options.

### Free Alternative: Azure Monitor Dashboards with Grafana (Preview)

If you do not want to incur costs, you can use the **Azure Monitor dashboards with Grafana** feature — a free, Azure-native Grafana experience built directly into the Azure Portal:

1. In the **Azure Portal**, open **Azure Monitor**
2. In the service menu, select **Dashboards with Grafana (preview)** → **New** → **Import**
3. Upload the `modules/grafana-dashboard.json` file from this repository
4. Before importing, manually replace the placeholders in the JSON:
   - `__APP_INSIGHTS_ID__` → your Application Insights resource ID
   - `__LAW_ID__` → your Log Analytics workspace resource ID
   - `__NAME_SUFFIX__` → your project name suffix (e.g., `labmonitor-dev`)
5. Select **Load**, enter a name, and choose the subscription/resource group

**Limitations of the free tier** (compared to Azure Managed Grafana Standard):
- Maximum 1 workspace per subscription, 20 dashboards, 5 data sources
- No alerting, email, reporting, or private networking
- No SLA, on-demand hosting resources
- Only Azure data source plugins

### Automated Deployment: Azure Managed Grafana Standard (Paid)

For automated pipeline deployment with full features, the lab uses **Azure Managed Grafana Standard** tier:

| Instance Size | Standard Units | Approximate Cost | Alert Rules |
|---------------|---------------|------------------|-------------|
| **X1** (default) | 2 SU | ~$0.086/hr (~$62/mo) + $6/active user | 500 |
| **X2** (larger) | 4 SU | ~$0.172/hr (~$124/mo) + $6/active user | 1,000 |

> **Costs shown are approximate as of April 2026.** Always confirm current pricing at [Azure Managed Grafana pricing](https://azure.microsoft.com/pricing/details/managed-grafana/) before deploying.
>
> **Delete the Grafana resource when no longer needed** to stop charges. The Essential tier has been deprecated by Microsoft (March 2026) — only Standard is supported.

### Enabling Grafana (Pipeline)

1. Set `DEPLOY_GRAFANA=true` in `deploy-config.cfg`
2. Optionally change `GRAFANA_SKU_SIZE=X2` for more capacity (default: `X1`)
3. Push to trigger deployment

The pipeline will:
1. Deploy the Grafana instance via Bicep (Standard tier, selected size)
2. Assign `Monitoring Reader` role to the Grafana managed identity
3. Assign `Grafana Admin` role to the deployment SP
4. Import the 18-panel dashboard with resolved resource IDs

### Dashboard Panels (18 panels, 8 rows)

| Row | Section | Panels |
|-----|---------|--------|
| A | E2E Overview | Total Requests (stat), Failure Rate % (gauge), Avg Response Time (stat), Dependency Failures (stat) |
| B | Edge: Front Door | Request Trend (timeseries), 4xx/5xx Error Rate (timeseries) |
| C | Frontend | Requests & Failures (timeseries), Response Time P50/P90/P95 (timeseries) |
| D | Backend API | Requests & Failures (timeseries), Response Time P50/P90/P95 (timeseries) |
| E | Dependencies | Dependency Calls by Type (timeseries), SQL Dependency Latency (timeseries) |
| F | Database | SQL PaaS DTU % (timeseries), VM CPU & Memory (timeseries) |
| G | Availability / SLO | Test Results by Name (timeseries), Overall SLI (gauge) |
| H | Investigations | Recent Exceptions (table), Failed Requests (table) |

### Accessing Grafana

After deployment, the Grafana URL is printed in the pipeline output. You can also find it:
- **Azure Portal** → **Resource Group** → `grafana-<prefix>-<env>` → **Overview** → **Endpoint**
- Or via CLI: `az grafana show -g <rg> -n grafana-<prefix>-<env> --query properties.endpoint -o tsv`

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

## Security Considerations

This lab environment includes several security-relevant configurations. Review and tighten these before adapting for production use:

| Area | Default | Recommendation |
|------|---------|----------------|
| **NSG Rules** | RDP (3389) and SQL (1433) allow `*` by default | Set `ALLOWED_SOURCE_ADDRESS` in `deploy-config.cfg` to your IP or CIDR |
| **CORS Policy** | Backend restricts origins to the frontend App Service URL via `ALLOWED_ORIGINS` env var | Add Front Door endpoint if needed; falls back to `AllowAnyOrigin` if not set |
| **SQL VM Access** | Public IP with `connectivityType: PUBLIC` | Consider switching to `PRIVATE` + Azure Bastion for production |
| **Azure SQL Public Access** | `publicNetworkAccess: Enabled` with Azure Services firewall rule | Use Private Endpoints for production workloads |
| **TrustServerCertificate** | `True` for Azure AD Default and SQL VM connections | Set to `False` and provision proper certificates for production |
| **Sensitive Secrets** | Passed via GitHub Secrets; no hardcoded passwords in code | Ensure all `SQL_ADMIN_PASSWORD`, `VM_ADMIN_PASSWORD` secrets are set |
| **CI/CD Logging** | Subscription ID and Tenant ID are masked in workflow output | Review workflow logs after runs to verify no secrets leak |

> **Important:** The `deploy-config.cfg` file contains resource group names, regions, and SKUs — not secrets. All sensitive values (passwords, client secrets, object IDs) must be stored as **GitHub Secrets**.

## License

This project is for educational/demo purposes.
