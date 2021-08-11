[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$urlRoot = 'https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/'
$urlFile = 'virtio-win.iso'

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
}

$imgFile
