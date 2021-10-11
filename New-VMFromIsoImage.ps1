#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$IsoPath,
    
    [Parameter(Mandatory=$true)]
    [string]$VMName,

    [uint64]$VHDXSizeBytes = 120GB,

    [int64]$MemoryStartupBytes = 1GB,

    [switch]$EnableDynamicMemory,

    [int64]$ProcessorCount = 2,

    [string]$SwitchName = 'SWITCH',

    [string]$MacAddress,

    [string]$InterfaceName = 'eth0',

    [string]$VlanId,

    [string]$SecondarySwitchName,

    [string]$SecondaryMacAddress,

    [string]$SecondaryInterfaceName,

    [string]$SecondaryVlanId,

    [switch]$EnableSecureBoot
)

$ErrorActionPreference = 'Stop'

function Normalize-MacAddress ([string]$value) {
    $value.`
        Replace('-', '').`
        Replace(':', '').`
        Insert(2,':').Insert(5,':').Insert(8,':').Insert(11,':').Insert(14,':').`
        ToLowerInvariant()
}

# Get default VHD path (requires administrative privileges)
$vmms = gwmi -namespace root\virtualization\v2 Msvm_VirtualSystemManagementService
$vmmsSettings = gwmi -namespace root\virtualization\v2 Msvm_VirtualSystemManagementServiceSettingData
$vhdxPath = Join-Path $vmmsSettings.DefaultVirtualHardDiskPath "$VMName.vhdx"
$metadataIso = Join-Path $vmmsSettings.DefaultVirtualHardDiskPath "$VMName-metadata.iso"

# Create VM
Write-Verbose 'Creating VM...'
$vm = New-VM -Name $VMName -Generation 2 -MemoryStartupBytes $MemoryStartupBytes -NewVHDPath $vhdxPath -NewVHDSizeBytes $VHDXSizeBytes -SwitchName $SwitchName
$vm | Set-VMProcessor -Count $ProcessorCount
$vm | Get-VMIntegrationService -Name "Guest Service Interface" | Enable-VMIntegrationService
$vm | Set-VMMemory -DynamicMemoryEnabled:$EnableDynamicMemory.IsPresent

# Adds DVD with image
$dvd = $vm | Add-VMDvdDrive -Path $IsoPath -Passthru
$vm | Set-VMFirmware -FirstBootDevice $dvd

if ($EnableSecureBoot.IsPresent) {
    # Sets Secure Boot Template.
    #   Set-VMFirmware -SecureBootTemplate 'MicrosoftUEFICertificateAuthority' doesn't work anymore (!?).
    $vm | Set-VMFirmware -SecureBootTemplateId ([guid]'272e7447-90a4-4563-a4b9-8e4ab00526ce')
} else 
{
    # Disables Secure Boot.
    $vm | Set-VMFirmware -EnableSecureBoot:Off
}

# Setup first network adapter
if ($MacAddress) {
    $MacAddress = Normalize-MacAddress $MacAddress
    $vm | Set-VMNetworkAdapter -StaticMacAddress $MacAddress.Replace(':', '')
}
$eth0 = Get-VMNetworkAdapter -VMName $VMName 
$eth0 | Rename-VMNetworkAdapter -NewName $InterfaceName
if ($VlanId) {
    $eth0 | Set-VMNetworkAdapterVlan -Access -VlanId $VlanId
}    
if ($SecondarySwitchName) {
    # Add secondary network adapter
    $eth1 = Add-VMNetworkAdapter -VMName $VMName -Name $SecondaryInterfaceName -SwitchName $SecondarySwitchName -PassThru

    if ($SecondaryMacAddress) {
        $SecondaryMacAddress = Normalize-MacAddress $SecondaryMacAddress
        $eth1 | Set-VMNetworkAdapter -StaticMacAddress $SecondaryMacAddress.Replace(':', '')
        if ($SecondaryVlanId) {
            $eth1 | Set-VMNetworkAdapterVlan -Access -VlanId $SecondaryVlanId
        }    

    }
}

# Disable Automatic Checkpoints. Check if command is available since it doesn't exist in Server 2016.
$command = Get-Command Set-VM
if ($command.Parameters.AutomaticCheckpointsEnabled) {
    $vm | Set-VM -AutomaticCheckpointsEnabled $false
}

# Wait for VM
$vm | Start-VM
Write-Verbose 'Waiting for VM integration services (1)...'
Wait-VM -Name $VMName -For Heartbeat

Write-Verbose 'All done!'
Write-Verbose 'After finished, please remember to remove the installation media with:'
Write-Verbose "    Get-VMDvdDrive -VMName '$VMName' | Remove-VMDvdDrive"

# Return the VM created.
$vm
