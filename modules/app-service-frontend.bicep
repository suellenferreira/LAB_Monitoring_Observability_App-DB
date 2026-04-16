// ============================================================================
// App Service - Frontend
// ============================================================================
// Observability role: Demonstrates client-side and server-side telemetry
// collection for a web frontend application.
//   - Application Insights SDK auto-instrumentation
//   - HTTP request/response logging
//   - App Service diagnostic settings (HTTP logs, app logs, platform metrics)
//   - Health check endpoint monitoring

@description('Azure region.')
param location string

@description('Name of the frontend App Service.')
param appName string

@description('Resource ID of the App Service Plan.')
param appServicePlanId string

@description('Application Insights connection string.')
param appInsightsConnectionString string

@description('Application Insights instrumentation key.')
param appInsightsInstrumentationKey string

@description('Resource ID of the Log Analytics workspace for diagnostic settings.')
param logAnalyticsWorkspaceId string

@description('Linux runtime stack for the frontend (e.g. DOTNETCORE|8.0, NODE|20-lts).')
param linuxFxVersion string = 'DOTNETCORE|8.0'

@description('Backend API base URL.')
param backendApiUrl string = ''

resource frontendApp 'Microsoft.Web/sites@2023-12-01' = {
  name: appName
  location: location
  kind: 'app,linux'
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: linuxFxVersion
      alwaysOn: true
      // Health check enables App Service to detect unhealthy instances
      healthCheckPath: '/health'
      appSettings: [
        // Application Insights connection — enables auto-instrumentation
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsightsInstrumentationKey
        }
        // Enable the Application Insights agent
        {
          name: 'ApplicationInsightsAgent_EXTENSION_VERSION'
          value: '~3'
        }
        {
          name: 'XDT_MicrosoftApplicationInsights_Mode'
          value: 'Recommended'
        }
        {
          name: 'BackendApi__BaseUrl'
          value: backendApiUrl
        }
      ]
    }
  }
}

// Diagnostic settings: send App Service platform logs and metrics to Log Analytics
resource frontendDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-law'
  scope: frontendApp
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

@description('Default hostname of the frontend App Service.')
output defaultHostName string = frontendApp.properties.defaultHostName

@description('Resource ID of the frontend App Service.')
output appId string = frontendApp.id
