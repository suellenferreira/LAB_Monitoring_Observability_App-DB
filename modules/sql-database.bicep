// ============================================================================
// Azure SQL Database (PaaS)
// ============================================================================
// Observability role: Demonstrates PaaS database monitoring including:
//   - SQL audit logs → Log Analytics (who did what, when)
//   - Query performance insights via diagnostic settings
//   - Automatic tuning recommendations
//   - Metrics: DTU/CPU usage, deadlocks, connection stats
//   - Threat detection alerts (Advanced Threat Protection)

@description('Azure region.')
param location string

@description('Name of the SQL Server.')
param serverName string

@description('Name of the SQL Database.')
param databaseName string

@description('SQL authentication mode: "entraOnly" (Entra ID only, no SQL login) or "sqlAndEntra" (both SQL login and Entra ID).')
@allowed(['entraOnly', 'sqlAndEntra'])
param authMode string = 'entraOnly'

@description('SQL administrator login. Required only when authMode is "sqlAndEntra".')
param adminLogin string = ''

@secure()
@description('SQL administrator password. Required only when authMode is "sqlAndEntra".')
param adminPassword string = ''

@description('Entra ID admin object ID (user or group). Required for Entra ID authentication.')
param entraAdminObjectId string = ''

@description('Entra ID admin login name (e.g. user@domain.com or group name).')
param entraAdminLogin string = ''

@description('Entra ID admin principal type: Group (for user/group) or Application (for service principal).')
@allowed(['Group', 'Application'])
param entraAdminPrincipalType string = 'Application'

@description('Resource ID of the Log Analytics workspace.')
param logAnalyticsWorkspaceId string

@description('SQL Database SKU name (e.g. S0, S1, P1).')
param skuName string = 'S0'

@description('SQL Database SKU tier (e.g. Basic, Standard, Premium).')
param skuTier string = 'Standard'

@description('SQL Database collation.')
param collation string = 'SQL_Latin1_General_CP1_CI_AS'

@description('SQL Database maximum size in bytes (default 2 GB).')
param maxSizeBytes int = 2147483648

// --- Entra ID Only: No SQL admin login, Entra-only authentication ---
resource sqlServerEntraOnly 'Microsoft.Sql/servers@2023-08-01-preview' = if (authMode == 'entraOnly') {
  name: serverName
  location: location
  properties: {
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: entraAdminPrincipalType
      login: entraAdminLogin
      sid: entraAdminObjectId
      tenantId: tenant().tenantId
      azureADOnlyAuthentication: true
    }
  }
}

// --- SQL + Entra ID: SQL admin login with Entra ID also configured ---
resource sqlServerSqlAndEntra 'Microsoft.Sql/servers@2023-08-01-preview' = if (authMode == 'sqlAndEntra') {
  name: serverName
  location: location
  properties: {
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
    administrators: {
      administratorType: 'ActiveDirectory'
      principalType: entraAdminPrincipalType
      login: entraAdminLogin
      sid: entraAdminObjectId
      tenantId: tenant().tenantId
      azureADOnlyAuthentication: false
    }
  }
}

// Auditing: captures all database operations for compliance and security
resource sqlAuditEntraOnly 'Microsoft.Sql/servers/auditingSettings@2023-08-01-preview' = if (authMode == 'entraOnly') {
  parent: sqlServerEntraOnly
  name: 'default'
  properties: {
    state: 'Enabled'
    isAzureMonitorTargetEnabled: true
  }
}

resource sqlAuditSqlAndEntra 'Microsoft.Sql/servers/auditingSettings@2023-08-01-preview' = if (authMode == 'sqlAndEntra') {
  parent: sqlServerSqlAndEntra
  name: 'default'
  properties: {
    state: 'Enabled'
    isAzureMonitorTargetEnabled: true
  }
}

// Allow Azure services to access the SQL Server (for demo purposes)
resource firewallEntraOnly 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = if (authMode == 'entraOnly') {
  parent: sqlServerEntraOnly
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource firewallSqlAndEntra 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = if (authMode == 'sqlAndEntra') {
  parent: sqlServerSqlAndEntra
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource sqlDatabaseEntraOnly 'Microsoft.Sql/servers/databases@2023-08-01-preview' = if (authMode == 'entraOnly') {
  parent: sqlServerEntraOnly
  name: databaseName
  location: location
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    collation: collation
    maxSizeBytes: maxSizeBytes
    zoneRedundant: false
    sampleName: 'AdventureWorksLT'
  }
}

resource sqlDatabaseSqlAndEntra 'Microsoft.Sql/servers/databases@2023-08-01-preview' = if (authMode == 'sqlAndEntra') {
  parent: sqlServerSqlAndEntra
  name: databaseName
  location: location
  sku: {
    name: skuName
    tier: skuTier
  }
  properties: {
    collation: collation
    maxSizeBytes: maxSizeBytes
    zoneRedundant: false
    sampleName: 'AdventureWorksLT'
  }
}

// Diagnostic settings on the database: query stats, errors, timeouts, deadlocks
resource sqlDbDiagnosticsEntraOnly 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (authMode == 'entraOnly') {
  name: 'send-to-law'
  scope: sqlDatabaseEntraOnly
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'SQLInsights'
        enabled: true
      }
      {
        category: 'AutomaticTuning'
        enabled: true
      }
      {
        category: 'QueryStoreRuntimeStatistics'
        enabled: true
      }
      {
        category: 'QueryStoreWaitStatistics'
        enabled: true
      }
      {
        category: 'Errors'
        enabled: true
      }
      {
        category: 'DatabaseWaitStatistics'
        enabled: true
      }
      {
        category: 'Timeouts'
        enabled: true
      }
      {
        category: 'Blocks'
        enabled: true
      }
      {
        category: 'Deadlocks'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'Basic'
        enabled: true
      }
      {
        category: 'InstanceAndAppAdvanced'
        enabled: true
      }
      {
        category: 'WorkloadManagement'
        enabled: true
      }
    ]
  }
}

// Diagnostic settings for sqlAndEntra mode
resource sqlDbDiagnosticsSqlAndEntra 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (authMode == 'sqlAndEntra') {
  name: 'send-to-law'
  scope: sqlDatabaseSqlAndEntra
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'SQLInsights', enabled: true }
      { category: 'AutomaticTuning', enabled: true }
      { category: 'QueryStoreRuntimeStatistics', enabled: true }
      { category: 'QueryStoreWaitStatistics', enabled: true }
      { category: 'Errors', enabled: true }
      { category: 'DatabaseWaitStatistics', enabled: true }
      { category: 'Timeouts', enabled: true }
      { category: 'Blocks', enabled: true }
      { category: 'Deadlocks', enabled: true }
    ]
    metrics: [
      { category: 'Basic', enabled: true }
      { category: 'InstanceAndAppAdvanced', enabled: true }
      { category: 'WorkloadManagement', enabled: true }
    ]
  }
}

// Diagnostic settings on the master database for server-level auditing
resource masterDbEntraOnly 'Microsoft.Sql/servers/databases@2023-08-01-preview' existing = if (authMode == 'entraOnly') {
  parent: sqlServerEntraOnly
  name: 'master'
}

resource masterDbSqlAndEntra 'Microsoft.Sql/servers/databases@2023-08-01-preview' existing = if (authMode == 'sqlAndEntra') {
  parent: sqlServerSqlAndEntra
  name: 'master'
}

resource masterDiagnosticsEntraOnly 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (authMode == 'entraOnly') {
  name: 'send-to-law'
  scope: masterDbEntraOnly
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'SQLSecurityAuditEvents', enabled: true }
    ]
  }
}

resource masterDiagnosticsSqlAndEntra 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (authMode == 'sqlAndEntra') {
  name: 'send-to-law'
  scope: masterDbSqlAndEntra
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'SQLSecurityAuditEvents', enabled: true }
    ]
  }
}

@description('SQL Server FQDN.')
output sqlServerFqdn string = authMode == 'entraOnly' ? sqlServerEntraOnly!.properties.fullyQualifiedDomainName : sqlServerSqlAndEntra!.properties.fullyQualifiedDomainName

@description('SQL Database name.')
output sqlDatabaseName string = databaseName
