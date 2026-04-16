// ============================================================================
// App Service Plan (shared)
// ============================================================================
// Hosts both the frontend and backend App Services.

@description('Azure region.')
param location string

@description('Name of the App Service Plan.')
param planName string

@description('SKU name for the App Service Plan.')
param skuName string = 'S1'

resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: planName
  location: location
  sku: {
    name: skuName
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

@description('Resource ID of the App Service Plan.')
output planId string = plan.id
