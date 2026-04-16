// ============================================================================
// Application Insights (workspace-based)
// ============================================================================
// Observability role: APM (Application Performance Monitoring) for both
// frontend and backend App Services. Collects:
//   - Request/response telemetry
//   - Dependency calls (SQL, HTTP, etc.)
//   - Exception and failure tracking
//   - Custom events and metrics
//   - Distributed tracing (end-to-end correlation across services)
// Workspace-based mode sends all data to Log Analytics for unified querying.

@description('Azure region.')
param location string

@description('Name of the Application Insights resource.')
param appInsightsName string

@description('Resource ID of the Log Analytics workspace to back this instance.')
param logAnalyticsWorkspaceId string

@description('Application Insights data retention in days.')
param retentionInDays int = 90

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    // Workspace-based mode: all telemetry flows into Log Analytics
    WorkspaceResourceId: logAnalyticsWorkspaceId
    // Enable continuous profiling for performance diagnostics
    DisableIpMasking: false
    RetentionInDays: retentionInDays
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

@description('Application Insights connection string (preferred over instrumentation key).')
output connectionString string = appInsights.properties.ConnectionString

@description('Application Insights instrumentation key.')
output instrumentationKey string = appInsights.properties.InstrumentationKey

@description('Resource ID of the Application Insights instance.')
output appInsightsId string = appInsights.id
