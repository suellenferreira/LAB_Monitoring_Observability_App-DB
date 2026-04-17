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

@description('Administrator login for Azure SQL Database (PaaS). Required only when sqlAuthMode is "sqlAndEntra".')
param sqlAdminLogin string = ''

@secure()
@description('Administrator password for Azure SQL Database (PaaS). Required only when sqlAuthMode is "sqlAndEntra".')
param sqlAdminPassword string = ''

@description('SQL authentication mode: "entraOnly" (Entra ID only, corporate-policy compliant) or "sqlAndEntra" (both SQL login and Entra ID).')
@allowed(['entraOnly', 'sqlAndEntra'])
param sqlAuthMode string = 'entraOnly'

@description('Entra ID admin object ID (user or group) for Azure SQL. Required for Entra ID authentication.')
param sqlEntraAdminObjectId string = ''

@description('Entra ID admin login name (e.g. user@domain.com or group name) for Azure SQL.')
param sqlEntraAdminLogin string = ''

@description('Entra ID admin principal type: Group (for user/group) or Application (for service principal).')
@allowed(['Group', 'Application'])
param sqlEntraAdminPrincipalType string = 'Application'

@description('Service Principal client ID for Azure SQL authentication (Active Directory Service Principal mode).')
param spClientId string = ''

@secure()
@description('Service Principal client secret for Azure SQL authentication.')
param spClientSecret string = ''

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
param frontendLinuxFxVersion string = 'DOTNETCORE|8.0'

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
param osDiskStorageType string = 'Standard_LRS'

// -- Networking --
@description('VNet address space CIDR for the SQL VM network.')
param vnetAddressPrefix string = '10.100.0.0/16'

@description('SQL subnet CIDR within the VNet.')
param subnetAddressPrefix string = '10.100.1.0/24'

// -- Alerts (Optional) --
@description('Deploy Azure Monitor alert rules (Action Group + Log/Metric alerts). Set to true to enable.')
param deployAlerts bool = false

@description('Email address for alert notifications. Required when deployAlerts is true.')
param alertEmailAddress string = ''

// -- Variables --
var nameSuffix = '${projectPrefix}-${environment}'
var sqlServerName = 'sql-${nameSuffix}'
var sqlDatabaseDbName = 'sqldb-${nameSuffix}'
// PaaS connection string:
//  - entraOnly + SP credentials → Active Directory Service Principal (MCAPS-compliant)
//  - entraOnly without SP → Active Directory Default (managed identity)
//  - sqlAndEntra → SQL authentication (User ID + Password)
var sqlConnectionString = sqlAuthMode == 'entraOnly'
  ? (spClientId != ''
    ? 'Server=tcp:${sqlServerName}${az.environment().suffixes.sqlServerHostname},1433;Database=${sqlDatabaseDbName};Authentication=Active Directory Service Principal;User Id=${spClientId};Password=${spClientSecret};Encrypt=True;TrustServerCertificate=False;'
    : 'Server=tcp:${sqlServerName}${az.environment().suffixes.sqlServerHostname},1433;Database=${sqlDatabaseDbName};Authentication=Active Directory Default;TrustServerCertificate=True;')
  : 'Server=tcp:${sqlServerName}${az.environment().suffixes.sqlServerHostname},1433;Database=${sqlDatabaseDbName};User ID=${sqlAdminLogin};Password=${sqlAdminPassword};Encrypt=True;TrustServerCertificate=True;'

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
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
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
    backendApiUrl: 'https://app-backend-${nameSuffix}.azurewebsites.net'
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
    sqlConnectionString: sqlConnectionString
    sqlVmConnectionString: 'Server=tcp:${sqlVm.outputs.publicIpAddress},1433;Database=AdventureWorks2022;User ID=${vmAdminUsername};Password=${vmAdminPassword};Encrypt=True;TrustServerCertificate=True;'
    allowedOrigins: 'https://app-frontend-${nameSuffix}.azurewebsites.net'
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
    authMode: sqlAuthMode
    adminLogin: sqlAdminLogin
    adminPassword: sqlAdminPassword
    entraAdminObjectId: sqlEntraAdminObjectId
    entraAdminLogin: sqlEntraAdminLogin
    entraAdminPrincipalType: sqlEntraAdminPrincipalType
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

// ============================================================================
// MODULE: Availability Tests (Standard Web Tests)
// Demonstrates: Proactive uptime monitoring from 5 global locations.
// Results feed into Application Insights availabilityResults table.
// ============================================================================
module availabilityTests 'modules/availability-tests.bicep' = {
  params: {
    location: location
    nameSuffix: nameSuffix
    appInsightsId: appInsights.outputs.appInsightsId
    frontendHostName: frontendApp.outputs.defaultHostName
    backendHostName: backendApp.outputs.defaultHostName
  }
}

// ============================================================================
// MODULE: Azure Monitor Workbook v2 — End-to-End Observability
// Raw JSON workbook definition loaded via loadTextContent to avoid
// Bicep string-serialization issues. 8 tabs: E2E Overview, Edge,
// Frontend, Backend, Dependencies, Database, Availability/SLO, Investigations.
// ============================================================================
module workbook 'modules/workbook-v2.bicep' = {
  params: {
    location: location
    nameSuffix: nameSuffix
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    appInsightsId: appInsights.outputs.appInsightsId
    frontDoorProfileId: frontDoor.outputs.frontDoorProfileId
  }
}

// ============================================================================
// MODULE: Azure Monitor Alerts (Optional)
// Demonstrates: Alert rules using log queries (Application Insights) and
// metric signals (App Service). Includes an Action Group with email receiver.
// Controlled by the deployAlerts parameter (default: false).
// ============================================================================
module alerts 'modules/alerts-demo.bicep' = if (deployAlerts) {
  params: {
    location: location
    nameSuffix: nameSuffix
    emailReceiverAddress: alertEmailAddress
    appInsightsResourceId: appInsights.outputs.appInsightsId
    logAnalyticsWorkspaceResourceId: logAnalytics.outputs.workspaceId
    frontendAppServiceResourceId: frontendApp.outputs.appId
    backendAppServiceResourceId: backendApp.outputs.appId
    sqlServerVmResourceId: sqlVm.outputs.vmId
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
