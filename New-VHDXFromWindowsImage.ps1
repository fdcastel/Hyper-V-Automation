#Requires -RunAsAdministrator
#Requires -PSEdition Desktop

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SourcePath,
    
    [Parameter(Mandatory=$true)]
    [string]$Edition,

    [Parameter(Mandatory=$true)]
    [string]$ComputerName,

    [string]$VHDXPath,

    [Parameter(Mandatory=$true)]
    [uint64]$VHDXSizeBytes,

    [Parameter(Mandatory=$true)]
    [string]$AdministratorPassword,

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

    [string]$Locale = 'en-US',

    [string]$AddVirtioDrivers
)

$ErrorActionPreference = 'Stop'

if (-not $VHDXPath)
{
    # https://stackoverflow.com/a/3040982
    $VHDXPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(".\$($ComputerName).vhdx")
}

# Create unattend.xml
$unattendPath = .\New-WindowsUnattendFile.ps1 -AdministratorPassword $AdministratorPassword -Version $Version -ComputerName $ComputerName -Locale $Locale

# Create VHDX from ISO image
Write-Verbose 'Creating VHDX from image...'
. .\tools\Convert-WindowsImage.ps1

# Create temporary folder to store files to be merged into the VHDX.
$mergeFolder = Join-Path $env:TEMP 'New-VHDXFromWindowsImage-root'
if (Test-Path $mergeFolder) {
    Remove-Item -Recurse -Force $mergeFolder
}
New-Item -ItemType Directory -Path $mergeFolder -Force > $null

$cwiArguments = @{
    SourcePath = $SourcePath
    Edition = $Edition
    VHDPath = $vhdxPath
    SizeBytes = $VHDXSizeBytes
    VHDFormat = 'VHDX'
    DiskLayout = 'UEFI'
    UnattendPath = $unattendPath
    MergeFolder = $mergeFolder
}

# Removes unattend.xml files after the setup is complete.
#   https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/add-a-custom-script-to-windows-setup#run-a-script-after-setup-is-complete-setupcompletecmd
$scriptsFolder = Join-Path $mergeFolder '\Windows\Setup\Scripts'
New-Item -ItemType Directory -Path $scriptsFolder -Force > $null
@'
DEL /Q /F C:\Windows\Panther\unattend.xml
DEL /Q /F C:\unattend.xml
'@ | Out-File "$scriptsFolder\SetupComplete.cmd" -Encoding ascii

if ($AddVirtioDrivers) {
    . .\tools\Virtio-Functions.ps1

    With-IsoImage -IsoFileName $AddVirtioDrivers {
        Param($virtioDriveLetter)

        # Throws if the ISO does not contain Virtio drivers.
        $virtioDrivers = Get-VirtioDrivers -VirtioDriveLetter $virtioDriveLetter -Version $Version

        # Adds QEMU Guest Agent installer
        $driversFolder = Join-Path $mergeFolder '\Windows\drivers'
        New-Item -ItemType Directory -Path $driversFolder -Force > $null
        Copy-Item "$($virtioDriveLetter):\guest-agent\qemu-ga-x86_64.msi" -Destination $driversFolder -Force

        # Run the installer when setup is complete.
        'C:\Windows\drivers\qemu-ga-x86_64.msi /quiet' | Out-File "$scriptsFolder\SetupComplete.cmd" -Append -Encoding ascii
   
        Convert-WindowsImage @cwiArguments -Driver $virtioDrivers
    }
} else {
    Convert-WindowsImage @cwiArguments
}

$VHDXPath
