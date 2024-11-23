[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$url = "https://cloudbase.it/downloads/CloudbaseInitSetup_Stable_x64.msi"
$urlFile = 'CloudbaseInitSetup_Stable_x64.msi'

        
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
