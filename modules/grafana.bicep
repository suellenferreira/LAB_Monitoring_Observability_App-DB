// ============================================================================
// Azure Managed Grafana — Observability Dashboard
// ============================================================================
// Deploys an Azure Managed Grafana instance with system-assigned managed
// identity and Monitoring Reader role for querying Application Insights
// and Log Analytics data.
//
// ╔══════════════════════════════════════════════════════════════════════╗
// ║ COST DISCLAIMER                                                    ║
// ║ Azure Managed Grafana — Standard tier (only supported SKU):        ║
// ║   X1 (default): 2 SU → ~$0.086/hr (~$62/mo) + $6/active user     ║
// ║   X2 (larger) : 4 SU → ~$0.172/hr (~$124/mo) + $6/active user    ║
// ║ There is NO free tier for Azure Managed Grafana.                   ║
// ║ For a free alternative, use "Azure Monitor dashboards with         ║
// ║ Grafana (preview)" in the Azure Portal — see README.               ║
// ║ Delete the resource when no longer needed to stop charges.         ║
// ║                                                                    ║
// ║ ⚠ Costs shown are approximate as of April 2026. Always confirm    ║
// ║   current pricing at the link below before deploying.              ║
// ║ Pricing: https://azure.microsoft.com/pricing/details/managed-grafana/ ║
// ╚══════════════════════════════════════════════════════════════════════╝
//
// This module is OPTIONAL — controlled by deployGrafana parameter in main.bicep.
// ============================================================================

@description('Azure region.')
param location string

@description('Name of the Grafana workspace.')
param grafanaName string

@description('Grafana instance size. X1 (default, 2 SU, 500 alert rules) or X2 (4 SU, 1000 alert rules).')
@allowed(['X1', 'X2'])
param skuSize string = 'X1'

// -- Grafana Instance --
resource grafana 'Microsoft.Dashboard/grafana@2024-11-01' = {
  name: grafanaName
  location: location
  sku: {
    name: 'Standard'
    size: skuSize
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    grafanaMajorVersion: '10'
    publicNetworkAccess: 'Enabled'
    zoneRedundancy: 'Disabled'
    apiKey: 'Disabled'
    deterministicOutboundIP: 'Disabled'
  }
}

// -- Role Assignment: Monitoring Reader --
// Grants the Grafana managed identity read access to monitoring data
// (Application Insights, Log Analytics, metrics) at the resource group scope.
var monitoringReaderRoleId = '43d0d8ad-25c7-4714-9337-8ba259a9fe05'

resource monitoringReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(grafana.id, monitoringReaderRoleId, resourceGroup().id)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringReaderRoleId)
    principalId: grafana.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// -- Outputs --

@description('Grafana workspace name.')
output grafanaName string = grafana.name

@description('Grafana dashboard endpoint URL.')
output grafanaEndpoint string = grafana.properties.endpoint

@description('Grafana resource ID.')
output grafanaId string = grafana.id
