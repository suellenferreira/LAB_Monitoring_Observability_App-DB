// ============================================================================
// Azure Monitor Alerts — Demo Alert Rules
// ============================================================================
// Demonstrates Azure Monitor alerting capabilities:
//   - Action Group with email receiver
//   - Scheduled Query (Log) Alerts scoped to Application Insights
//   - Metric Alerts for App Service HTTP 5xx errors
//
// This module is OPTIONAL — controlled by the deployAlerts parameter in main.bicep.
// ============================================================================

// -- Parameters --

@description('Azure region.')
param location string

@description('Name suffix for resource naming.')
param nameSuffix string

@description('Action Group display name.')
param actionGroupName string = 'ag-alerts-${nameSuffix}'

@description('Action Group short name (max 12 chars).')
@maxLength(12)
param actionGroupShortName string = 'ag-alerts'

@description('Email address for alert notifications.')
param emailReceiverAddress string

@description('Resource ID of the Application Insights instance.')
param appInsightsResourceId string

@description('Resource ID of the Log Analytics workspace.')
#disable-next-line no-unused-params
param logAnalyticsWorkspaceResourceId string

@description('Resource ID of the Frontend App Service.')
param frontendAppServiceResourceId string

@description('Resource ID of the Backend App Service.')
param backendAppServiceResourceId string

@description('Resource ID of the SQL Server VM.')
#disable-next-line no-unused-params
param sqlServerVmResourceId string

// ============================================================================
// ACTION GROUP
// ============================================================================
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  properties: {
    groupShortName: actionGroupShortName
    enabled: true
    emailReceivers: [
      {
        name: 'AlertEmail'
        emailAddress: emailReceiverAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

// ============================================================================
// LOG ALERT #1 — App Error Rate High (Sev2)
// ============================================================================
// Fires when the application failure rate exceeds 5% in the last 5 minutes
// with at least 20 total requests (avoids noise from low traffic).
// ============================================================================
resource logAlertErrorRate 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-app-error-rate-high-${nameSuffix}'
  location: location
  properties: {
    displayName: 'App-ErrorRate-High'
    description: 'Application failure rate exceeds 5% in the last 5 minutes.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [
      appInsightsResourceId
    ]
    criteria: {
      allOf: [
        {
          query: '''
requests
| where timestamp > ago(5m)
| summarize Total=count(), Failed=countif(success == false)
| extend FailureRate = Failed * 100.0 / Total
| where Total > 20 and FailureRate > 5
| project FailureRate
'''
          timeAggregation: 'Maximum'
          metricMeasureColumn: 'FailureRate'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

// ============================================================================
// LOG ALERT #2 — App Latency Average High (Sev3)
// ============================================================================
// Fires when the average request duration exceeds 2000 ms (2 seconds)
// across all frontend and backend requests.
// ============================================================================
resource logAlertLatency 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-app-latency-avg-high-${nameSuffix}'
  location: location
  properties: {
    displayName: 'App-Latency-Avg-High'
    description: 'Average request latency exceeds 2000 ms in the last 5 minutes.'
    severity: 3
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [
      appInsightsResourceId
    ]
    criteria: {
      allOf: [
        {
          query: '''
requests
| where timestamp > ago(5m)
| summarize AvgLatencyMs = avg(duration)
| where AvgLatencyMs > 2000
| project AvgLatencyMs
'''
          timeAggregation: 'Maximum'
          metricMeasureColumn: 'AvgLatencyMs'
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

// ============================================================================
// LOG ALERT #3 — SQL Dependency Latency High (Sev2)
// ============================================================================
// Fires when the average SQL dependency call duration exceeds 1500 ms
// for any target database. Groups by target to identify which DB is slow.
// ============================================================================
resource logAlertSqlLatency 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-dep-sql-latency-high-${nameSuffix}'
  location: location
  properties: {
    displayName: 'Dependency-SQL-Latency-High'
    description: 'Average SQL dependency latency exceeds 1500 ms by target in the last 5 minutes.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [
      appInsightsResourceId
    ]
    criteria: {
      allOf: [
        {
          query: '''
dependencies
| where timestamp > ago(5m)
| where type == "SQL"
| summarize AvgDependencyMs = avg(duration) by target
| where AvgDependencyMs > 1500
| project target, AvgDependencyMs
'''
          timeAggregation: 'Maximum'
          metricMeasureColumn: 'AvgDependencyMs'
          dimensions: [
            {
              name: 'target'
              operator: 'Include'
              values: [ '*' ]
            }
          ]
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

// ============================================================================
// LOG ALERT #4 — SQL Dependency Failure Rate High (Sev2)
// ============================================================================
// Fires when SQL dependency failure rate exceeds 2% for any target,
// with at least 20 total calls (avoids noise from low traffic).
// ============================================================================
resource logAlertSqlFailure 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: 'alert-dep-sql-failure-rate-high-${nameSuffix}'
  location: location
  properties: {
    displayName: 'Dependency-SQL-FailureRate-High'
    description: 'SQL dependency failure rate exceeds 2% by target in the last 5 minutes.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [
      appInsightsResourceId
    ]
    criteria: {
      allOf: [
        {
          query: '''
dependencies
| where timestamp > ago(5m)
| where type == "SQL"
| summarize Total=count(), Failed=countif(success == false) by target
| extend FailureRate = Failed * 100.0 / Total
| where Total > 20 and FailureRate > 2
| project target, FailureRate
'''
          timeAggregation: 'Maximum'
          metricMeasureColumn: 'FailureRate'
          dimensions: [
            {
              name: 'target'
              operator: 'Include'
              values: [ '*' ]
            }
          ]
          operator: 'GreaterThan'
          threshold: 0
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}

// ============================================================================
// METRIC ALERT #5 — Frontend HTTP 5xx High (Sev2)
// ============================================================================
// Fires when the Frontend App Service returns more than 5 HTTP 5xx errors
// in a 5-minute window (total aggregation).
// ============================================================================
resource metricAlertFrontend5xx 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-fe-http5xx-high-${nameSuffix}'
  location: 'global'
  properties: {
    description: 'Frontend App Service HTTP 5xx errors exceed 5 in 5 minutes.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [
      frontendAppServiceResourceId
    ]
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Http5xxCount'
          metricName: 'Http5xx'
          metricNamespace: 'Microsoft.Web/sites'
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// ============================================================================
// METRIC ALERT #6 — Backend HTTP 5xx High (Sev2)
// ============================================================================
// Fires when the Backend App Service returns more than 5 HTTP 5xx errors
// in a 5-minute window (total aggregation).
// ============================================================================
resource metricAlertBackend5xx 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'alert-be-http5xx-high-${nameSuffix}'
  location: 'global'
  properties: {
    description: 'Backend App Service HTTP 5xx errors exceed 5 in 5 minutes.'
    severity: 2
    enabled: true
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    scopes: [
      backendAppServiceResourceId
    ]
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'Http5xxCount'
          metricName: 'Http5xx'
          metricNamespace: 'Microsoft.Web/sites'
          operator: 'GreaterThan'
          threshold: 5
          timeAggregation: 'Total'
          criterionType: 'StaticThresholdCriterion'
        }
      ]
    }
    actions: [
      {
        actionGroupId: actionGroup.id
      }
    ]
  }
}

// -- Outputs --

@description('Action Group resource ID.')
output actionGroupId string = actionGroup.id

@description('Action Group name.')
output actionGroupName string = actionGroup.name

// ============================================================================
// KQL REFERENCE — Copy these queries into Workbooks or Log Analytics
// ============================================================================
//
// --- Alert #1: App Error Rate High ---
// requests
// | where timestamp > ago(5m)
// | summarize Total=count(), Failed=countif(success == false)
// | extend FailureRate = Failed * 100.0 / Total
// | where Total > 20 and FailureRate > 5
//
// --- Alert #2: App Latency Average High ---
// requests
// | where timestamp > ago(5m)
// | summarize AvgLatencyMs = avg(duration)
// | where AvgLatencyMs > 2000
//
// --- Alert #3: SQL Dependency Latency High ---
// dependencies
// | where timestamp > ago(5m)
// | where type == "SQL"
// | summarize AvgDependencyMs = avg(duration) by target
// | where AvgDependencyMs > 1500
//
// --- Alert #4: SQL Dependency Failure Rate High ---
// dependencies
// | where timestamp > ago(5m)
// | where type == "SQL"
// | summarize Total=count(), Failed=countif(success == false) by target
// | extend FailureRate = Failed * 100.0 / Total
// | where Total > 20 and FailureRate > 2
//
// --- Alert #5: Frontend HTTP 5xx (Metric) ---
// Metric: Http5xx on Microsoft.Web/sites (Frontend)
// Condition: Total > 5 over 5-minute window
//
// --- Alert #6: Backend HTTP 5xx (Metric) ---
// Metric: Http5xx on Microsoft.Web/sites (Backend)
// Condition: Total > 5 over 5-minute window
//
// ============================================================================
