using 'main.bicep'

// ===========================================================================
// General Settings
// ===========================================================================
param location = 'centralus'
param projectPrefix = 'labmonitor'
param environment = 'dev'

// ===========================================================================
// App Service Settings
// ===========================================================================
param appServicePlanSku = 'S1'
param frontendLinuxFxVersion = 'DOTNETCORE|8.0'
param backendLinuxFxVersion = 'DOTNETCORE|8.0'

// ===========================================================================
// SQL Database (PaaS) Settings
// ===========================================================================
// authMode: 'entraOnly' = Entra ID only (corporate-policy compliant, no SQL password needed)
//           'sqlAndEntra' = Both SQL login + Entra ID (requires SQL_ADMIN_LOGIN/PASSWORD)
param sqlAuthMode = 'entraOnly'
param sqlEntraAdminObjectId = readEnvironmentVariable('SQL_ENTRA_ADMIN_OBJECT_ID', '')
param sqlEntraAdminLogin = readEnvironmentVariable('SQL_ENTRA_ADMIN_LOGIN', '')
param sqlAdminLogin = readEnvironmentVariable('SQL_ADMIN_LOGIN', 'sqladminuser')
param sqlAdminPassword = readEnvironmentVariable('SQL_ADMIN_PASSWORD', '')
param sqlDatabaseSkuName = 'S0'
param sqlDatabaseSkuTier = 'Standard'

// ===========================================================================
// SQL VM (IaaS) Settings
// ===========================================================================
param vmAdminUsername = readEnvironmentVariable('VM_ADMIN_USERNAME', 'vmadminuser')
param vmAdminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD', '')
param vmSize = 'Standard_D2s_v5'
param vmImageOffer = 'sql2022-ws2022'
param vmImageSku = 'sqldev-gen2'
param osDiskStorageType = 'Standard_LRS'

// ===========================================================================
// Networking
// ===========================================================================
param vnetAddressPrefix = '10.100.0.0/16'
param subnetAddressPrefix = '10.100.1.0/24'

// ===========================================================================
// Observability
// ===========================================================================
param logRetentionDays = 90
param appInsightsRetentionDays = 90

// ===========================================================================
// Alerts (Optional)
// ===========================================================================
// Set to true to deploy Azure Monitor alert rules
param deployAlerts = false
param alertEmailAddress = readEnvironmentVariable('ALERT_EMAIL_ADDRESS', '')

// ===========================================================================
// Grafana (Optional — incurs cost, no free tier)
// ===========================================================================
// Essential: ~$36/month | Standard: ~$130/month
param deployGrafana = false
param grafanaSku = 'Essential'
