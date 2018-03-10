[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$OutFileName
)

$ErrorActionPreference = 'Stop'

# Note: Github removed TLS 1.0 support. Enables TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol-bor 'Tls12'

$url = 'https://cloud-images.ubuntu.com/releases/16.04/release/ubuntu-16.04-server-cloudimg-amd64-uefi1.img'
$imgFile = $OutFileName
if (-not $imgFile) {
    $imgFile = '.\ubuntu-16.04-server-cloudimg-amd64-uefi1.img'
}

$client = New-Object System.Net.WebClient
$client.DownloadFile($url, $imgFile)

# Check file integrity
$sha1Hash = Get-FileHash $imgFile -Algorithm SHA1
 $allHashs = $client.DownloadString('https://cloud-images.ubuntu.com/releases/16.04/release/SHA1SUMS')
$m = [regex]::Matches($allHashs, '(?<Hash>\w{40})\s\*ubuntu-16.04-server-cloudimg-amd64-uefi1.img')
$expectedHash = $m[0].Groups['Hash'].Value
if ($sha1Hash.Hash -ne $expectedHash) { throw 'Integrity check failed.' }

$imgFile
