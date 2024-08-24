# Logstash Examples

Example Logstash pipelines that can be deployed to an Azure Container App for development or testing. This may be useful when the pipeline needs to be reachable externally.

## JSON to Azure Log Analytics

[`json-azureloganalytics`](https://github.com/chrisred/az-logstash-example/tree/master/json-azureloganalytics) deploys a pipeline where JSON data is sent to Azure Log Analytics.

## LogicMonitor to ServiceNow

[`logicmonitor-servicenow`](https://github.com/chrisred/az-logstash-example/tree/master/logicmonitor-servicenow) deploys a pipeline where LogicMonitor events are sent to a ServiceNow Event Management endpoint.