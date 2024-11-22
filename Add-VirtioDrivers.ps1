#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$VirtioIsoPath,
    
    [Parameter(Mandatory=$true)]
    [string]$ImagePath,

    [Parameter(Mandatory=$true)]
    [ValidateSet('Server2025Datacenter',
                 'Server2025Standard',
                 'Server2022Datacenter',
                 'Server2022Standard',
                 'Server2019Datacenter',
                 'Server2019Standard',
                 'Server2016Datacenter',
                 'Server2016Standard',
                 'Windows11Enterprise',
                 'Windows11Professional',
                 'Windows10Enterprise',
                 'Windows10Professional',
                 'Windows81Professional')]
    [string]$Version,

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
    $virtioDrivers = Get-VirtioDrivers -VirtioDriveLetter $virtioDriveLetter -Version $Version

    With-WindowsImage -ImagePath $ImagePath -ImageIndex $ImageIndex -VirtioDriveLetter $VirtioDriveLetter {
        Param($mountPath)

        $virtioDrivers | ForEach-Object {
            Add-WindowsDriver -Path $mountPath -Driver $_ -Recurse -ForceUnsigned > $null
        }
    }
}
