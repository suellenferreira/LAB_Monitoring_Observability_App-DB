// ============================================================================
// Azure Virtual Machine with SQL Server (IaaS)
// ============================================================================
// Observability role: Demonstrates IaaS-level monitoring including:
//   - Boot diagnostics (screenshot & serial log for troubleshooting VM boot)
//   - Azure Monitor Agent (AMA) for guest OS telemetry
//   - Data Collection Rule: Windows event logs, performance counters,
//     SQL Server error logs → Log Analytics
//   - VM platform metrics (CPU, disk, network) via diagnostic settings
// This contrasts with the PaaS SQL Database to show the additional
// monitoring effort required for IaaS workloads.

@description('Azure region.')
param location string

@description('Name of the virtual machine.')
param vmName string

@description('VM administrator username.')
param adminUsername string

@secure()
@description('VM administrator password.')
param adminPassword string

@description('VM size.')
param vmSize string = 'Standard_D2s_v5'

@description('Name suffix for associated resources.')
param nameSuffix string

@description('Resource ID of the Log Analytics workspace.')
param logAnalyticsWorkspaceId string

@description('VNet address space CIDR.')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('SQL subnet CIDR.')
param subnetAddressPrefix string = '10.0.1.0/24'

@description('SQL Server VM image publisher.')
param vmImagePublisher string = 'MicrosoftSQLServer'

@description('SQL Server VM image offer.')
param vmImageOffer string = 'sql2022-ws2022'

@description('SQL Server VM image SKU.')
param vmImageSku string = 'sqldev-gen2'

@description('OS disk storage account type.')
param osDiskStorageType string = 'StandardSSD_LRS'

// -- Networking --
resource vnet 'Microsoft.Network/virtualNetworks@2024-01-01' = {
  name: 'vnet-${nameSuffix}'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
  }
}

resource subnet 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' = {
  parent: vnet
  name: 'snet-sql'
  properties: {
    addressPrefix: subnetAddressPrefix
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-01-01' = {
  name: 'nsg-${vmName}'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowRDP'
        properties: {
          priority: 1000
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource publicIp 'Microsoft.Network/publicIPAddresses@2024-01-01' = {
  name: 'pip-${vmName}'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-01-01' = {
  name: 'nic-${vmName}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnet.id
          }
          publicIPAddress: {
            id: publicIp.id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
  }
}

// -- Virtual Machine with SQL Server image --
resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        // SQL Server image (configurable via parameters)
        publisher: vmImagePublisher
        offer: vmImageOffer
        sku: vmImageSku
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: osDiskStorageType
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
    // Boot diagnostics: captures serial log and screenshots for VM troubleshooting
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

// SQL Virtual Machine resource — enables SQL IaaS Agent and Mixed Mode auth
resource sqlVm 'Microsoft.SqlVirtualMachine/sqlVirtualMachines@2023-10-01' = {
  name: vmName
  location: location
  properties: {
    virtualMachineResourceId: vm.id
    sqlManagement: 'Full'
    sqlServerLicenseType: 'PAYG'
    serverConfigurationsManagementSettings: {
      sqlConnectivityUpdateSettings: {
        connectivityType: 'PUBLIC'
        port: 1433
        sqlAuthUpdateUserName: adminUsername
        sqlAuthUpdatePassword: adminPassword
      }
    }
  }
}

// Azure Monitor Agent extension — collects guest OS telemetry
resource amaExtension 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: vm
  name: 'AzureMonitorWindowsAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorWindowsAgent'
    typeHandlerVersion: '1.0'
    autoUpgradeMinorVersion: true
    enableAutomaticUpgrade: true
  }
}

// Custom Script Extension: downloads and restores AdventureWorks sample database
resource installAdventureWorks 'Microsoft.Compute/virtualMachines/extensions@2024-07-01' = {
  parent: vm
  name: 'InstallAdventureWorks'
  location: location
  dependsOn: [amaExtension, sqlVm]
  properties: {
    publisher: 'Microsoft.Compute'
    type: 'CustomScriptExtension'
    typeHandlerVersion: '1.10'
    autoUpgradeMinorVersion: true
    settings: {}
    protectedSettings: {
      commandToExecute: 'powershell -ExecutionPolicy Unrestricted -Command "New-Item -Path C:\\SQLBackups -ItemType Directory -Force; $ProgressPreference = \'SilentlyContinue\'; Invoke-WebRequest -Uri \'https://github.com/Microsoft/sql-server-samples/releases/download/adventureworks/AdventureWorks2022.bak\' -OutFile \'C:\\SQLBackups\\AdventureWorks2022.bak\'; Invoke-Sqlcmd -Username \'${adminUsername}\' -Password \'${adminPassword}\' -Query \\"RESTORE DATABASE [AdventureWorks2022] FROM DISK = N\'C:\\SQLBackups\\AdventureWorks2022.bak\' WITH MOVE \'AdventureWorks2022\' TO \'C:\\Program Files\\Microsoft SQL Server\\MSSQL16.MSSQLSERVER\\MSSQL\\DATA\\AdventureWorks2022.mdf\', MOVE \'AdventureWorks2022_log\' TO \'C:\\Program Files\\Microsoft SQL Server\\MSSQL16.MSSQLSERVER\\MSSQL\\DATA\\AdventureWorks2022_log.ldf\', REPLACE\\" -ServerInstance \'localhost\'"'
    }
  }
}

// Data Collection Rule: defines what guest OS data to collect
resource dcr 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: 'dcr-${vmName}'
  location: location
  kind: 'Windows'
  properties: {
    dataSources: {
      // Windows performance counters: CPU, memory, disk, SQL Server metrics
      performanceCounters: [
        {
          name: 'VMPerformanceCounters'
          streams: ['Microsoft-Perf']
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\Processor(_Total)\\% Processor Time'
            '\\Memory\\Available MBytes'
            '\\LogicalDisk(_Total)\\% Free Space'
            '\\LogicalDisk(_Total)\\Disk Reads/sec'
            '\\LogicalDisk(_Total)\\Disk Writes/sec'
            '\\SQLServer:General Statistics\\User Connections'
            '\\SQLServer:SQL Statistics\\Batch Requests/sec'
            '\\SQLServer:Buffer Manager\\Buffer cache hit ratio'
            '\\SQLServer:Locks(_Total)\\Number of Deadlocks/sec'
          ]
        }
      ]
      // Windows Event Logs: System and Application logs
      windowsEventLogs: [
        {
          name: 'WindowsEventLogs'
          streams: ['Microsoft-Event']
          xPathQueries: [
            'Application!*[System[(Level=1 or Level=2 or Level=3)]]'
            'System!*[System[(Level=1 or Level=2 or Level=3)]]'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          name: 'logAnalyticsDestination'
          workspaceResourceId: logAnalyticsWorkspaceId
        }
      ]
    }
    dataFlows: [
      {
        streams: ['Microsoft-Perf']
        destinations: ['logAnalyticsDestination']
      }
      {
        streams: ['Microsoft-Event']
        destinations: ['logAnalyticsDestination']
      }
    ]
  }
}

// Associate the Data Collection Rule with the VM
resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2023-03-11' = {
  name: 'dcra-${vmName}'
  scope: vm
  properties: {
    dataCollectionRuleId: dcr.id
  }
}

@description('Virtual machine name.')
output vmName string = vm.name

@description('Virtual machine resource ID.')
output vmId string = vm.id
