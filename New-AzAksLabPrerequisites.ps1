<#
    This Script is required to setup prerequisites in your Azure Subscription
    The Script will Generate Resource Group of your choosing in your desired Azure Region
    And then it generate a Service Principial That only has Access to that resource Group, you can feed into you Github Actions
    Altough Secrets are protected, I still won't use a Subscription Level RBAC assignment, it's way too dangerous for the convinience it provides. 
#>

#Requires -Module @{ ModuleName = 'Az'; ModuleVersion = '4.7' }

#Get the Local Config File
$localConfigPath = "./local.settings.json"
$config = Get-Content -Path $localConfigPath | ConvertFrom-Json -Depth 10

#Makes Sure You are in the correct Azure Subscription
Set-AzContext -Subscription $config.Az_SubscriptionID

#Creates a New Resource Group
$ResourceGroup = New-AzResourceGroup -Name $config.Az_ResourceGroupName -Location $config.Az_Location -Force

$SpnName = $config.Az_SpnName

# Create Service Principal with Az Cli as it already generates a Secret and able to print out result in SDK expected format
# See this link for more information https://github.com/marketplace/actions/azure-login
$SPNCreds = az ad sp create-for-rbac --name $SpnName --sdk-auth --role contributor --scopes $ResourceGroup.ResourceId

$SPNCreds | Set-Content -Path './local.spn.creds.json' -Force