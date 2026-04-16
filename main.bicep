// ============================================================================
// LAB: Monitoring & Observability - App + Database Demo Environment
// ============================================================================
//
// DISCLAIMER:
// This template is provided for EDUCATIONAL and DEMO purposes only.
// It deploys Azure resources that WILL INCUR COSTS on your subscription.
// Resources include: App Services, Azure SQL, Virtual Machines, Front Door,
// Log Analytics, and Application Insights.
//
// YOU are solely responsible for:
//   - Reviewing all parameters and configurations before deployment
//   - Monitoring and managing costs in your Azure subscription
//   - Securing credentials (admin usernames/passwords) used in this template
//   - Deleting the resource group when the lab is no longer needed
//
// The authors assume NO liability for charges, data loss, or security
// incidents resulting from the use of this template.
//
// To tear down all resources:  az group delete --name <resource-group> --yes
//
// ============================================================================
// This template deploys a full-stack Azure environment instrumented with
// observability components: Log Analytics, Application Insights, diagnostic
// settings, and VM monitoring agents.

targetScope = 'resourceGroup'

// -- Parameters --
@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Unique project prefix used in resource naming.')
@minLength(3)
@maxLength(10)
param projectPrefix string = 'labmonitor'

@description('Environment name (dev, staging, prod).')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('SKU for the App Service Plan.')
param appServicePlanSku string = 'S1'

@description('Administrator login for Azure SQL Database (PaaS).')
param sqlAdminLogin string

@secure()
@description('Administrator password for Azure SQL Database (PaaS).')
param sqlAdminPassword string

@description('Administrator login for the SQL Server VM (IaaS).')
param vmAdminUsername string

@secure()
@description('Administrator password for the SQL Server VM (IaaS).')
param vmAdminPassword string

@description('VM size for the SQL Server IaaS VM.')
param vmSize string = 'Standard_D2s_v5'

// -- Observability Settings --
@description('Log Analytics workspace retention in days.')
param logRetentionDays int = 30

@description('Application Insights data retention in days.')
param appInsightsRetentionDays int = 90

// -- Runtime Stacks --
@description('Linux runtime stack for the frontend App Service.')
param frontendLinuxFxVersion string = 'NODE|20-lts'

@description('Linux runtime stack for the backend API App Service.')
param backendLinuxFxVersion string = 'DOTNETCORE|8.0'

// -- SQL Database (PaaS) Settings --
@description('SQL Database SKU name (e.g. S0, S1, P1).')
param sqlDatabaseSkuName string = 'S0'

@description('SQL Database SKU tier (e.g. Basic, Standard, Premium).')
param sqlDatabaseSkuTier string = 'Standard'

// -- SQL VM (IaaS) Settings --
@description('SQL Server VM image offer.')
param vmImageOffer string = 'sql2022-ws2022'

@description('SQL Server VM image SKU.')
param vmImageSku string = 'sqldev-gen2'

@description('OS disk storage account type for the SQL VM.')
param osDiskStorageType string = 'StandardSSD_LRS'

// -- Networking --
@description('VNet address space CIDR for the SQL VM network.')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('SQL subnet CIDR within the VNet.')
param subnetAddressPrefix string = '10.0.1.0/24'

// -- Variables --
var nameSuffix = '${projectPrefix}-${environment}'

// ============================================================================
// MODULE: Log Analytics Workspace
// Demonstrates: Centralized log collection and query capabilities.
// All other resources send their diagnostics/telemetry here.
// ============================================================================
module logAnalytics 'modules/log-analytics.bicep' = {
  params: {
    location: location
    workspaceName: 'law-${nameSuffix}'
    retentionInDays: logRetentionDays
  }
}

// ============================================================================
// MODULE: Application Insights (workspace-based)
// Demonstrates: APM (Application Performance Monitoring) for App Services.
// Both frontend and backend send telemetry to this single instance.
// ============================================================================
module appInsights 'modules/app-insights.bicep' = {
  params: {
    location: location
    appInsightsName: 'appi-${nameSuffix}'
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    retentionInDays: appInsightsRetentionDays
  }
}

// ============================================================================
// MODULE: App Service Plan (shared by frontend and backend)
// ============================================================================
module appServicePlan 'modules/app-service-plan.bicep' = {
  params: {
    location: location
    planName: 'asp-${nameSuffix}'
    skuName: appServicePlanSku
  }
}

// ============================================================================
// MODULE: App Service - Frontend
// Demonstrates: Web app observability via Application Insights SDK integration.
// Telemetry includes requests, dependencies, exceptions, and page views.
// ============================================================================
module frontendApp 'modules/app-service-frontend.bicep' = {
  params: {
    location: location
    appName: 'app-frontend-${nameSuffix}'
    appServicePlanId: appServicePlan.outputs.planId
    appInsightsConnectionString: appInsights.outputs.connectionString
    appInsightsInstrumentationKey: appInsights.outputs.instrumentationKey
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    linuxFxVersion: frontendLinuxFxVersion
  }
}

// ============================================================================
// MODULE: App Service - Backend API
// Demonstrates: API-level observability — dependency tracking to SQL,
// custom metrics, request tracing, and distributed tracing correlation
// with the frontend via Application Insights.
// ============================================================================
module backendApp 'modules/app-service-backend.bicep' = {
  params: {
    location: location
    appName: 'app-backend-${nameSuffix}'
    appServicePlanId: appServicePlan.outputs.planId
    appInsightsConnectionString: appInsights.outputs.connectionString
    appInsightsInstrumentationKey: appInsights.outputs.instrumentationKey
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    linuxFxVersion: backendLinuxFxVersion
  }
}

// ============================================================================
// MODULE: Azure SQL Database (PaaS)
// Demonstrates: PaaS database observability — auditing, query performance
// insights, diagnostic settings for metrics and query store data sent
// to Log Analytics.
// ============================================================================
module sqlDatabase 'modules/sql-database.bicep' = {
  params: {
    location: location
    serverName: 'sql-${nameSuffix}'
    databaseName: 'sqldb-${nameSuffix}'
    adminLogin: sqlAdminLogin
    adminPassword: sqlAdminPassword
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    skuName: sqlDatabaseSkuName
    skuTier: sqlDatabaseSkuTier
  }
}

// ============================================================================
// MODULE: Azure VM with SQL Server (IaaS)
// Demonstrates: IaaS-level observability — VM boot diagnostics, guest OS
// metrics, performance counters, Windows event logs, and SQL Server
// diagnostics collected via Azure Monitor Agent and sent to Log Analytics.
// ============================================================================
module sqlVm 'modules/sql-vm.bicep' = {
  params: {
    location: location
    vmName: 'vm-sql-${environment}'
    adminUsername: vmAdminUsername
    adminPassword: vmAdminPassword
    vmSize: vmSize
    nameSuffix: nameSuffix
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    vmImageOffer: vmImageOffer
    vmImageSku: vmImageSku
    osDiskStorageType: osDiskStorageType
    vnetAddressPrefix: vnetAddressPrefix
    subnetAddressPrefix: subnetAddressPrefix
  }
}

// ============================================================================
// MODULE: Azure Front Door
// Demonstrates: Edge/CDN-level observability — access logs, WAF logs,
// health probe logs, and routing metrics sent to Log Analytics.
// ============================================================================
module frontDoor 'modules/front-door.bicep' = {
  params: {
    profileName: 'afd-${nameSuffix}'
    frontendAppHostName: frontendApp.outputs.defaultHostName
    backendAppHostName: backendApp.outputs.defaultHostName
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
  }
}

// -- Outputs --
@description('Log Analytics Workspace ID for queries.')
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId

@description('Application Insights instrumentation key.')
output appInsightsInstrumentationKey string = appInsights.outputs.instrumentationKey

@description('Frontend App Service URL.')
output frontendUrl string = 'https://${frontendApp.outputs.defaultHostName}'

@description('Backend API App Service URL.')
output backendApiUrl string = 'https://${backendApp.outputs.defaultHostName}'

@description('Azure Front Door endpoint.')
output frontDoorEndpoint string = frontDoor.outputs.frontDoorEndpointHostName

@description('Azure SQL Server FQDN.')
output sqlServerFqdn string = sqlDatabase.outputs.sqlServerFqdn

@description('SQL IaaS VM name.')
output sqlVmName string = sqlVm.outputs.vmName
