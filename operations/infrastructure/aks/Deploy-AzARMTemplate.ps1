#Requires -Module @{ ModuleName = 'Az'; ModuleVersion = '4.2' }

[CmdletBinding()]
param (
    [Parameter()][switch]$WhatIf,
    [Parameter()][switch]$Test,
    [Parameter()][switch]$Force
)
#region Configuration
#Deployment Assets Configuration
# Go Up one level so you can pick a project
# This is here in case you want to keep your script in different folder.
$OperationsPath = Split-Path $PSScriptRoot 
$ArmArtifactsPath = "$OperationsPath\infrastructure" # Target the folder which desired ARM Template and Parameter files are in. 

#Azure Environment Configuration
$TenantId = '76d89495-0839-45fd-a549-c8ea16e6d5e0'
$SubscriptionId = '9ba089ac-b8fc-496b-a408-e42840ba07de'
#endregion

#region Connect to Correct Tenant and Subscription
$CurrentContext = Get-AzContext
#If there is no AzContext found connect to desired Subscription and Tenant
if (!$CurrentContext) {
    Connect-AzAccount -Tenant $TenantId -Subscription $SubscriptionId -UseDeviceAuthentication
    $CurrentContext = Get-AzContext
}
#If subscription ID doesnt match, call the Set-AzContext with 
#SubscriptionId and TenantId to allow switch between tenants as well. 
if ($CurrentContext.Subscription.Id -ne $SubscriptionId) {
    $CurrentContext = Set-AzContext -Subscription $SubscriptionId -Tenant $TenantId
}
#endregion

#region Service Constants
$ProjectName = 'mert'
$Stage = 'dev'
$ServiceType = 'aks'
$Region = "aue"
#endregion

#region Service Curated Parameters
$ResourceGroupName = $ProjectName + $Stage + $ServiceType + $Region + '01'
$TemplateFile = "$ArmArtifactsPath\template.json"
$TemplateParameterFile = "$ArmArtifactsPath\parameters.$Stage.$($Region)01.json"

$ARGS = @{
    ResourceGroupName     = $ResourceGroupName
    TemplateFile          = $TemplateFile
    TemplateParameterFile = $TemplateParameterFile
    Mode                  = 'Incremental'
    Verbose               = $true
    ErrorAction           = 'Stop'
}
#endregion

#region Deployment Helpers
$ErrorActionPreference = "Stop"
if ($Test) {
    Test-AzResourceGroupDeployment @ARGS
    exit $LASTEXITCODE
}
if ($WhatIf) {
    $WhatIfResult = Get-AzResourceGroupDeploymentWhatIfResult @ARGS `
                                    -ResultFormat FullResourcePayloads
    $WhatIfResult
    exit $LASTEXITCODE
}
#endregion

#region Deployment ("Validate & Deploy" or "Forced" Deployment)
try {
    $PromptForConfirmation = (($Force) ? $false : $true)
    Write-Host "Deploying $Region"
    $Deployment = New-AzResourceGroupDeployment @ARGS `
                                                -Name "$(New-Guid)" `
                                                -Confirm:$PromptForConfirmation `
                                                -WhatIfResultFormat FullResourcePayloads
}
catch {
    Write-Host $_.Exception.Message
    exit $LASTEXITCODE
}

# Tell me If my Deployment was Successfull
if ($Deployment.ProvisioningState -eq "Succeeded") {
    Write-Host "Deployed $Region Successfully"
}
# Or if there was an error during Deployment I want to know about it
elseif ($Deployment.ProvisioningState -ne "Succeeded" -and ($Deployment.CorrelationId)) {
    Write-Host "$(Get-AzLog -CorrelationId $Deployment.CorrelationId)"
}
# Else just let me know if there was no AzResourceGroupDeployment Object found
elseif (!($Deployment)) {
    Write-Warning "No AzResourceGroupDeployment Object Found"
}
#endregion