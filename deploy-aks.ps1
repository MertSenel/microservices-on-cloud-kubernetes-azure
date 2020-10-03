[CmdletBinding()]
param (
    # Name of the Environment Variable Script will get the Azure SPN Credentials
    [Parameter()][string]$EnvironmentVariableName = 'AZURE_CREDENTIALS',
    [Parameter()][string]$ArmTemplateFilePath = './arm/aks.json',
    [Parameter()][string]$ArmTemplateParameterFilePath = './arm/aks.parameters.json'
)


$localSpnCreds = Get-ChildItem -Path "Env:\$EnvironmentVariableName"
$spn = $localSpnCreds.Value | ConvertFrom-Json

$ArmTemplateParameters = Get-Content -Path $ArmTemplateParameterFilePath | ConvertFrom-Json -Depth 10
$config = $ArmTemplateParameters.parameters.config.value

#region Curate Variables
$SubscriptionId = $spn.subscriptionId
$ResourceGroupName = $config.project + '-' + $config.env + '-' + 'aks' + '-' + $config.region + $config.num
$AksClusterName = $config.project + $config.env + $config.region + $config.num + '-aks'
$Location = $ArmTemplateParameters.parameters.location.value
#endregion

#region Connect To Azure if Not connected Already
$CurrentContext = Get-AzContext

if ((!$CurrentContext) -or ($CurrentContext.Subscription.Id -ne $SubscriptionId)) {
    [string]$clientId = $spn.clientId
    [string]$clientSecret = $spn.clientSecret
    # Convert to SecureString
    [securestring]$secClientSecret = ConvertTo-SecureString $clientSecret -AsPlainText -Force
    [pscredential]$spnCreds = New-Object System.Management.Automation.PSCredential ($clientId, $secClientSecret)
    Connect-AzAccount -ServicePrincipal -Credential $spnCreds -Tenant $spn.tenantId -Scope Process | out-null
    Set-AzContext -Subscription $SubscriptionId | Out-Null
}
#endregion

#Create/Update the resource Group
New-AzResourceGroup -ResourceGroupName $ResourceGroupName -Location $Location -Force | out-null

$Args = @{
    ResourceGroupName     = $ResourceGroupName
    Name                  = "$(new-guid)"
    TemplateFile          = $ArmTemplateFilePath
    TemplateParameterFile = $ArmTemplateParameterFilePath
}

Write-Output "Start ARM Deployment"
$AzDeployment = New-AzResourceGroupDeployment @Args

Write-Output "Get kubectl Credentials"
if ($LASTEXITCODE -eq 0) {
    Import-AzAksCredential -ResourceGroupName $ResourceGroupName -Name $AksClusterName -Force
}
else {
    exit 1
}

#region Install Istio 
Write-Output "istio operator init"
istioctl operator init

Write-Output "kubectl create ns istio-system"
kubectl create ns istio-system

Write-Output "kubectl apply -f istio.aks.yaml"
kubectl apply -f istio.aks.yaml 

Start-Sleep -Seconds 5

Write-Host "Waiting for Istio Addons"
kubectl wait --for=condition=available --timeout=500s deployment/prometheus -n istio-system
kubectl wait --for=condition=available --timeout=500s deployment/grafana -n istio-system
kubectl wait --for=condition=available --timeout=500s deployment/kiali -n istio-system