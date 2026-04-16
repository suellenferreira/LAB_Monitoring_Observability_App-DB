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

@description('SQL administrator login.')
param adminLogin string

@secure()
@description('SQL administrator password.')
param adminPassword string

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

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: serverName
  location: location
  properties: {
    administratorLogin: adminLogin
    administratorLoginPassword: adminPassword
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

// Auditing: captures all database operations for compliance and security
resource sqlAudit 'Microsoft.Sql/servers/auditingSettings@2023-08-01-preview' = {
  parent: sqlServer
  name: 'default'
  properties: {
    state: 'Enabled'
    isAzureMonitorTargetEnabled: true
  }
}

// Allow Azure services to access the SQL Server (for demo purposes)
resource firewallAllowAzure 'Microsoft.Sql/servers/firewallRules@2023-08-01-preview' = {
  parent: sqlServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01-preview' = {
  parent: sqlServer
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
  }
}

// Diagnostic settings on the database: query stats, errors, timeouts, deadlocks
resource sqlDbDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-law'
  scope: sqlDatabase
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

// Diagnostic settings on the master database for server-level auditing
resource masterDb 'Microsoft.Sql/servers/databases@2023-08-01-preview' existing = {
  parent: sqlServer
  name: 'master'
}

resource masterDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-law'
  scope: masterDb
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'SQLSecurityAuditEvents'
        enabled: true
      }
    ]
  }
}

@description('SQL Server FQDN.')
output sqlServerFqdn string = sqlServer.properties.fullyQualifiedDomainName

@description('SQL Database name.')
output sqlDatabaseName string = sqlDatabase.name
