// ============================================================================
// Azure Front Door (Standard/Premium)
// ============================================================================
// Observability role: Demonstrates edge-level and CDN observability:
//   - Access logs: every request hitting the Front Door edge
//   - Health probe logs: backend health check results
//   - WAF logs: Web Application Firewall decisions (if WAF enabled)
//   - Metrics: request count, latency, origin health percentage
// Shows how to monitor traffic before it reaches the App Services.

@description('Name of the Front Door profile.')
param profileName string

@description('Hostname of the frontend App Service.')
param frontendAppHostName string

@description('Hostname of the backend API App Service.')
param backendAppHostName string

@description('Resource ID of the Log Analytics workspace.')
param logAnalyticsWorkspaceId string

@description('Front Door SKU name (Standard_AzureFrontDoor or Premium_AzureFrontDoor).')
@allowed(['Standard_AzureFrontDoor', 'Premium_AzureFrontDoor'])
param skuName string = 'Standard_AzureFrontDoor'

@description('Health probe interval in seconds.')
param healthProbeIntervalInSeconds int = 30

resource frontDoorProfile 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: profileName
  location: 'global'
  sku: {
    name: skuName
  }
}

// Front Door endpoint
resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' = {
  parent: frontDoorProfile
  name: 'ep-${profileName}'
  location: 'global'
  properties: {
    enabledState: 'Enabled'
  }
}

// Origin group for the frontend
resource frontendOriginGroup 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = {
  parent: frontDoorProfile
  name: 'og-frontend'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
    }
    healthProbeSettings: {
      probePath: '/health'
      probeRequestType: 'HEAD'
      probeProtocol: 'Https'
      probeIntervalInSeconds: healthProbeIntervalInSeconds
    }
  }
}

resource frontendOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: frontendOriginGroup
  name: 'origin-frontend'
  properties: {
    hostName: frontendAppHostName
    httpPort: 80
    httpsPort: 443
    originHostHeader: frontendAppHostName
    priority: 1
    weight: 1000
  }
}

// Origin group for the backend API
resource backendOriginGroup 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = {
  parent: frontDoorProfile
  name: 'og-backend'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
    }
    healthProbeSettings: {
      probePath: '/api/health'
      probeRequestType: 'HEAD'
      probeProtocol: 'Https'
      probeIntervalInSeconds: healthProbeIntervalInSeconds
    }
  }
}

resource backendOrigin 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: backendOriginGroup
  name: 'origin-backend'
  properties: {
    hostName: backendAppHostName
    httpPort: 80
    httpsPort: 443
    originHostHeader: backendAppHostName
    priority: 1
    weight: 1000
  }
}

// Route: /* → frontend
resource frontendRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = {
  parent: endpoint
  name: 'route-frontend'
  properties: {
    originGroup: {
      id: frontendOriginGroup.id
    }
    supportedProtocols: ['Http', 'Https']
    patternsToMatch: ['/*']
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
  }
  dependsOn: [frontendOrigin]
}

// Route: /api/* → backend
resource backendRoute 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = {
  parent: endpoint
  name: 'route-backend'
  properties: {
    originGroup: {
      id: backendOriginGroup.id
    }
    supportedProtocols: ['Http', 'Https']
    patternsToMatch: ['/api/*']
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
  }
  dependsOn: [backendOrigin]
}

// Diagnostic settings: access logs, health probe logs, and metrics to Log Analytics
resource frontDoorDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-law'
  scope: frontDoorProfile
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'FrontDoorAccessLog'
        enabled: true
      }
      {
        category: 'FrontDoorHealthProbeLog'
        enabled: true
      }
      {
        category: 'FrontDoorWebApplicationFirewallLog'
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

@description('Front Door endpoint hostname.')
output frontDoorEndpointHostName string = endpoint.properties.hostName

@description('Front Door profile ID.')
output frontDoorProfileId string = frontDoorProfile.id
