###########################################################
# Start - Initialization - Invocation, Logging etc
###########################################################
$VerbosePreference = "SilentlyContinue"
$ErrorActionPreference = "Stop"

$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path $scriptPath

& "$scriptDir\..\scripts\init.ps1"
if(-not $?)
{
    throw "Initialization failure."
}
###########################################################
# End - Initialization - Invocation, Logging etc
###########################################################

$inputConfig = @{
VNET="true"
EVENTHUBS="true"
KAFKA="true"
SQLAZURE="true"
}

#Create Run Configuration
& "$scriptDir\..\scripts\config\CreateRunConfig.ps1" $scriptDir "eventcount" $inputConfig
if(-not $?)
{
    Write-ErrorLog "Creation of Run Configuration failed. Please check the logs for error information or retry." (Get-ScriptName) (Get-ScriptLineNumber)
    throw "Creation of Run Configuration failed. Please check the logs for error information or retry."
}

#Create Azure Resources
& "$scriptDir\..\scripts\azure\CreateAzureResources.ps1" $scriptDir
if(-not $?)
{
    Write-ErrorLog "Creation of Azure Resources failed. Please check the logs for error information or retry." (Get-ScriptName) (Get-ScriptLineNumber)
    throw "Creation of Azure Resources failed. Please check the logs for error information or retry."
}

#Update Project Properties
$configFile = Join-Path $scriptDir "run\configurations.properties"
$config = & "$scriptDir\..\scripts\config\ReadConfig.ps1" $configFile

$clusterInformation = & "$scriptDir\..\scripts\storm\GetAmbariClusterInformation.ps1" $config["KAFKA_CLUSTER_URL"] $config["KAFKA_CLUSTER_USERNAME"] $config["KAFKA_CLUSTER_PASSWORD"] $config["KAFKA_CLUSTER_NAME"]

$kafkaBrokers = $($clusterInformation.items.Hosts | ? {$_.host_name -like "wn*"} | % { $_.host_name + ":9092"}) -Join ","
Write-InfoLog "Kafka Brokers: $kafkaBrokers"
$config.add("KAFKA_BROKERS", $kafkaBrokers)

$kafkaZookeepers = $($clusterInformation.items.Hosts | ? {$_.host_name -like "zk*"} | % { $_.host_name + ":2181"}) -Join ","
Write-InfoLog "Kafka Zookeepers: $KafkaZookeepers"
$config.add("KAFKA_ZOOKEEPERS", $kafkaZookeepers)

& "$scriptDir\..\scripts\config\ReplaceStringInFile.ps1" "$scriptDir\EventGenTopology\myconfig.properties.template" "$scriptDir\EventGenTopology\src\main\resources\myconfig.properties" $config
& "$scriptDir\..\scripts\config\ReplaceStringInFile.ps1" "$scriptDir\EventCountTopology\myconfig.properties.template" "$scriptDir\EventCountTopology\src\main\resources\myconfig.properties" $config

$updateConfig = @{
EventHubFqnAddress=$config["EVENTHUBS_FQDN_SUFFIX"]
EventHubNamespace=$config["EVENTHUBS_NAMESPACE"]
EventHubEntityPath=$config["EVENTHUBS_ENTITY_PATH"]
EventHubSharedAccessKeyName=$config["EVENTHUBS_USERNAME"]
EventHubSharedAccessKey=$config["EVENTHUBS_PASSWORD"]
EventHubPartitions=$config["EVENTHUBS_PARTITION_COUNT"]
SqlDbServerName=$config["SQLAZURE_SERVER_NAME"]
SqlDbDatabaseName=$config["SQLAZURE_DB_NAME"]
SqlDbUsername=$config["SQLAZURE_USER"]
SqlDbPassword=$config["SQLAZURE_PASSWORD"]
}

$topologyDir = Join-Path $scriptDir "EventCountHybridTopology"

& "$scriptDir\..\scripts\scpnet\UpdateScpAppConfig.ps1" "$topologyDir\App.config" $updateConfig