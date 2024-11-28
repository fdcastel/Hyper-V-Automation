#
# Functions for working with cloud-init Metadata drives.
#

function New-MetadataIso(
    [string]$VMName,
    [string]$Metadata,
    [string]$UserData,
    [string]$NetworkConfig
) {
    Write-Verbose 'Creating metadata ISO image...'
    $tempPath = [System.IO.Path]::GetTempPath()

    # Creates temporary folder for ISO content.
    $metadataContentRoot = Join-Path $tempPath "$VMName-metadata"
    mkdir $metadataContentRoot > $null
    try {
        # Write metadata files.
        $Metadata | Out-File "$metadataContentRoot\meta-data" -Encoding ascii
        $UserData | Out-File "$metadataContentRoot\user-data" -Encoding ascii
        $NetworkConfig | Out-File "$metadataContentRoot\network-config" -Encoding ascii

        # Use temp folder for metadata ISO -- https://github.com/fdcastel/Hyper-V-Automation/issues/13
        $metadataIso = Join-Path $tempPath "$VMName-metadata.iso"

        # Write metadata ISO file.
        $oscdimgPath = Join-Path $PSScriptRoot '.\oscdimg.exe'
        & {
            $ErrorActionPreference = 'Continue'
            & $oscdimgPath $metadataContentRoot $metadataIso -j2 -lCIDATA
            if ($LASTEXITCODE -gt 0) {
                throw "oscdimg.exe returned $LASTEXITCODE."
            }
        } *> $null

        Write-Verbose "Metadata ISO created: $metadataIso"
        return $metadataIso
    }
    finally {
        # Clear temporary folder.
        Remove-Item -Path $metadataContentRoot -Recurse -Force
        $ErrorActionPreference = 'Stop'
    }
}
