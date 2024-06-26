param
(
    [parameter(Mandatory = $true)] [String] $spn_id,
    [parameter(Mandatory = $true)] [String] $spn_secret,
    [parameter(Mandatory = $true)] [String] $tenant_id,
    [parameter(Mandatory = $true)] [String] $subscription_id
)

Write-Host "Login to subscription..."

az login --service-principal -u $spn_id -p $spn_secret -t $tenant_id
az account set -s $subscription_id

Write-Host "Creating logs folder..."

mkdir logs
cd logs

# Databricks

Write-Host "Getting Databricks logs..."

databricks -v

sudo az extension add --name databricks --debug

az extension list

$databricks_workspaces = $(az resource list --subscription $subscription_id --resource-type "Microsoft.Databricks/workspaces" --query "[].{name:name, resourceGroup:resourceGroup}" --output json | ConvertFrom-Json)
$databricks_workspaces
# loop over all databricks workspaces and retrieve the clusters

$AAD_TOKEN = $(az account get-access-token --resource=2ff814a6-3304-4ab8-85cb-cd0e6f879c1d | jq -r .accessToken)
$env:DATABRICKS_AAD_TOKEN = $AAD_TOKEN

$cluster_info = @()
$databricks_workspace_info = @{}
foreach ($databricks_workspace in $databricks_workspaces) {
    $databricks_workspace_name = $databricks_workspace.name
    $databricks_workspace_resource_group = $databricks_workspace.resourceGroup

    $workspace_info = az databricks workspace show --name $databricks_workspace_name --resource-group $databricks_workspace_resource_group | ConvertFrom-Json
    $databricks_workspace_info[$databricks_workspace_name] = $workspace_info

    Write-Host $workspace_info
    Write-Host $workspace_info.workspaceUrl

    $DATABRICKS_HOST = "https://$($workspace_info.workspaceUrl)"
    Write-Host "DATABRICKS_HOST: $DATABRICKS_HOST"

    # Configure the Databricks CLI
    Write-Host "Initializing the connection"
    databricks configure --profile dbrx --host $DATABRICKS_HOST --aad-token

    # List clusters and store information
    Write-Host "Listing the clusters"
    $clusters = databricks clusters list --profile dbrx --output json | ConvertFrom-Json
    $cluster_info += $clusters
}

$databricks_workspace_info | ConvertTo-Json | Out-File -FilePath databricks_workspaces.json
$cluster_info | ConvertTo-Json | Out-File -FilePath databricks_clusters.json

# Storage accounts

Write-Host "Getting storage accounts logs..."

az storage account list > storage_accounts.json

# Key vaults

Write-Host "Getting key vaults logs..."

$keyvaults = az keyvault list --query "[].{id:id, name:name}" | ConvertFrom-Json

$keyvaults_per_subscription = @()
foreach ($keyvault in $keyvaults) {
    $keyvaultInfo = @{
        "name"    = $keyvault.name
        "id"      = $keyvault.id
        "network" = @{
            "defaultAction" = $null  # Default to null
            "ipRules"       = @()
        }
    }
    $keyvaultName = $keyvault.name
    # Write-Host "Keyvault Name: $keyvaultName"
    # Get network settings for the key vault
    $network_settings = az keyvault network-rule list --name $keyvaultName | ConvertFrom-Json
    # Set default action if available
    if ($network_settings.defaultAction) {
        $keyvaultInfo.network.defaultAction = $network_settings.defaultAction
    }
    # Extract IP rules
    $keyvaultInfo.network.ipRules = $network_settings.ipRules | ForEach-Object { $_.value }
    $keyvaults_per_subscription += $keyvaultInfo
}
# Convert the array to JSON without escaping double quotes
$keyvaults_per_subscription | ConvertTo-Json -Depth 10 | Out-File -FilePath keyvaults.json

# az module

Write-Host "Installing az module..."

Install-Module Az -Force

# ADF integration runtimes

Write-Host "Getting ADF integration runtimes logs..."

# list all data factories in the subscription without knowing the resource group name

$datafactories = Get-AzDataFactoryV2

# loop over datafactories and get the integration runtimes

$integration_runtime_info = @()
foreach ($datafactory in $datafactories) {
    $datafactory_name = $datafactory.DataFactoryName
    $datafactory_resource_group = $datafactory.ResourceGroupName
    # Write-Host "Datafactory Name: $datafactory_name"
    # Write-Host "Datafactory Resource Group: $datafactory_resource_group"
    $integration_runtimes = Get-AzDataFactoryV2IntegrationRuntime -ResourceGroupName $datafactory_resource_group -DataFactoryName $datafactory_name

    # display the integration runtimes in a table

    $integration_runtimes | Format-Table

    # initialize empty json for integration runtime info
    foreach ($integration_runtime in $integration_runtimes) {
        $integration_info = Get-AzDataFactoryV2IntegrationRuntimeMetric -name $integration_runtime.Name -ResourceGroupName $datafactory_resource_group -DataFactoryName $datafactory_name | ConvertTo-Json
        $integration_runtime_info += $integration_info | ConvertFrom-Json
    }
}

$integration_runtime_info | ConvertTo-Json | Out-File -FilePath adf_shir.json

# NSG's

$nsgs = az network nsg list --query "[].{name:name, resourceGroup:resourceGroup}" | ConvertFrom-Json
$nsgs

$nsg_info = @()
foreach ($nsg in $nsgs) {
    $nsg_name = $nsg.name
    $nsg_resource_group = $nsg.resourceGroup
    Write-Host "NSG Name: $nsg_name"
    Write-Host "NSG Resource Group: $nsg_resource_group"
    $nsg_rules = az network nsg rule list --nsg-name $nsg_name --resource-group $nsg_resource_group | ConvertFrom-Json
    $nsg_info += @{
        Name = $nsg_name
        ResourceGroup = $nsg_resource_group
        Rules = $nsg_rules
    }
}

$nsg_info | ConvertTo-Json | Out-File -FilePath nsgs.json

# Routing tables

$routing_tables = az network route-table list --query "[].{name:name, resourceGroup:resourceGroup}" | ConvertFrom-Json
$routing_tables

$routing_table_info = @()
foreach ($routing_table in $routing_tables) {
    $routing_table_name = $routing_table.name
    $routing_table_resource_group = $routing_table.resourceGroup
    Write-Host "Routing Table Name: $routing_table_name"
    Write-Host "Routing Table Resource Group: $routing_table_resource_group"
    $routing_table_routes = az network route-table route list --route-table-name $routing_table_name --resource-group $routing_table_resource_group | ConvertFrom-Json
    $routing_table_info += @{
        Name = $routing_table_name
        ResourceGroup = $routing_table_resource_group
        Routes = $routing_table_routes
    }
}

$routing_table_info | ConvertTo-Json | Out-File -FilePath routing_tables.json

