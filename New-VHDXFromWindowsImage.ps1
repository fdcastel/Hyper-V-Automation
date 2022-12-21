#Requires -RunAsAdministrator

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
    [ValidateSet('Server2022Datacenter',
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
Convert-WindowsImage -SourcePath $SourcePath -Edition $Edition -VHDPath $vhdxPath -SizeBytes $VHDXSizeBytes -VHDFormat VHDX -DiskLayout UEFI -UnattendPath $unattendPath

if ($AddVirtioDrivers) {
    .\Add-VirtioDrivers.ps1 -VirtioIsoPath $AddVirtioDrivers -ImagePath $VHDXPath
}

$VHDXPath
