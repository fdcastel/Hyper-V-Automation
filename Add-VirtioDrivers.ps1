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
# Main
#

# Reference: https://pve.proxmox.com/wiki/Windows_10_guest_best_practices

. .\tools\Virtio-Functions.ps1

With-IsoImage -IsoFileName $VirtioIsoPath {
    Param($virtioDriveLetter)

    # Throws if the ISO does not contain Virtio drivers.
    $virtioDrivers = Get-VirtioDrivers -VirtioDriveLetter $virtioDriveLetter

    With-WindowsImage -ImagePath $ImagePath -ImageIndex $ImageIndex -VirtioDriveLetter $VirtioDriveLetter {
        Param($mountPath)

        $virtioDrivers | ForEach-Object {
            Add-WindowsDriver -Path $mountPath -Driver $_ -Recurse -ForceUnsigned
        }
    }
}
