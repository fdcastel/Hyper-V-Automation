#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$VirtioIsoPath,
    
    [Parameter(Mandatory=$true)]
    [string]$ImagePath,

    [int]$ImageIndex = 1
)

$ErrorActionPreference = 'Stop'



#
# Source: https://pve.proxmox.com/wiki/Windows_10_guest_best_practices
#



#
# Functions
#

function With-IsoImage([string]$IsoFileName, [scriptblock]$ScriptBlock)
{
    $IsoFileName = (Resolve-Path $IsoFileName).Path

    Write-Verbose "Mounting '$IsoFileName'..."
    $mountedImage = Mount-DiskImage -ImagePath $IsoFileName -StorageType ISO -PassThru
    try 
    {
        $driveLetter = ($mountedImage | Get-Volume).DriveLetter
        Invoke-Command $ScriptBlock -ArgumentList $driveLetter
    }
    finally
    {
        Write-Verbose "Dismounting '$IsoFileName'..."
        Dismount-DiskImage -ImagePath $IsoFileName | Out-Null
    }
}

function With-WindowsImage([string]$ImagePath, [int]$ImageIndex, [string]$VirtioDriveLetter, [scriptblock]$ScriptBlock)
{
    $mountPath = Join-Path ([System.IO.Path]::GetTempPath()) "winmount\"

    Write-Verbose "Mounting '$ImagePath' ($ImageIndex)..."
    mkdir $mountPath -Force | Out-Null
    Mount-WindowsImage -Path $mountPath -ImagePath $ImagePath -Index $ImageIndex | Out-Null
    try
    {
        Invoke-Command $ScriptBlock -ArgumentList $mountPath
    }
    finally
    {
        Write-Verbose "Dismounting '$ImagePath' ($ImageIndex)..."
        Dismount-WindowsImage -Path $mountPath -Save | Out-Null
    }
}

function Add-DriversToWindowsImage($ImagePath, $ImageIndex, $VirtioDriveLetter)
{
    With-WindowsImage -ImagePath $ImagePath -ImageIndex $ImageIndex -VirtioDriveLetter $VirtioDriveLetter {
        Param($mountPath)

        Write-Verbose "  Adding driver 'vioscsi'..."
        Add-WindowsDriver -Path $mountPath -Driver "$($VirtioDriveLetter):\vioscsi\w10\amd64" -Recurse -ForceUnsigned | Out-Null

        Write-Verbose "  Adding driver 'NetKVM'..."
        Add-WindowsDriver -Path $mountPath -Driver "$($VirtioDriveLetter):\NetKVM\w10\amd64" -Recurse -ForceUnsigned | Out-Null

        Write-Verbose "  Adding driver 'Balloon'..."
        Add-WindowsDriver -Path $mountPath -Driver "$($VirtioDriveLetter):\Balloon\w10\amd64" -Recurse -ForceUnsigned | Out-Null
    }
}



#
# Main
#


With-IsoImage -IsoFileName $VirtioIsoPath {
    Param($virtioDriveLetter)

    $virtioInstaller = "$($virtioDriveLetter):\virtio-win-gt-x64.msi"
    $exists = Test-Path $virtioInstaller
    if (-not $exists)
    {
        throw "The specified ISO does not appear to be a valid Virtio installation media."
    }

    Add-DriversToWindowsImage -ImagePath $ImagePath -ImageIndex $ImageIndex -VirtioDriveLetter $virtioDriveLetter
}
