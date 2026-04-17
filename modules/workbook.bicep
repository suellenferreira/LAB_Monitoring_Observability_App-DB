// ============================================================================
// Azure Monitor Workbook — End-to-End Observability
// ============================================================================
// Custom workbook deployed as Infrastructure-as-Code.
// Provides 8 tabs covering Edge → App → Dependencies → Database → SLO.
//
// Data sources:
//   - Azure Monitor Metrics (AzureMetrics table)
//   - Azure Monitor Logs / Log Analytics (Perf, Event, AzureMetrics)
//   - Front Door resource-specific tables (CDNAccessLog, CDNHealthProbeLog)
//   - SQL diagnostics (AzureDiagnostics — SQL not yet on resource-specific tables)
//   - Application Insights (requests, dependencies, exceptions, traces,
//     availabilityResults, performanceCounters)
//   - VM guest OS via AMA/DCR (Perf counters, Windows Event Logs)

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

// Generate a deterministic GUID for the workbook from the name suffix
var workbookId = guid('workbook-e2e-${nameSuffix}')

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

// ============================================================================
// Workbook JSON — 8 tabs with shared parameters
// ============================================================================
var serializedWorkbook = string({
  version: 'Notebook/1.0'
  items: [
    // ========================================================================
    // SHARED PARAMETERS
    // ========================================================================
    {
      type: 9
      content: {
        version: 'KqlParameterItem/1.0'
        parameters: [
          {
            id: guid('param-timerange')
            version: 'KqlParameterItem/1.0'
            name: 'TimeRange'
            type: 4
            isRequired: true
            typeSettings: {
              selectableValues: [
                { durationMs: 3600000, displayName: 'Last 1 hour' }
                { durationMs: 14400000, displayName: 'Last 4 hours' }
                { durationMs: 86400000, displayName: 'Last 24 hours' }
                { durationMs: 259200000, displayName: 'Last 3 days' }
                { durationMs: 604800000, displayName: 'Last 7 days' }
              ]
              allowCustom: true
            }
            value: { durationMs: 86400000 }
          }
          {
            id: guid('param-subscription')
            version: 'KqlParameterItem/1.0'
            name: 'Subscription'
            type: 6
            isRequired: true
            multiSelect: false
            query: 'summarize by subscriptionId\n| project value = strcat("/subscriptions/", subscriptionId), label = subscriptionId, selected = true'
            crossComponentResources: [ 'value::all' ]
            queryType: 1
            resourceType: 'microsoft.resourcegraph/resources'
            value: ''
          }
          {
            id: guid('param-appinsights')
            version: 'KqlParameterItem/1.0'
            name: 'AppInsights'
            label: 'Application Insights'
            type: 5
            isRequired: true
            query: 'resources\n| where type == "microsoft.insights/components"\n| project value = id, label = name, selected = id =~ "${appInsightsId}"'
            crossComponentResources: [ '{Subscription}' ]
            queryType: 1
            resourceType: 'microsoft.resourcegraph/resources'
            value: appInsightsId
          }
          {
            id: guid('param-law')
            version: 'KqlParameterItem/1.0'
            name: 'LogAnalyticsWorkspace'
            label: 'Log Analytics Workspace'
            type: 5
            isRequired: true
            query: 'resources\n| where type == "microsoft.operationalinsights/workspaces"\n| project value = id, label = name, selected = id =~ "${logAnalyticsWorkspaceId}"'
            crossComponentResources: [ '{Subscription}' ]
            queryType: 1
            resourceType: 'microsoft.resourcegraph/resources'
            value: logAnalyticsWorkspaceId
          }
          {
            id: guid('param-frontdoor')
            version: 'KqlParameterItem/1.0'
            name: 'FrontDoorProfile'
            label: 'Front Door Profile'
            type: 5
            isRequired: false
            query: 'resources\n| where type == "microsoft.cdn/profiles"\n| project value = id, label = name, selected = id =~ "${frontDoorProfileId}"'
            crossComponentResources: [ '{Subscription}' ]
            queryType: 1
            resourceType: 'microsoft.resourcegraph/resources'
            value: frontDoorProfileId
          }
        ]
        style: 'above'
        queryType: 1
        resourceType: 'microsoft.resourcegraph/resources'
      }
      name: 'parameters'
    }

    // ========================================================================
    // TAB NAVIGATION (links/tabs group)
    // ========================================================================
    {
      type: 11
      content: {
        version: 'LinkItem/1.0'
        style: 'tabs'
        links: [
          { id: guid('tab-a'), cellValue: 'tabA', linkTarget: 'parameter', linkLabel: 'A. E2E Overview', subTarget: 'SelectedTab', style: 'link' }
          { id: guid('tab-b'), cellValue: 'tabB', linkTarget: 'parameter', linkLabel: 'B. Edge: Front Door', subTarget: 'SelectedTab', style: 'link' }
          { id: guid('tab-c'), cellValue: 'tabC', linkTarget: 'parameter', linkLabel: 'C. Frontend (FE)', subTarget: 'SelectedTab', style: 'link' }
          { id: guid('tab-d'), cellValue: 'tabD', linkTarget: 'parameter', linkLabel: 'D. Backend (API)', subTarget: 'SelectedTab', style: 'link' }
          { id: guid('tab-e'), cellValue: 'tabE', linkTarget: 'parameter', linkLabel: 'E. Dependencies & Flow', subTarget: 'SelectedTab', style: 'link' }
          { id: guid('tab-f'), cellValue: 'tabF', linkTarget: 'parameter', linkLabel: 'F. Database (SQL)', subTarget: 'SelectedTab', style: 'link' }
          { id: guid('tab-g'), cellValue: 'tabG', linkTarget: 'parameter', linkLabel: 'G. Availability / SLO', subTarget: 'SelectedTab', style: 'link' }
          { id: guid('tab-h'), cellValue: 'tabH', linkTarget: 'parameter', linkLabel: 'H. Investigations', subTarget: 'SelectedTab', style: 'link' }
        ]
      }
      name: 'tabs'
    }
    // Hidden parameter to track selected tab
    {
      type: 9
      content: {
        version: 'KqlParameterItem/1.0'
        parameters: [
          {
            id: guid('param-selectedtab')
            version: 'KqlParameterItem/1.0'
            name: 'SelectedTab'
            type: 1
            isRequired: false
            isHiddenWhenLocked: true
            value: 'tabA'
          }
        ]
        style: 'above'
      }
      name: 'hidden-tab-param'
    }

    // ========================================================================
    // TAB A — E2E Overview (Single Pane of Glass)
    // ========================================================================
    {
      type: 12
      content: {
        version: 'NotebookGroup/1.0'
        groupType: 0
        items: [
          // ── Section header ──
          {
            type: 1
            content: {
              json: '## End-to-End Overview\\n\\nSingle pane of glass showing health across all layers: Edge → Frontend → Backend → Database.'
            }
            name: 'tab-a-header'
          }
          // ── Health summary tiles ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'let feRequests = requests\n| where timestamp {TimeRange}\n| where cloud_RoleName has "frontend"\n| summarize FE_Total=count(), FE_Failed=countif(success == false), FE_AvgDuration=avg(duration)\n| extend FE_Health = iff(FE_Failed == 0, "Healthy", strcat(FE_Failed, " failures"));\nlet beRequests = requests\n| where timestamp {TimeRange}\n| where cloud_RoleName has "backend"\n| summarize BE_Total=count(), BE_Failed=countif(success == false), BE_AvgDuration=avg(duration)\n| extend BE_Health = iff(BE_Failed == 0, "Healthy", strcat(BE_Failed, " failures"));\nlet sqlDeps = dependencies\n| where timestamp {TimeRange}\n| where type == "SQL"\n| summarize SQL_Total=count(), SQL_Failed=countif(success == false), SQL_AvgDuration=avg(duration)\n| extend SQL_Health = iff(SQL_Failed == 0, "Healthy", strcat(SQL_Failed, " failures"));\nlet httpDeps = dependencies\n| where timestamp {TimeRange}\n| where type == "HTTP"\n| summarize HTTP_Total=count(), HTTP_Failed=countif(success == false)\n| extend HTTP_Health = iff(HTTP_Failed == 0, "Healthy", strcat(HTTP_Failed, " failures"));\nfeRequests | extend dummy=1\n| join kind=fullouter (beRequests | extend dummy=1) on dummy\n| join kind=fullouter (sqlDeps | extend dummy=1) on dummy\n| join kind=fullouter (httpDeps | extend dummy=1) on dummy\n| project Frontend=strcat(FE_Health, " (", FE_Total, " req)"), Backend=strcat(BE_Health, " (", BE_Total, " req)"), SQL_Dependencies=strcat(SQL_Health, " (", SQL_Total, " calls)"), HTTP_Dependencies=strcat(HTTP_Health, " (", HTTP_Total, " calls)")'
              size: 4
              title: 'Layer Health Summary'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'tiles'
              tileSettings: {
                titleContent: { columnMatch: 'FD_Health', formatter: 1 }
                subtitleContent: { columnMatch: 'FD_Total', formatter: 1 }
              }
            }
            name: 'tab-a-health-tiles'
          }
          // ── Request volume across layers (timechart) ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'let fe = requests\n| where timestamp {TimeRange}\n| where cloud_RoleName has "frontend"\n| summarize FE_Requests=count() by bin(timestamp, 5m);\nlet be = requests\n| where timestamp {TimeRange}\n| where cloud_RoleName has "backend"\n| summarize BE_Requests=count() by bin(timestamp, 5m);\nfe\n| join kind=fullouter be on timestamp\n| project timestamp=coalesce(timestamp, timestamp1), FE_Requests=coalesce(FE_Requests,0), BE_Requests=coalesce(BE_Requests,0)\n| order by timestamp asc'
              size: 0
              title: 'Request Volume — Frontend vs Backend'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'timechart'
              chartSettings: { seriesLabelSettings: [ { seriesName: 'FE_Requests', label: 'Frontend' }, { seriesName: 'BE_Requests', label: 'Backend' } ] }
            }
            name: 'tab-a-request-volume'
          }
          // ── E2E Latency Percentiles ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'requests\n| where timestamp {TimeRange}\n| summarize p50=percentile(duration,50), p90=percentile(duration,90), p95=percentile(duration,95), p99=percentile(duration,99) by bin(timestamp, 5m), cloud_RoleName\n| extend cloud_RoleName = case(cloud_RoleName has "frontend", "Frontend", cloud_RoleName has "backend", "Backend", cloud_RoleName)\n| project timestamp, cloud_RoleName, p50=round(p50,1), p90=round(p90,1), p95=round(p95,1), p99=round(p99,1)\n| order by timestamp asc'
              size: 0
              title: 'Latency Percentiles (ms) by Service'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'timechart'
            }
            name: 'tab-a-latency-percentiles'
          }
          // ── Top Errors Summary ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'exceptions\n| where timestamp {TimeRange}\n| summarize Count=count() by problemId, cloud_RoleName\n| top 10 by Count desc\n| project [\'Exception\'] = problemId, Service = cloud_RoleName, Count'
              size: 0
              title: 'Top 10 Exceptions'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'table'
              gridSettings: { sortBy: [ { itemKey: 'Count', sortOrder: 2 } ] }
            }
            name: 'tab-a-top-errors'
          }
        ]
      }
      conditionalVisibilities: [{ parameterName: 'SelectedTab', comparison: 'isEqualTo', value: 'tabA' }]
      name: 'group-tab-a'
    }

    // ========================================================================
    // TAB B — Edge: Azure Front Door
    // ========================================================================
    {
      type: 12
      content: {
        version: 'NotebookGroup/1.0'
        groupType: 0
        items: [
          {
            type: 1
            content: {
              json: '## Edge: Azure Front Door\\n\\nEdge health, latency, and error analysis. Isolate whether issues originate at the edge or at the origin.'
            }
            name: 'tab-b-header'
          }
          // ── Request count trend ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'CDNAccessLog\n| where TimeGenerated {TimeRange}\n| summarize Requests=count() by bin(TimeGenerated, 5m)\n| order by TimeGenerated asc'
              size: 0
              title: 'Front Door — Request Count Trend'
              queryType: 0
              resourceType: 'microsoft.operationalinsights/workspaces'
              crossComponentResources: [ '{LogAnalyticsWorkspace}' ]
              visualization: 'timechart'
            }
            name: 'tab-b-request-trend'
          }
          // ── Response latency at edge ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'CDNAccessLog\n| where TimeGenerated {TimeRange}\n| extend latencyMs = todouble(TimeTaken) * 1000\n| summarize p50=percentile(latencyMs,50), p90=percentile(latencyMs,90), p95=percentile(latencyMs,95), p99=percentile(latencyMs,99) by bin(TimeGenerated, 5m)\n| order by TimeGenerated asc'
              size: 0
              title: 'Edge Latency (ms) — Percentiles'
              queryType: 0
              resourceType: 'microsoft.operationalinsights/workspaces'
              crossComponentResources: [ '{LogAnalyticsWorkspace}' ]
              visualization: 'timechart'
              chartSettings: { seriesLabelSettings: [ { seriesName: 'p50', label: 'P50' }, { seriesName: 'p90', label: 'P90' }, { seriesName: 'p95', label: 'P95' }, { seriesName: 'p99', label: 'P99' } ] }
            }
            name: 'tab-b-edge-latency'
          }
          // ── HTTP error rates ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'CDNAccessLog\n| where TimeGenerated {TimeRange}\n| extend StatusCode = toint(HttpStatusCode)\n| extend StatusClass = case(StatusCode >= 500, "5xx", StatusCode >= 400, "4xx", StatusCode >= 300, "3xx", "2xx")\n| summarize Count=count() by bin(TimeGenerated, 5m), StatusClass\n| order by TimeGenerated asc'
              size: 0
              title: 'HTTP Status Code Distribution'
              queryType: 0
              resourceType: 'microsoft.operationalinsights/workspaces'
              crossComponentResources: [ '{LogAnalyticsWorkspace}' ]
              visualization: 'timechart'
              chartSettings: { seriesLabelSettings: [ { seriesName: '2xx', color: 'green' }, { seriesName: '3xx', color: 'blue' }, { seriesName: '4xx', color: 'orange' }, { seriesName: '5xx', color: 'red' } ] }
            }
            name: 'tab-b-http-errors'
          }
          // ── Backend health probe status ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'CDNHealthProbeLog\n| where TimeGenerated {TimeRange}\n| extend Result = iff(toint(HttpStatusCode) >= 200 and toint(HttpStatusCode) < 400, "Healthy", "Unhealthy")\n| summarize Count=count() by bin(TimeGenerated, 5m), Result, OriginName\n| order by TimeGenerated asc'
              size: 0
              title: 'Backend Health Probe Results'
              queryType: 0
              resourceType: 'microsoft.operationalinsights/workspaces'
              crossComponentResources: [ '{LogAnalyticsWorkspace}' ]
              visualization: 'timechart'
              chartSettings: { seriesLabelSettings: [ { seriesName: 'Healthy', color: 'green' }, { seriesName: 'Unhealthy', color: 'red' } ] }
            }
            name: 'tab-b-health-probes'
          }
          // ── Top URLs by request volume ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'CDNAccessLog\n| where TimeGenerated {TimeRange}\n| summarize Requests=count(), AvgLatencyMs=round(avg(todouble(TimeTaken))*1000,1), Errors=countif(toint(HttpStatusCode)>=400) by RequestUri\n| top 20 by Requests desc\n| project URL=RequestUri, Requests, AvgLatencyMs, Errors, ErrorRate=round(todouble(Errors)/todouble(Requests)*100,1)'
              size: 0
              title: 'Top 20 URLs by Volume'
              queryType: 0
              resourceType: 'microsoft.operationalinsights/workspaces'
              crossComponentResources: [ '{LogAnalyticsWorkspace}' ]
              visualization: 'table'
              gridSettings: { sortBy: [ { itemKey: 'Requests', sortOrder: 2 } ] }
            }
            name: 'tab-b-top-urls'
          }
        ]
      }
      conditionalVisibilities: [{ parameterName: 'SelectedTab', comparison: 'isEqualTo', value: 'tabB' }]
      name: 'group-tab-b'
    }

    // ========================================================================
    // TAB C — Frontend App Service
    // ========================================================================
    {
      type: 12
      content: {
        version: 'NotebookGroup/1.0'
        groupType: 0
        items: [
          {
            type: 1
            content: {
              json: '## Frontend App Service\\n\\nTraffic, failure modes, and latency for the Razor Pages frontend.'
            }
            name: 'tab-c-header'
          }
          // ── Request rate ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'requests\n| where timestamp {TimeRange}\n| where cloud_RoleName has "frontend"\n| summarize Requests=count(), Failed=countif(success == false) by bin(timestamp, 5m)\n| order by timestamp asc'
              size: 0
              title: 'Frontend — Request Rate & Failures'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'timechart'
              chartSettings: { seriesLabelSettings: [ { seriesName: 'Requests', color: 'blue' }, { seriesName: 'Failed', color: 'red' } ] }
            }
            name: 'tab-c-request-rate'
          }
          // ── Response time distribution ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'requests\n| where timestamp {TimeRange}\n| where cloud_RoleName has "frontend"\n| summarize p50=percentile(duration,50), p90=percentile(duration,90), p95=percentile(duration,95), p99=percentile(duration,99) by bin(timestamp, 5m)\n| order by timestamp asc'
              size: 0
              title: 'Frontend — Response Time Percentiles (ms)'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'timechart'
            }
            name: 'tab-c-latency'
          }
          // ── Exceptions ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'exceptions\n| where timestamp {TimeRange}\n| where cloud_RoleName has "frontend"\n| summarize Count=count() by bin(timestamp, 5m), type\n| order by timestamp asc'
              size: 0
              title: 'Frontend — Exceptions Over Time'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'timechart'
            }
            name: 'tab-c-exceptions'
          }
          // ── Top operations ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'requests\n| where timestamp {TimeRange}\n| where cloud_RoleName has "frontend"\n| summarize Requests=count(), AvgDurationMs=round(avg(duration),1), FailRate=round(countif(success==false)*100.0/count(),1) by name\n| top 15 by Requests desc\n| project Operation=name, Requests, AvgDurationMs, [\'Fail %\']=FailRate'
              size: 0
              title: 'Frontend — Top Operations'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'table'
            }
            name: 'tab-c-top-operations'
          }
          // ── App Service HTTP Logs ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'AppServiceHTTPLogs\n| where TimeGenerated {TimeRange}\n| where _ResourceId has "frontend"\n| summarize Requests=count() by bin(TimeGenerated, 5m), ScStatus=tostring(ScStatus)\n| order by TimeGenerated asc'
              size: 0
              title: 'Frontend — App Service HTTP Status Codes'
              queryType: 0
              resourceType: 'microsoft.operationalinsights/workspaces'
              crossComponentResources: [ '{LogAnalyticsWorkspace}' ]
              visualization: 'timechart'
            }
            name: 'tab-c-appservice-http'
          }
        ]
      }
      conditionalVisibilities: [{ parameterName: 'SelectedTab', comparison: 'isEqualTo', value: 'tabC' }]
      name: 'group-tab-c'
    }

    // ========================================================================
    // TAB D — Backend App Service (API)
    // ========================================================================
    {
      type: 12
      content: {
        version: 'NotebookGroup/1.0'
        groupType: 0
        items: [
          {
            type: 1
            content: {
              json: '## Backend App Service (API)\\n\\nAPI behavior: traffic, failure modes, latency, and SQL dependency calls.'
            }
            name: 'tab-d-header'
          }
          // ── Request rate ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'requests\n| where timestamp {TimeRange}\n| where cloud_RoleName has "backend"\n| summarize Requests=count(), Failed=countif(success == false) by bin(timestamp, 5m)\n| order by timestamp asc'
              size: 0
              title: 'Backend API — Request Rate & Failures'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'timechart'
              chartSettings: { seriesLabelSettings: [ { seriesName: 'Requests', color: 'blue' }, { seriesName: 'Failed', color: 'red' } ] }
            }
            name: 'tab-d-request-rate'
          }
          // ── Response time ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'requests\n| where timestamp {TimeRange}\n| where cloud_RoleName has "backend"\n| summarize p50=percentile(duration,50), p90=percentile(duration,90), p95=percentile(duration,95), p99=percentile(duration,99) by bin(timestamp, 5m)\n| order by timestamp asc'
              size: 0
              title: 'Backend API — Response Time Percentiles (ms)'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'timechart'
            }
            name: 'tab-d-latency'
          }
          // ── SQL dependency breakdown ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'dependencies\n| where timestamp {TimeRange}\n| where cloud_RoleName has "backend"\n| where type == "SQL"\n| summarize Calls=count(), AvgDurationMs=round(avg(duration),1), Failed=countif(success == false) by bin(timestamp, 5m)\n| order by timestamp asc'
              size: 0
              title: 'Backend → SQL Dependency Calls'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'timechart'
              chartSettings: { seriesLabelSettings: [ { seriesName: 'Calls', color: 'blue' }, { seriesName: 'Failed', color: 'red' } ] }
            }
            name: 'tab-d-sql-deps'
          }
          // ── Exceptions ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'exceptions\n| where timestamp {TimeRange}\n| where cloud_RoleName has "backend"\n| summarize Count=count() by bin(timestamp, 5m), type\n| order by timestamp asc'
              size: 0
              title: 'Backend API — Exceptions Over Time'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'timechart'
            }
            name: 'tab-d-exceptions'
          }
          // ── Top API endpoints ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'requests\n| where timestamp {TimeRange}\n| where cloud_RoleName has "backend"\n| summarize Requests=count(), AvgDurationMs=round(avg(duration),1), FailRate=round(countif(success==false)*100.0/count(),1) by name\n| top 15 by Requests desc\n| project Endpoint=name, Requests, AvgDurationMs, [\'Fail %\']=FailRate'
              size: 0
              title: 'Backend API — Top Endpoints'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'table'
            }
            name: 'tab-d-top-endpoints'
          }
        ]
      }
      conditionalVisibilities: [{ parameterName: 'SelectedTab', comparison: 'isEqualTo', value: 'tabD' }]
      name: 'group-tab-d'
    }

    // ========================================================================
    // TAB E — Dependencies & Transaction Flow (E2E)
    // ========================================================================
    {
      type: 12
      content: {
        version: 'NotebookGroup/1.0'
        groupType: 0
        items: [
          {
            type: 1
            content: {
              json: '## Dependencies & Transaction Flow\\n\\nEnd-to-end chain: Frontend → Backend → Database. Identify where latency and failures occur.'
            }
            name: 'tab-e-header'
          }
          // ── FE → BE dependency calls ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'dependencies\n| where timestamp {TimeRange}\n| where cloud_RoleName has "frontend"\n| where type == "HTTP"\n| summarize Calls=count(), AvgDurationMs=round(avg(duration),1), Failed=countif(success == false) by bin(timestamp, 5m)\n| order by timestamp asc'
              size: 0
              title: 'Frontend → Backend (HTTP Dependency Calls)'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'timechart'
              chartSettings: { seriesLabelSettings: [ { seriesName: 'Calls', color: 'green' }, { seriesName: 'AvgDurationMs', color: 'orange' }, { seriesName: 'Failed', color: 'red' } ] }
            }
            name: 'tab-e-fe-to-be'
          }
          // ── BE → SQL dependency calls ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'dependencies\n| where timestamp {TimeRange}\n| where cloud_RoleName has "backend"\n| where type == "SQL"\n| summarize Calls=count(), AvgDurationMs=round(avg(duration),1), Failed=countif(success == false) by bin(timestamp, 5m)\n| order by timestamp asc'
              size: 0
              title: 'Backend → SQL Database (Dependency Calls)'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'timechart'
              chartSettings: { seriesLabelSettings: [ { seriesName: 'Calls', color: 'blue' }, { seriesName: 'AvgDurationMs', color: 'orange' }, { seriesName: 'Failed', color: 'red' } ] }
            }
            name: 'tab-e-be-to-sql'
          }
          // ── Latency waterfall (avg per layer) ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'let feLatency = dependencies\n| where timestamp {TimeRange}\n| where cloud_RoleName has "frontend" and type == "HTTP"\n| summarize FE_to_BE_ms=round(avg(duration),1);\nlet beLatency = requests\n| where timestamp {TimeRange}\n| where cloud_RoleName has "backend"\n| summarize BE_Processing_ms=round(avg(duration),1);\nlet sqlLatency = dependencies\n| where timestamp {TimeRange}\n| where cloud_RoleName has "backend" and type == "SQL"\n| summarize BE_to_SQL_ms=round(avg(duration),1);\nfeLatency | extend dummy=1\n| join kind=fullouter (beLatency | extend dummy=1) on dummy\n| join kind=fullouter (sqlLatency | extend dummy=1) on dummy\n| project [\'FE → BE (avg ms)\']=FE_to_BE_ms, [\'BE Processing (avg ms)\']=BE_Processing_ms, [\'BE → SQL (avg ms)\']=BE_to_SQL_ms'
              size: 4
              title: 'Latency Waterfall — Average by Layer'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'tiles'
            }
            name: 'tab-e-latency-waterfall'
          }
          // ── Dependency failure breakdown ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'dependencies\n| where timestamp {TimeRange}\n| where success == false\n| summarize Failures=count() by type, target, resultCode\n| top 20 by Failures desc\n| project Type=type, Target=target, ResultCode=resultCode, Failures'
              size: 0
              title: 'Failed Dependencies — Breakdown'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'table'
              gridSettings: { sortBy: [ { itemKey: 'Failures', sortOrder: 2 } ] }
            }
            name: 'tab-e-failed-deps'
          }
          // ── E2E latency percentiles over time ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'dependencies\n| where timestamp {TimeRange}\n| summarize p50=percentile(duration,50), p90=percentile(duration,90), p95=percentile(duration,95) by bin(timestamp, 5m), type\n| order by timestamp asc'
              size: 0
              title: 'Dependency Latency by Type (Percentiles)'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'timechart'
            }
            name: 'tab-e-dep-latency-trend'
          }
        ]
      }
      conditionalVisibilities: [{ parameterName: 'SelectedTab', comparison: 'isEqualTo', value: 'tabE' }]
      name: 'group-tab-e'
    }

    // ========================================================================
    // TAB F — Database (SQL Server)
    // ========================================================================
    {
      type: 12
      content: {
        version: 'NotebookGroup/1.0'
        groupType: 0
        items: [
          {
            type: 1
            content: {
              json: '## Database Layer — SQL Server\\n\\nDual view: Azure SQL (PaaS) diagnostics and SQL VM (IaaS) guest OS metrics side by side.'
            }
            name: 'tab-f-header'
          }
          // ── Sub-header: PaaS ──
          {
            type: 1
            content: {
              json: '### Azure SQL Database (PaaS) — AdventureWorksLT'
            }
            name: 'tab-f-paas-header'
          }
          // ── PaaS: DTU / CPU from metrics ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'AzureMetrics\n| where TimeGenerated {TimeRange}\n| where ResourceProvider == "MICROSOFT.SQL"\n| where MetricName in ("dtu_consumption_percent", "cpu_percent", "connection_successful", "connection_failed")\n| summarize AvgValue=round(avg(Average),2) by bin(TimeGenerated, 5m), MetricName\n| order by TimeGenerated asc'
              size: 0
              title: 'Azure SQL — DTU / CPU / Connections'
              queryType: 0
              resourceType: 'microsoft.operationalinsights/workspaces'
              crossComponentResources: [ '{LogAnalyticsWorkspace}' ]
              visualization: 'timechart'
            }
            name: 'tab-f-paas-dtu'
          }
          // ── PaaS: Deadlocks and blocks ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'AzureDiagnostics\n| where TimeGenerated {TimeRange}\n| where ResourceProvider == "MICROSOFT.SQL"\n| where Category in ("Deadlocks", "Blocks", "Errors")\n| summarize Count=count() by bin(TimeGenerated, 15m), Category\n| order by TimeGenerated asc'
              size: 0
              title: 'Azure SQL — Deadlocks, Blocks & Errors'
              queryType: 0
              resourceType: 'microsoft.operationalinsights/workspaces'
              crossComponentResources: [ '{LogAnalyticsWorkspace}' ]
              visualization: 'timechart'
              chartSettings: { seriesLabelSettings: [ { seriesName: 'Deadlocks', color: 'red' }, { seriesName: 'Blocks', color: 'orange' }, { seriesName: 'Errors', color: 'redBright' } ] }
            }
            name: 'tab-f-paas-deadlocks'
          }
          // ── PaaS: Query Store wait stats ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'AzureDiagnostics\n| where TimeGenerated {TimeRange}\n| where Category == "QueryStoreWaitStatistics"\n| summarize TotalWaitMs=sum(todouble(total_query_wait_time_ms_d)) by bin(TimeGenerated, 15m), wait_category_s\n| top 50 by TotalWaitMs desc\n| order by TimeGenerated asc'
              size: 0
              title: 'Azure SQL — Query Wait Categories'
              queryType: 0
              resourceType: 'microsoft.operationalinsights/workspaces'
              crossComponentResources: [ '{LogAnalyticsWorkspace}' ]
              visualization: 'timechart'
            }
            name: 'tab-f-paas-wait-stats'
          }
          // ── Sub-header: IaaS ──
          {
            type: 1
            content: {
              json: '### SQL Server on VM (IaaS) — AdventureWorks2022\\n\\nGuest OS performance counters collected via Azure Monitor Agent (AMA).'
            }
            name: 'tab-f-iaas-header'
          }
          // ── IaaS: CPU & Memory ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'Perf\n| where TimeGenerated {TimeRange}\n| where Computer has "vm-sql"\n| where CounterName in ("% Processor Time", "Available MBytes")\n| summarize AvgValue=round(avg(CounterValue),2) by bin(TimeGenerated, 5m), CounterName\n| order by TimeGenerated asc'
              size: 0
              title: 'SQL VM — CPU & Memory'
              queryType: 0
              resourceType: 'microsoft.operationalinsights/workspaces'
              crossComponentResources: [ '{LogAnalyticsWorkspace}' ]
              visualization: 'timechart'
              chartSettings: { seriesLabelSettings: [ { seriesName: '% Processor Time', label: 'CPU %' }, { seriesName: 'Available MBytes', label: 'Free Memory (MB)' } ] }
            }
            name: 'tab-f-iaas-cpu-mem'
          }
          // ── IaaS: SQL Server counters ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'Perf\n| where TimeGenerated {TimeRange}\n| where Computer has "vm-sql"\n| where ObjectName has "SQLServer"\n| summarize AvgValue=round(avg(CounterValue),2) by bin(TimeGenerated, 5m), CounterName\n| order by TimeGenerated asc'
              size: 0
              title: 'SQL VM — SQL Server Performance Counters'
              queryType: 0
              resourceType: 'microsoft.operationalinsights/workspaces'
              crossComponentResources: [ '{LogAnalyticsWorkspace}' ]
              visualization: 'timechart'
            }
            name: 'tab-f-iaas-sql-counters'
          }
          // ── IaaS: Disk I/O ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'Perf\n| where TimeGenerated {TimeRange}\n| where Computer has "vm-sql"\n| where CounterName in ("Disk Reads/sec", "Disk Writes/sec", "% Free Space")\n| summarize AvgValue=round(avg(CounterValue),2) by bin(TimeGenerated, 5m), CounterName\n| order by TimeGenerated asc'
              size: 0
              title: 'SQL VM — Disk I/O'
              queryType: 0
              resourceType: 'microsoft.operationalinsights/workspaces'
              crossComponentResources: [ '{LogAnalyticsWorkspace}' ]
              visualization: 'timechart'
            }
            name: 'tab-f-iaas-disk'
          }
          // ── IaaS: Network throughput ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'Perf\n| where TimeGenerated {TimeRange}\n| where Computer has "vm-sql"\n| where CounterName == "Bytes Total/sec"\n| summarize AvgBytesPerSec=round(avg(CounterValue),0) by bin(TimeGenerated, 5m)\n| extend AvgMbps = round(AvgBytesPerSec * 8 / 1000000, 2)\n| project TimeGenerated, AvgMbps\n| order by TimeGenerated asc'
              size: 0
              title: 'SQL VM — Network Throughput (Mbps)'
              queryType: 0
              resourceType: 'microsoft.operationalinsights/workspaces'
              crossComponentResources: [ '{LogAnalyticsWorkspace}' ]
              visualization: 'timechart'
            }
            name: 'tab-f-iaas-network'
          }
          // ── IaaS: Windows Event Errors ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'Event\n| where TimeGenerated {TimeRange}\n| where Computer has "vm-sql"\n| where EventLevelName in ("Error", "Critical")\n| summarize Count=count() by bin(TimeGenerated, 15m), EventLog, EventLevelName\n| order by TimeGenerated asc'
              size: 0
              title: 'SQL VM — Windows Event Errors'
              queryType: 0
              resourceType: 'microsoft.operationalinsights/workspaces'
              crossComponentResources: [ '{LogAnalyticsWorkspace}' ]
              visualization: 'timechart'
              chartSettings: { seriesLabelSettings: [ { seriesName: 'Error', color: 'orange' }, { seriesName: 'Critical', color: 'red' } ] }
            }
            name: 'tab-f-iaas-events'
          }
          // ── Dependency view from app side ──
          {
            type: 1
            content: {
              json: '### SQL from Application Perspective (Dependency Telemetry)'
            }
            name: 'tab-f-dep-header'
          }
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'dependencies\n| where timestamp {TimeRange}\n| where type == "SQL"\n| summarize Calls=count(), AvgMs=round(avg(duration),1), P95ms=round(percentile(duration,95),1), Failed=countif(success==false) by target\n| project [\'SQL Target\']=target, Calls, [\'Avg (ms)\']=AvgMs, [\'P95 (ms)\']=P95ms, Failed'
              size: 0
              title: 'SQL Dependencies — App-Side Latency by Target'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'table'
            }
            name: 'tab-f-sql-dep-table'
          }
        ]
      }
      conditionalVisibilities: [{ parameterName: 'SelectedTab', comparison: 'isEqualTo', value: 'tabF' }]
      name: 'group-tab-f'
    }

    // ========================================================================
    // TAB G — Availability / SLO View
    // ========================================================================
    {
      type: 12
      content: {
        version: 'NotebookGroup/1.0'
        groupType: 0
        items: [
          {
            type: 1
            content: {
              json: '## Availability & SLO\\n\\nOps-friendly view of SLIs (Service Level Indicators) and availability from web tests and request telemetry.'
            }
            name: 'tab-g-header'
          }
          // ── Availability test results ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'availabilityResults\n| where timestamp {TimeRange}\n| summarize SuccessCount=countif(success == 1), TotalCount=count() by bin(timestamp, 15m), name\n| extend AvailabilityPct = round(todouble(SuccessCount) / todouble(TotalCount) * 100, 2)\n| order by timestamp asc'
              size: 0
              title: 'Availability Test Results (%)'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'timechart'
              chartSettings: { ySettings: { min: 0, max: 100 } }
            }
            name: 'tab-g-availability-trend'
          }
          // ── Availability summary tiles ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'availabilityResults\n| where timestamp {TimeRange}\n| summarize SuccessCount=countif(success == 1), TotalCount=count(), AvgDurationMs=round(avg(duration),1) by name\n| extend AvailabilityPct = round(todouble(SuccessCount) / todouble(TotalCount) * 100, 2)\n| extend Status = iff(AvailabilityPct >= 99.9, "✅ SLO Met", iff(AvailabilityPct >= 99.0, "⚠️ At Risk", "🔴 SLO Breached"))\n| project [\'Test Name\']=name, [\'Availability %\']=AvailabilityPct, Status, [\'Avg Duration (ms)\']=AvgDurationMs, [\'Total Checks\']=TotalCount, Passed=SuccessCount'
              size: 0
              title: 'Availability Summary (Target: 99.9%)'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'table'
              gridSettings: {
                formatters: [
                  { columnMatch: 'Availability %', formatter: 8, formatOptions: { min: 95, max: 100, palette: 'greenRed' } }
                ]
              }
            }
            name: 'tab-g-availability-summary'
          }
          // ── Request success rate (SLI) ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'requests\n| where timestamp {TimeRange}\n| summarize Total=count(), Successful=countif(success == true) by bin(timestamp, 15m), cloud_RoleName\n| extend SuccessRate = round(todouble(Successful) / todouble(Total) * 100, 2)\n| extend Service = case(cloud_RoleName has "frontend", "Frontend", cloud_RoleName has "backend", "Backend", cloud_RoleName)\n| project timestamp, Service, SuccessRate\n| order by timestamp asc'
              size: 0
              title: 'Request Success Rate by Service (SLI)'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'timechart'
              chartSettings: { ySettings: { min: 90, max: 100 }, seriesLabelSettings: [ { seriesName: 'Frontend', color: 'blue' }, { seriesName: 'Backend', color: 'green' } ] }
            }
            name: 'tab-g-success-rate'
          }
          // ── Latency SLI (P95 < target) ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'requests\n| where timestamp {TimeRange}\n| summarize P95ms=round(percentile(duration, 95),0) by bin(timestamp, 15m), cloud_RoleName\n| extend Service = case(cloud_RoleName has "frontend", "Frontend", cloud_RoleName has "backend", "Backend", cloud_RoleName)\n| project timestamp, Service, P95ms\n| order by timestamp asc'
              size: 0
              title: 'P95 Latency by Service (Target: < 2000ms)'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'timechart'
              chartSettings: {
                ySettings: { min: 0 }
                seriesLabelSettings: [ { seriesName: 'Frontend', color: 'blue' }, { seriesName: 'Backend', color: 'green' } ]
                customThresholdLine: '2000'
                customThresholdLineStyle: 1
              }
            }
            name: 'tab-g-latency-sli'
          }
          // ── Error budget burn ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'let sloTarget = 99.9;\nlet budget = 100.0 - sloTarget;\nrequests\n| where timestamp {TimeRange}\n| summarize Total=count(), Failed=countif(success == false)\n| extend ErrorRate = round(todouble(Failed) / todouble(Total) * 100, 4)\n| extend BudgetUsedPct = round(ErrorRate / budget * 100, 2)\n| extend BudgetRemaining = round(100.0 - BudgetUsedPct, 2)\n| extend Status = iff(BudgetUsedPct <= 50, "✅ Healthy", iff(BudgetUsedPct <= 80, "⚠️ Caution", "🔴 Critical"))\n| project [\'SLO Target\']=strcat(sloTarget, "%"), [\'Error Budget\']=strcat(budget, "%"), [\'Actual Error Rate\']=strcat(ErrorRate, "%"), [\'Budget Used\']=strcat(BudgetUsedPct, "%"), [\'Budget Remaining\']=strcat(BudgetRemaining, "%"), Status'
              size: 4
              title: 'Error Budget Burn'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'table'
            }
            name: 'tab-g-error-budget'
          }
        ]
      }
      conditionalVisibilities: [{ parameterName: 'SelectedTab', comparison: 'isEqualTo', value: 'tabG' }]
      name: 'group-tab-g'
    }

    // ========================================================================
    // TAB H — Investigations (Troubleshooting Playground)
    // ========================================================================
    {
      type: 12
      content: {
        version: 'NotebookGroup/1.0'
        groupType: 0
        items: [
          {
            type: 1
            content: {
              json: '## Investigations\\n\\nFlexible, parameter-driven drilldown. Pick an operation or time window to explore traces, logs, and exceptions.'
            }
            name: 'tab-h-header'
          }
          // ── Operation filter parameter ──
          {
            type: 9
            content: {
              version: 'KqlParameterItem/1.0'
              parameters: [
                {
                  id: guid('param-operation')
                  version: 'KqlParameterItem/1.0'
                  name: 'OperationFilter'
                  label: 'Operation Name'
                  type: 2
                  isRequired: false
                  query: 'requests\n| where timestamp {TimeRange}\n| summarize Count=count() by name\n| order by Count desc\n| take 50\n| project value=name, label=strcat(name, " (", Count, ")")'
                  crossComponentResources: [ '{AppInsights}' ]
                  typeSettings: { additionalResourceOptions: [ 'value::all' ] }
                  queryType: 0
                  resourceType: 'microsoft.insights/components'
                  value: 'value::all'
                }
                {
                  id: guid('param-severity')
                  version: 'KqlParameterItem/1.0'
                  name: 'SeverityFilter'
                  label: 'Min Severity'
                  type: 2
                  isRequired: false
                  typeSettings: { additionalResourceOptions: [] }
                  jsonData: '[\n  { "value": "0", "label": "Verbose" },\n  { "value": "1", "label": "Information" },\n  { "value": "2", "label": "Warning" },\n  { "value": "3", "label": "Error" },\n  { "value": "4", "label": "Critical" }\n]'
                  value: '2'
                }
              ]
              style: 'above'
            }
            name: 'tab-h-params'
          }
          // ── Request detail grid ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'requests\n| where timestamp {TimeRange}\n| where "*" == "{OperationFilter}" or name == "{OperationFilter}"\n| project timestamp, name, duration=round(duration,1), resultCode, success, cloud_RoleName, operation_Id\n| order by timestamp desc\n| take 100'
              size: 0
              title: 'Recent Requests'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'table'
              gridSettings: {
                sortBy: [ { itemKey: 'timestamp', sortOrder: 2 } ]
                formatters: [
                  { columnMatch: 'success', formatter: 18, formatOptions: { thresholdsOptions: 'icons', thresholdsGrid: [ { operator: '==', thresholdValue: 'true', representation: 'success', text: '' }, { operator: 'Default', representation: 'error', text: '' } ] } }
                ]
              }
            }
            name: 'tab-h-requests'
          }
          // ── Trace log viewer ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'traces\n| where timestamp {TimeRange}\n| where severityLevel >= toint("{SeverityFilter}")\n| project timestamp, message, severityLevel, cloud_RoleName, operation_Id\n| order by timestamp desc\n| take 200'
              size: 0
              title: 'Application Traces'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'table'
              gridSettings: {
                formatters: [
                  { columnMatch: 'severityLevel', formatter: 18, formatOptions: { thresholdsOptions: 'icons', thresholdsGrid: [ { operator: '>=', thresholdValue: '3', representation: 'error', text: '' }, { operator: '>=', thresholdValue: '2', representation: 'warning', text: '' }, { operator: 'Default', representation: 'info', text: '' } ] } }
                ]
              }
            }
            name: 'tab-h-traces'
          }
          // ── Exception details ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'exceptions\n| where timestamp {TimeRange}\n| project timestamp, type, [\'message\']=outerMessage, cloud_RoleName, operation_Id, problemId\n| order by timestamp desc\n| take 100'
              size: 0
              title: 'Recent Exceptions'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'table'
            }
            name: 'tab-h-exceptions'
          }
          // ── Dependency failures ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'dependencies\n| where timestamp {TimeRange}\n| where success == false\n| project timestamp, type, target, name, duration=round(duration,1), resultCode, cloud_RoleName, operation_Id\n| order by timestamp desc\n| take 100'
              size: 0
              title: 'Failed Dependencies'
              queryType: 0
              resourceType: 'microsoft.insights/components'
              crossComponentResources: [ '{AppInsights}' ]
              visualization: 'table'
            }
            name: 'tab-h-failed-deps'
          }
          // ── Windows Event Log (VM troubleshooting) ──
          {
            type: 3
            content: {
              version: 'KqlItem/1.0'
              query: 'Event\n| where TimeGenerated {TimeRange}\n| where EventLevelName in ("Error", "Critical", "Warning")\n| project TimeGenerated, Computer, EventLog, EventLevelName, RenderedDescription\n| order by TimeGenerated desc\n| take 100'
              size: 0
              title: 'Windows Event Log — Errors & Warnings (SQL VM)'
              queryType: 0
              resourceType: 'microsoft.operationalinsights/workspaces'
              crossComponentResources: [ '{LogAnalyticsWorkspace}' ]
              visualization: 'table'
              gridSettings: {
                formatters: [
                  { columnMatch: 'EventLevelName', formatter: 18, formatOptions: { thresholdsOptions: 'icons', thresholdsGrid: [ { operator: '==', thresholdValue: 'Critical', representation: 'critical', text: '' }, { operator: '==', thresholdValue: 'Error', representation: 'error', text: '' }, { operator: 'Default', representation: 'warning', text: '' } ] } }
                ]
              }
            }
            name: 'tab-h-event-log'
          }
        ]
      }
      conditionalVisibilities: [{ parameterName: 'SelectedTab', comparison: 'isEqualTo', value: 'tabH' }]
      name: 'group-tab-h'
    }
  ]
  fallbackResourceIds: [ appInsightsId ]
})

@description('Workbook resource ID.')
output workbookId string = workbook.id

@description('Workbook display name.')
output workbookName string = workbook.properties.displayName
