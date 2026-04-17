// ============================================================================
// Azure Monitor Workbook v2 — End-to-End Observability
// ============================================================================
// Loads raw workbook JSON from workbook-v2.json and deploys it as IaC.
// Uses loadTextContent + replace() to inject resource IDs at deploy time,
// avoiding Bicep string-serialization pitfalls.
//
// Data sources (all pre-enabled in the infrastructure):
//   - Application Insights (requests, dependencies, exceptions, traces,
//     availabilityResults, performanceCounters)
//   - Log Analytics (AzureMetrics, AzureDiagnostics, Perf, Event)
//   - Front Door resource-specific tables (CDNAccessLog, CDNHealthProbeLog)
//   - SQL Database diagnostics (AzureDiagnostics — SQL not yet resource-specific)
//   - SQL VM guest OS via AMA/DCR (Perf counters, Windows Event Logs)

@description('Azure region.')
param location string

@description('Name suffix for resource naming.')
param nameSuffix string

@description('Resource ID of the Log Analytics workspace.')
param logAnalyticsWorkspaceId string

@description('Resource ID of Application Insights.')
param appInsightsId string

@description('Resource ID of the Azure Front Door profile.')
param frontDoorProfileId string

// Deterministic GUID for the workbook resource
var workbookId = guid('workbook-e2e-v2-${nameSuffix}')

// Load the raw workbook JSON and inject resource IDs
var rawJson = loadTextContent('workbook-v2.json')
var serializedWorkbook = replace(
  replace(
    replace(rawJson, '__APP_INSIGHTS_ID__', appInsightsId),
    '__LAW_ID__', logAnalyticsWorkspaceId
  ),
  '__FRONT_DOOR_ID__', frontDoorProfileId
)

resource workbook 'Microsoft.Insights/workbooks@2023-06-01' = {
  name: workbookId
  location: location
  kind: 'shared'
  properties: {
    displayName: 'E2E Observability — ${nameSuffix}'
    category: 'workbook'
    sourceId: appInsightsId
    serializedData: serializedWorkbook
  }
}

@description('Workbook resource ID.')
output workbookId string = workbook.id

@description('Workbook display name.')
output workbookName string = workbook.properties.displayName
