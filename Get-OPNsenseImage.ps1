[CmdletBinding()]
param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

$urlRoot = 'https://mirror.dns-root.de/opnsense/releases/mirror/'
$urlFile = 'OPNsense-22.1.2-OpenSSL-dvd-amd64.iso.bz2'

$url = "$urlRoot/$urlFile"
        
if (-not $OutputPath) {
    $OutputPath = Get-Item '.\'
}

$isoFile = Join-Path $OutputPath $urlFile

$uncompressedUrlFile = [System.IO.Path]::GetFileNameWithoutExtension($urlFile)
$uncompressedIsoFile = Join-Path $OutputPath $uncompressedUrlFile

if ([System.IO.File]::Exists($uncompressedIsoFile)) {
    Write-Verbose "File '$uncompressedIsoFile' already exists. Nothing to do."
} else {
    if ([System.IO.File]::Exists($isoFile)) {
        Write-Verbose "File '$isoFile' already exists."
    } else
    {
        Write-Verbose "Downloading file '$isoFile'..."

        $client = New-Object System.Net.WebClient
        $client.DownloadFile($url, $isoFile)
    }

    $7zCommand = Get-Command "7z.exe" -ErrorAction SilentlyContinue
    if (-not $7zCommand) 
    { 
        throw "7z.exe not found. Please install it with 'choco install 7zip -y'."
    }

    Write-Verbose "Extracting file '$isoFile' to '$OutputPath'..."
    & 7z.exe e $isoFile "-o$($OutputPath)" | Out-Null

    $fileExists = Test-Path -Path $uncompressedisoFile
    if (-not $fileExists) {
        throw "Image '$uncompressedUrlFile' not found after extracting .bz2 file."
    }
}

$uncompressedIsoFile
