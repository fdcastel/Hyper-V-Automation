#Requires -RunAsAdministrator
#Requires -PSEdition Desktop

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SourcePath,
    
    [Parameter(Mandatory=$true)]
    [string]$Edition,

    [string]$ComputerName,

    [string]$VHDXPath,

    [uint64]$VHDXSizeBytes,

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
    # Resolve path that might not exist -- https://stackoverflow.com/a/3040982
    $VHDXPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(".\$($ComputerName).vhdx")
}

if (-not $VHDXSizeBytes) {
    $VHDXSizeBytes = 120GB
}

if (-not $AdministratorPassword) {
    # Random password
    $AdministratorPassword = -join (
        (65..90) + (97..122) + (48..57) |
            Get-Random -Count 16 |
                ForEach-Object {[char]$_}
    )
}

# Create unattend.xml
$unattendPath = .\New-WindowsUnattendFile.ps1 -AdministratorPassword $AdministratorPassword -Version $Version -ComputerName $ComputerName -Locale $Locale -AddVirtioDrivers:(!!$AddVirtioDrivers)

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

$driversFolder = Join-Path $mergeFolder '\Windows\drivers'
New-Item -ItemType Directory -Path $driversFolder -Force > $null

if ($AddVirtioDrivers) {
    . .\tools\Virtio-Functions.ps1

    With-IsoImage -IsoFileName $AddVirtioDrivers {
        Param($virtioDriveLetter)

        # Throws if the ISO does not contain Virtio drivers.
        $virtioDrivers = Get-VirtioDrivers -VirtioDriveLetter $virtioDriveLetter -Version $Version

        # Adds QEMU Guest Agent installer (will be installed by unattend.xml)
        $msiFile = Get-Item "$($virtioDriveLetter):\guest-agent\qemu-ga-x86_64.msi"
        Copy-Item $msiFile -Destination $driversFolder -Force

        Convert-WindowsImage @cwiArguments -Driver $virtioDrivers
    }
} else {
    Convert-WindowsImage @cwiArguments
}

$VHDXPath
