# LogicMonitor to ServiceNow

A minimal [Logstash](https://www.elastic.co/logstash) deployment using an [Azure Container App](https://learn.microsoft.com/en-us/azure/container-apps/) for testing or development. The pipeline in this example accepts events from [LogicMonitor](https://www.logicmonitor.com/) and sends them to a ServiceNow [Event Management](https://docs.servicenow.com/csh?topicname=c_EM.html&version=latest) endpoint.

## Creation

Steps to deploy the resources and configure the pipeline. 

### Deployment

1. Create a Resource Group as the target for the deployment.

2. Use the "Deploy to Azure" link to deploy the template, or run the command below in a Bash Cloud Shell.

    [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fchrisred%2Faz-logstash-example%2Fmaster%2Flogicmonitor-servicenow%2Flogstash.json)

    The parameters below require a value to be set. `logstashInputPass` sets the password for the pipeline basic authentication (the user ID is set to `logicmonitor` by default). The `logstashOutput*` parameters set the ServiceNow URL and credentials required to send events to the Event Management [web service API](https://docs.servicenow.com/csh?topicname=send-events-via-web-service.html&version=latest).

    ```bash
    az deployment group create --resource-group logstash-example \
        --template-uri https://raw.githubusercontent.com/chrisred/az-logstash-example/master/logicmonitor-servicenow/logstash.bicep \
        --parameters \
        logstashInputPass=<password> \
        logstashOutputUrl=https://<instancename>.service-now.com/api/global/em/jsonv2 \
        logstashOutputUser=<servicenow_userid> \
        logstashOutputPass=<servicenow_password>
    ```

### Configuration

1. With the resources deployed successfully we can populate the `logstash-config` Azure Files share with the configuration files. The following script will upload the required files, it can be copy and pasted into a Bash Cloud Shell. Replace `<storageaccountname>` and `<storageaccountkey>` with the relevant value, the key is found under "Access Keys" for the Storage Account resource.

    ```bash
    ACCOUNT_NAME=<storageaccountname>
    ACCOUNT_KEY=<storageaccountkey>
    SHARE_NAME=logstash-config

    wget https://raw.githubusercontent.com/elastic/logstash/main/config/jvm.options
    wget https://raw.githubusercontent.com/elastic/logstash/main/config/log4j2.properties
    wget https://raw.githubusercontent.com/chrisred/az-logstash-example/master/logicmonitor-servicenow/logstash.yml
    wget https://raw.githubusercontent.com/chrisred/az-logstash-example/master/logicmonitor-servicenow/logstash.conf

    az storage file upload --account-name $ACCOUNT_NAME --account-key $ACCOUNT_KEY --path jvm.options --share-name $SHARE_NAME --source jvm.options
    az storage file upload --account-name $ACCOUNT_NAME --account-key $ACCOUNT_KEY --path log4j2.properties --share-name $SHARE_NAME --source log4j2.properties
    az storage file upload --account-name $ACCOUNT_NAME --account-key $ACCOUNT_KEY --path logstash.yml --share-name $SHARE_NAME --source logstash.yml
    az storage file upload --account-name $ACCOUNT_NAME --account-key $ACCOUNT_KEY --path logstash.conf --share-name $SHARE_NAME --source logstash.conf
    ```

2. Restart the the container so Logstash reads the configuration files. To do this stop and start the Container App from the Overview section in the portal, or use the following command: `az containerapp revision restart --revision <revision_name> --resource-group <resource_group>`.

## Usage

The Container App "Overview" shows the `Application Url`. Loading the URL in a browser should raise an authentication prompt, this shows the Logstash pipeline is responding. This URL would be configured within LogicMonitor.

The Log stream section captures the container `STDOUT` messages, the line `[INFO ][logstash.javapipeline    ][main] Pipeline started {"pipeline.id"=>"main"}` indicates the pipeline has started successfully.

The Scale settings for the container have `Min replicas` set to `0` and `Max replicas` set to `1`. With these settings after 300 seconds with no incoming requests the container will stop, the next request will need to wait for it to start again. Set `Min replicas` to `1` to keep the container permanently running. During container initialization the `json_encode` filter plugin is installed which increases the startup time.

See [this repository](https://github.com/chrisred/logstash-pipeline-conf/tree/master#logicmonitor-to-servicenow) for more details on the pipeline.