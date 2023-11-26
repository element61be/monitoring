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
