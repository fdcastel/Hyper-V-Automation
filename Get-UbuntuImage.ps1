[CmdletBinding()]
param(
    [string]$OutFileName,
    
    [switch]$Previous
)

$ErrorActionPreference = 'Stop'

# Note: Github removed TLS 1.0 support. Enables TLS 1.2
# [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol-bor 'Tls12'

$urlRoot = 'https://cloud-images.ubuntu.com/releases/18.04/release'
$urlFile = 'ubuntu-18.04-server-cloudimg-amd64.img'

if ($Previous) {
    $urlRoot = 'https://cloud-images.ubuntu.com/releases/16.04/release'
    $urlFile = 'ubuntu-16.04-server-cloudimg-amd64-uefi1.img'
}

$url = "$urlRoot/$urlFile"
        
$imgFile = $OutFileName
if (-not $imgFile) {
    $imgFile = ".\$urlFile"
}

$client = New-Object System.Net.WebClient
$client.DownloadFile($url, $imgFile)

# Check file integrity
$sha1Hash = Get-FileHash $imgFile -Algorithm SHA1
$allHashs = $client.DownloadString("$urlRoot/SHA1SUMS")
$m = [regex]::Matches($allHashs, "(?<Hash>\w{40})\s\*$urlFile")
if (-not $m[0]) { throw "Cannot get SHA1 hash for $urlFile." }
$expectedHash = $m[0].Groups['Hash'].Value
if ($sha1Hash.Hash -ne $expectedHash) { throw 'Integrity check failed.' }

$imgFile
