# Enables TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$url = 'https://codeload.github.com/fdcastel/Hyper-V-Automation/zip/master'
$fileName = Join-Path $env:TEMP 'Hyper-V-Automation-master.zip'

Invoke-RestMethod $url -OutFile $fileName
Expand-Archive $fileName -DestinationPath $env:TEMP -Force

cd "$env:TEMP\Hyper-V-Automation-master"
