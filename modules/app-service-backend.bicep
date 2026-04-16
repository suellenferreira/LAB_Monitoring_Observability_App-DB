// ============================================================================
// App Service - Backend API
// ============================================================================
// Observability role: Demonstrates API-level telemetry including:
//   - Dependency tracking (calls to SQL, external APIs)
//   - Request tracing and performance metrics
//   - Distributed tracing correlation with the frontend
//   - Exception and failure logging
//   - App Service diagnostic settings (HTTP logs, app logs, platform metrics)

@description('Azure region.')
param location string

@description('Name of the backend API App Service.')
param appName string

@description('Resource ID of the App Service Plan.')
param appServicePlanId string

@description('Application Insights connection string.')
param appInsightsConnectionString string

@description('Application Insights instrumentation key.')
param appInsightsInstrumentationKey string

@description('Resource ID of the Log Analytics workspace for diagnostic settings.')
param logAnalyticsWorkspaceId string

@description('Linux runtime stack for the backend API (e.g. DOTNETCORE|8.0, PYTHON|3.12).')
param linuxFxVersion string = 'DOTNETCORE|8.0'

resource backendApp 'Microsoft.Web/sites@2023-12-01' = {
  name: appName
  location: location
  kind: 'app,linux'
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      alwaysOn: true
      healthCheckPath: '/api/health'
      appSettings: [
        // Same Application Insights instance as frontend — enables
        // end-to-end distributed tracing across the full stack
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsightsInstrumentationKey
        }
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'XDT_MicrosoftApplicationInsights_Mode'
          value: 'Recommended'
        }
      ]
    }
  }
}

// Diagnostic settings: captures platform-level logs and metrics
resource backendDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-law'
  scope: backendApp
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'AppServiceHTTPLogs'
        enabled: true
      }
      {
        category: 'AppServiceConsoleLogs'
        enabled: true
      }
      {
        category: 'AppServiceAppLogs'
        enabled: true
      }
      {
        category: 'AppServicePlatformLogs'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

@description('Default hostname of the backend API App Service.')
output defaultHostName string = backendApp.properties.defaultHostName

@description('Resource ID of the backend API App Service.')
output appId string = backendApp.id
