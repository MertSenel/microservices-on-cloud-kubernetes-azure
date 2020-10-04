[CmdletBinding()]
param (
    # Name of the Environment Variable Script will get the Azure SPN Credentials
    [Parameter()][string]$EnvironmentVariableName = 'AZURE_CREDENTIALS',
    [Parameter()][string]$ArmTemplateFilePath = './arm/aks.json',
    [Parameter()][string]$ArmTemplateParameterFilePath = './arm/aks.parameters.json',
    [Parameter()][string]$ISTIO_VERSION = "1.7.3",
    [Parameter()][string]$APPL_VERSION = 'v0.2.0',
    [Parameter()][string]$APPL_NS = 'default',
    [Parameter()][switch]$DeployInfra,
    [Parameter()][switch]$DeployServices,
    [Parameter()][switch]$ForceUniqueName,
    [Parameter()][switch]$CleanUpLabResources
)
# If ForceUniqueName naming flag is passed Assign a Hyphen followed by a Random Integer to $Build_Uid if not passed just assign an empty String
$Build_Uid = $ForceUniqueName ? ('-' + (Get-Random -Maximum 99999).ToString()) : ""

#Setup config and credentials
$localSpnCreds = Get-ChildItem -Path "Env:\$EnvironmentVariableName"
$spn = $localSpnCreds.Value | ConvertFrom-Json

$ArmTemplateParameters = Get-Content -Path $ArmTemplateParameterFilePath | ConvertFrom-Json -Depth 10
$config = $ArmTemplateParameters.parameters.config.value

#region Curate Variables
$SubscriptionId = $spn.subscriptionId
$ResourceGroupName = $config.project + '-' + $config.env + '-' + 'aks' + '-' + $config.region + $config.num + $Build_Uid
$AksClusterName = $config.project + $config.env + $config.region + $config.num + '-' + 'aks' + $Build_Uid
$logAnalyticsWorkspaceName = $config.project + $config.env + $config.region + $config.num + '-' + 'oms' + $Build_Uid
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

if ($DeployInfra) {
    #Create/Update the resource Group
    New-AzResourceGroup -ResourceGroupName $ResourceGroupName -Location $Location -Force | out-null

    $Args = @{
        ResourceGroupName     = $ResourceGroupName
        Name                  = "$(new-guid)"
        TemplateFile          = $ArmTemplateFilePath
        TemplateParameterFile = $ArmTemplateParameterFilePath
        GITHUB_RUN_ID         = $Build_Uid
    }

    Write-Output "Start ARM Deployment"
    $AzDeployment = New-AzResourceGroupDeployment @Args

    #Update Resource Names with Deployment Outputs In case They are Different/Randomized
    $AksClusterName = $AzDeployment.Outputs.aksClusterName.value
    $logAnalyticsWorkspaceName = $AzDeployment.Outputs.logAnalyticsWorkspaceName.value
    Write-Output "End ARM Deployment"
}

if ($DeployServices) {
    Write-Output "Get kubectl Credentials"
    Import-AzAksCredential -ResourceGroupName $ResourceGroupName -Name $AksClusterName -Force
    Write-Output "Got kubectl Credentials"

    #region Install Istio 
    Write-Output "Start istio operator init"
    istioctl operator init
    Write-Output "Finished istio operator init"

    Write-Output "Startkubectl create ns istio-system"
    kubectl create ns istio-system
    Write-Output "Finished kubectl create ns istio-system"
    Start-Sleep -Seconds 5

    Write-Output "Startkubectl apply -f istio.aks.yaml"
    kubectl apply -f './ps1/workflow/istio.aks.yaml'
    Write-Output "Finished kubectl apply -f istio.aks.yaml"

    $prometheus = kubectl get deployment.apps/prometheus -n istio-system
    $grafana = kubectl get deployment.apps/grafana -n istio-system
    $kiali = kubectl get deployment.apps/kiali -n istio-system

    $retryCounter = 0
    while (((!$prometheus) -or (!$grafana) -or (!$kiali)) -and ($retryCounter -lt 30)) {
        $prometheus = (kubectl get deployment.apps/prometheus -n istio-system 2> $null)
        $grafana = (kubectl get deployment.apps/grafana -n istio-system 2> $null)
        $kiali = (kubectl get deployment.apps/kiali -n istio-system 2> $null)
        Write-Output "Waiting for Istio Add-On Deployments To be Created"
        Start-Sleep -Seconds 30
        $retryCounter++
    }
    Write-Output "All Istio Add-On Deployments Found"

    Write-Output "Start Waiting for Istio Addon Deployment to be Completed"
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

    #Deploy Services
    Write-Output "Start Activatiation istio for ns: $APPL_NS"
    kubectl label namespace --overwrite "$APPL_NS" istio-injection='enabled'
    kubectl get namespaces -L istio-injection
    Write-Output "Finished Activatiation istio for ns: $APPL_NS"

    Write-Output "### deploy application: "
    kubectl apply -f "https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/$($APPL_VERSION)/release/kubernetes-manifests.yaml"
    Write-Output "### wait for resources to become available: "
    kubectl wait --for=condition=available --timeout=500s deployment/adservice
    kubectl wait --for=condition=available --timeout=500s deployment/cartservice
    kubectl wait --for=condition=available --timeout=500s deployment/checkoutservice
    kubectl wait --for=condition=available --timeout=500s deployment/currencyservice
    kubectl wait --for=condition=available --timeout=500s deployment/emailservice
    kubectl wait --for=condition=available --timeout=500s deployment/frontend
    kubectl wait --for=condition=available --timeout=500s deployment/loadgenerator
    kubectl wait --for=condition=available --timeout=500s deployment/paymentservice
    kubectl wait --for=condition=available --timeout=500s deployment/productcatalogservice
    kubectl wait --for=condition=available --timeout=500s deployment/recommendationservice
    kubectl wait --for=condition=available --timeout=500s deployment/shippingservice
}

#Clean Up
if ($CleanUpLabResources) {
    Write-Output "Clean Up Lab Resource as CleanUpLabResources Flag is Passed"
    #Force Delete Log Analytics Workspace Otherwise it doesn't release the DNS name for 14 day due to soft-delete behaviour
    #See: https://docs.microsoft.com/en-us/azure/azure-monitor/platform/delete-workspace#soft-delete-behavior
    Remove-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $logAnalyticsWorkspaceName -ForceDelete
    Remove-AzResourceGroup -Name $ResourceGroupName -Force
}
else {
    kubectl get all -n "$APPL_NS"
}
