[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SourceVhdx,

    [string]$TargetQcow2
)

$ErrorActionPreference = 'Stop'

if (-not $TargetQcow2) {
    $TargetQcow2 = [io.path]::ChangeExtension($SourceVhdx, '.qcow2')
}

& qemu-img.exe convert -p -f vhdx -O qcow2 $SourceVhdx $TargetQcow2 2>&1 | Write-Verbose
if ($LASTEXITCODE -ne 0) {
    throw "qemu-img returned $LASTEXITCODE. Aborting."
}

$TargetQcow2