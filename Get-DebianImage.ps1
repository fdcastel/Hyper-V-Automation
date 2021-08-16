[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

# Enables TLS 1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$urlRoot = "https://cloud.debian.org/images/cloud/bullseye/latest/"

$urlFile = "debian-11-genericcloud-amd64.qcow2"

$url = "$urlRoot/$urlFile"
        
if (-not $OutputPath) {
    $OutputPath = Get-Item '.\'
}

$imgFile = Join-Path $OutputPath $urlFile

if ([System.IO.File]::Exists($imgFile)) {
    Write-Verbose "File '$imgFile' already exists. Nothing to do."
} else {
    Write-Verbose "Downloading file '$imgFile'..."

    $client = New-Object System.Net.WebClient
    $client.DownloadFile($url, $imgFile)

    Write-Verbose "Checking file integrity..."
    $sha1Hash = Get-FileHash $imgFile -Algorithm SHA512
    $allHashs = $client.DownloadString("$urlRoot/SHA512SUMS")
    $m = [regex]::Matches($allHashs, "(?<Hash>\w{128})\s\s$urlFile")
    if (-not $m[0]) { throw "Cannot get hash for $urlFile." }
    $expectedHash = $m[0].Groups['Hash'].Value
    if ($sha1Hash.Hash -ne $expectedHash) { throw "Integrity check for '$imgFile' failed." }
}

$imgFile
