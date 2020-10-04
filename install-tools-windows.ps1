<#
    Script to Show how to install istioctl and kubectl executables on a Windows Environment
#>

# Specify the Istio version that will be leveraged throughout these instructions
$localToolPath = 'C:\Users\Mert\source\tools'
$ISTIO_VERSION="1.7.3"
[Net.ServicePointManager]::SecurityProtocol = "tls12"
$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -URI "https://github.com/istio/istio/releases/download/$ISTIO_VERSION/istioctl-$ISTIO_VERSION-win.zip" -OutFile "istioctl-$ISTIO_VERSION.zip"
Expand-Archive -Path "istioctl-$ISTIO_VERSION.zip" -DestinationPath .

# Copy istioctl.exe to yout Local Tools Folder which you already have in your PATH variable
New-Item -ItemType Directory -Force -Path $localToolPath
Move-Item -Path .\istioctl.exe -Destination $localToolPath

## or else to the Microsoft Docs method and move it to C:\isto
# Copy istioctl.exe to C:\Istio
New-Item -ItemType Directory -Force -Path "C:\Istio"
Move-Item -Path .\istioctl.exe -Destination "C:\Istio\"

# Then you need to append this directory to your env PATH variable
# Add C:\Istio to PATH. 
# Make the new PATH permanently available for the current User
$USER_PATH = [environment]::GetEnvironmentVariable("PATH", "User") + ";C:\Istio\"
[environment]::SetEnvironmentVariable("PATH", $USER_PATH, "User")
# Make the new PATH immediately available in the current shell
$env:PATH += ";C:\Istio\"


# To Install KubeCtl via Azure Powershell Module
Install-AzAksKubectl -Destination $localToolPath