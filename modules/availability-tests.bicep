// ============================================================================
// Availability Tests (Standard Web Tests)
// ============================================================================
// Creates URL ping tests for Frontend and Backend health endpoints.
// Results are stored in the Application Insights availabilityResults table
// and used for SLO/SLI calculations in the monitoring workbook.

@description('Azure region.')
param location string

@description('Name suffix for resource naming.')
param nameSuffix string

@description('Resource ID of the Application Insights instance.')
param appInsightsId string

@description('Frontend App Service default hostname (e.g. app-frontend-xxx.azurewebsites.net).')
param frontendHostName string

@description('Backend App Service default hostname (e.g. app-backend-xxx.azurewebsites.net).')
param backendHostName string

@description('Frequency of the test in seconds.')
@allowed([300, 600, 900])
param frequencySeconds int = 300

@description('Timeout in seconds for each test.')
param timeoutSeconds int = 120

@description('Test locations (Azure region codes for availability test agents).')
param testLocations array = [
  { Id: 'us-fl-mia-edge' }   // Central US
  { Id: 'us-va-ash-azr' }    // East US
  { Id: 'us-ca-sjc-azr' }    // West US
  { Id: 'emea-gb-db3-azr' }  // North Europe
  { Id: 'apac-sg-sin-azr' }  // Southeast Asia
]

// Frontend availability test — checks the main page
resource frontendTest 'Microsoft.Insights/webtests@2022-06-15' = {
  name: 'avail-frontend-${nameSuffix}'
  location: location
  kind: 'standard'
  tags: {
    'hidden-link:${appInsightsId}': 'Resource'
  }
  properties: {
    SyntheticMonitorId: 'avail-frontend-${nameSuffix}'
    Name: 'Frontend Health'
    Description: 'Availability test for the frontend web application'
    Enabled: true
    Frequency: frequencySeconds
    Timeout: timeoutSeconds
    Kind: 'standard'
    RetryEnabled: true
    Locations: testLocations
    Request: {
      RequestUrl: 'https://${frontendHostName}/'
      HttpVerb: 'GET'
      ParseDependentRequests: false
      FollowRedirects: true
    }
    ValidationRules: {
      ExpectedHttpStatusCode: 200
      SSLCheck: true
      SSLCertRemainingLifetimeCheck: 7
    }
  }
}

// Backend API availability test — checks the health endpoint
resource backendTest 'Microsoft.Insights/webtests@2022-06-15' = {
  name: 'avail-backend-${nameSuffix}'
  location: location
  kind: 'standard'
  tags: {
    'hidden-link:${appInsightsId}': 'Resource'
  }
  properties: {
    SyntheticMonitorId: 'avail-backend-${nameSuffix}'
    Name: 'Backend API Health'
    Description: 'Availability test for the backend API health endpoint'
    Enabled: true
    Frequency: frequencySeconds
    Timeout: timeoutSeconds
    Kind: 'standard'
    RetryEnabled: true
    Locations: testLocations
    Request: {
      RequestUrl: 'https://${backendHostName}/api/health'
      HttpVerb: 'GET'
      ParseDependentRequests: false
      FollowRedirects: true
    }
    ValidationRules: {
      ExpectedHttpStatusCode: 200
      ContentValidation: {
        ContentMatch: 'healthy'
        IgnoreCase: true
        PassIfTextFound: true
      }
      SSLCheck: true
      SSLCertRemainingLifetimeCheck: 7
    }
  }
}

@description('Frontend availability test resource ID.')
output frontendTestId string = frontendTest.id

@description('Backend availability test resource ID.')
output backendTestId string = backendTest.id
