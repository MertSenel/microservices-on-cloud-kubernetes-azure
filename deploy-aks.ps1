[CmdletBinding()]
param (
    # Parameter help description
    [Parameter(Mandatory=$false)]
    [string]
    $settingsFilePath='settings.json'
)

$localConfigPath = "./local.settings.json"
$config = Get-Content -Path $localConfigPath | ConvertFrom-Json -Depth 10


Import-Module Az.Aks

AksArgs = @{
    ResourceGroupName = $config.Az_ResourceGroupName
    
}

New-AzAksCluster 