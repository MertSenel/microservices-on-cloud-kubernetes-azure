<#
    This Script will generate a Service Principial to be used in Azure Login Github Action as a Secret 
#>
[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $SpnName="azure-k8s-lab-ga-spn",
    # Parameter help description
    [Parameter()]
    [string]
    $EnvironmentVariableName = 'AZURE_CREDENTIALS'
)
# Create Service Principal with Az Cli as it already generates a Secret and able to print out result in SDK expected format
# See this link for more information https://github.com/marketplace/actions/azure-login
$SPNCreds = az ad sp create-for-rbac --name $SpnName --sdk-auth --role contributor

# Save the SPN Credentials to a local file so you can use it to create your Github Repository Secret
$SPNCreds | Set-Content -Path "./$EnvironmentVariableName.json" -Force

# We will also save it as an environment variable
$LocalEnvVar = Get-Content -Path "./$EnvironmentVariableName.json" | ConvertFrom-Json | ConvertTo-Json -Compress
Set-Item -Path "Env:\$EnvironmentVariableName" -Value $LocalEnvVar

