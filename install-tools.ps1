# Specify the Istio version that will be leveraged throughout these instructions
$localToolPath = $localToolPath
$ISTIO_VERSION="1.7.3"

[Net.ServicePointManager]::SecurityProtocol = "tls12"
$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -URI "https://github.com/istio/istio/releases/download/$ISTIO_VERSION/istioctl-$ISTIO_VERSION-win.zip" -OutFile "istioctl-$ISTIO_VERSION.zip"
Expand-Archive -Path "istioctl-$ISTIO_VERSION.zip" -DestinationPath .

# Copy istioctl.exe to C:\Istio
New-Item -ItemType Directory -Force -Path $localToolPath
Move-Item -Path .\istioctl.exe -Destination $localToolPath

Install-AzAksKubectl -Destination $localToolPath