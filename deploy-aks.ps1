[CmdletBinding()]
param (
    # Name of the Environment Variable Script will get the Azure SPN Credentials
    [Parameter()][string]$EnvironmentVariableName = 'AZURE_CREDENTIALS',
    [Parameter()][string]$ArmTemplateFilePath = './arm/aks.json',
    [Parameter()][string]$ArmTemplateParameterFilePath = './arm/aks.parameters.json',
    [Parameter()][string]$ISTIO_VERSION = "1.7.3"
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

Write-Output "End ARM Deployment"

Write-Output "Get kubectl Credentials"
Import-AzAksCredential -ResourceGroupName $ResourceGroupName -Name $AksClusterName -Force
Write-Output "Got kubectl Credentials"

#region Install Istio 
Write-Output "Start istio operator init"

#Download the istioctl first
$ISTIO_VERSION="1.7.3"
[Net.ServicePointManager]::SecurityProtocol = "tls12"
$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -URI "https://github.com/istio/istio/releases/download/$ISTIO_VERSION/istioctl-$ISTIO_VERSION-win.zip" -OutFile "istioctl-$ISTIO_VERSION.zip"
Expand-Archive -Path "istioctl-$ISTIO_VERSION.zip" -DestinationPath .

./istioctl.exe operator init

Write-Output "Finished istio operator init"

Write-Output "Startkubectl create ns istio-system"
kubectl create ns istio-system
Write-Output "Finished kubectl create ns istio-system"

Write-Output "Startkubectl apply -f istio.aks.yaml"
kubectl apply -f istio.aks.yaml 
Write-Output "Finished kubectl apply -f istio.aks.yaml"

Start-Sleep -Seconds 5

Write-Output "Start Waiting for Istio Addons"
kubectl wait --for=condition=available --timeout=500s deployment/prometheus -n istio-system
kubectl wait --for=condition=available --timeout=500s deployment/grafana -n istio-system
kubectl wait --for=condition=available --timeout=500s deployment/kiali -n istio-system
Write-Output "Finished Waiting for Istio Addons"

#Deploy Polaris
Write-Output "Start Deploy Polaris"
kubectl apply -f https://github.com/FairwindsOps/polaris/releases/latest/download/dashboard.yaml
kubectl get namespaces | Select-String polaris
kubectl wait --for=condition=available --timeout=500s deployment/polaris-dashboard -n polaris
#kubectl port-forward --namespace polaris svc/polaris-dashboard 8080:80
Write-Output "Finished Deploy Polaris"