// ============================================================================
// Log Analytics Workspace
// ============================================================================
// Observability role: Central data sink for logs, metrics, and diagnostics
// from ALL resources in this environment. Enables cross-resource KQL queries,
// alerting, and workbook dashboards.

@description('Azure region.')
param location string

@description('Name of the Log Analytics workspace.')
param workspaceName string

@description('Data retention in days.')
param retentionInDays int = 30

@description('Log Analytics pricing SKU.')
param skuName string = 'PerGB2018'

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: skuName
    }
    retentionInDays: retentionInDays
    // Enables ingestion and query-based usage tracking
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

@description('Resource ID of the Log Analytics workspace.')
output workspaceId string = workspace.id

@description('Name of the Log Analytics workspace.')
output workspaceName string = workspace.name
