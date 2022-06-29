#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SourcePath,
    
    [Parameter(Mandatory=$true)]
    [string]$Edition,

    [Parameter(Mandatory=$true)]
    [string]$VMName,

    [Parameter(Mandatory=$true)]
    [uint64]$VHDXSizeBytes,

    [Parameter(Mandatory=$true)]
    [string]$AdministratorPassword,

    [Parameter(Mandatory=$true)]
    [ValidateSet('Server2022Datacenter','Server2022Standard','Server2019Datacenter','Server2019Standard','Server2016Datacenter','Server2016Standard','Windows10Enterprise','Windows10Professional','Windows81Professional')]
    [string]$Version,

    [Parameter(Mandatory=$true)]
    [int64]$MemoryStartupBytes,

    [switch]$EnableDynamicMemory,

    [int64]$VMProcessorCount = 2,

    [string]$VMSwitchName = 'SWITCH',

    [string]$VMMacAddress,

    [string]$Locale = 'en-US'
)

$ErrorActionPreference = 'Stop'

# Get default VHD path (requires administrative privileges)
$vmms = gwmi -namespace root\virtualization\v2 Msvm_VirtualSystemManagementService
$vmmsSettings = gwmi -namespace root\virtualization\v2 Msvm_VirtualSystemManagementServiceSettingData
$vhdxPath = Join-Path $vmmsSettings.DefaultVirtualHardDiskPath "$VMName.vhdx"

# Create VHDX from ISO image
.\New-VHDXFromWindowsImage.ps1 -SourcePath $SourcePath -Edition $Edition -ComputerName $VMName -VHDXSizeBytes $VHDXSizeBytes -VHDXPath $vhdxPath -AdministratorPassword $AdministratorPassword -Version $Version -Locale $Locale

# Create VM
Write-Verbose 'Creating VM...'
$vm = New-VM -Name $VMName -Generation 2 -MemoryStartupBytes $MemoryStartupBytes -VHDPath $vhdxPath -SwitchName $VMSwitchName
$vm | Set-VMProcessor -Count $VMProcessorCount
$vm | Get-VMIntegrationService |
    Where-Object { $_ -is [Microsoft.HyperV.PowerShell.GuestServiceInterfaceComponent] } |
        Enable-VMIntegrationService -Passthru
$vm | Set-VMMemory -DynamicMemoryEnabled:$EnableDynamicMemory.IsPresent

if ($VMMacAddress) {
    $vm | Set-VMNetworkAdapter -StaticMacAddress ($VMMacAddress -replace ':','')
}
# Disable Automatic Checkpoints (doesn't exist in Server 2016)
$command = Get-Command Set-VM
if ($command.Parameters.AutomaticCheckpointsEnabled) {
    $vm | Set-VM -AutomaticCheckpointsEnabled $false
}
$vm | Start-VM

# Wait for installation complete
Write-Verbose 'Waiting for VM integration services...'
Wait-VM -Name $vmName -For Heartbeat

# Return the VM created.
Write-Verbose 'All done!'
$vm
