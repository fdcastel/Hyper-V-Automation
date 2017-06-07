[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$VMName,
    
    [Parameter(Mandatory=$true)]
    [string]$DestinationHost,

    [Parameter(Mandatory=$true)]
    [string]$CertificateThumbprint
)

$ErrorActionPreference = 'Stop'

if ((Get-VM $VMName).State -eq 'Running') {
    throw "The virtual machine must be stopped to use this command."
}

# Remove current replication (if any)
Remove-VMReplication -VMName $VMName -ErrorAction SilentlyContinue

# Setup temporary replication to destination host
Enable-VMReplication -VMName $VMName -ReplicaServerName $DestinationHost -AuthenticationType Certificate -CertificateThumbprint $CertificateThumbprint -ReplicaServerPort 443 -CompressionEnabled $true

# Move VM files from Replica to Primary location
$sourceVhdx = (Get-VM $VMName -ComputerName $DestinationHost | Get-VMHardDiskDrive).Path
$targetVhdx = (Get-VM $VMName | Get-VMHardDiskDrive).Path
$targetVhdx = Join-Path (Split-Path $targetVhdx -Parent) (Split-Path $sourceVhdx -Leaf)
$vhds = @(@{'SourceFilePath' = $sourceVhdx; 'DestinationFilePath' = $targetVhdx})
Invoke-Command -ComputerName $DestinationHost {
  Move-VMStorage -VMName $using:VMName -VirtualMachinePath 'C:\Hyper-V\Virtual Machines' -SnapshotFilePath 'C:\Hyper-V\Snapshots' -VHDs $using:vhds
}

# Replicate
Start-VMInitialReplication -VMName $VMName -AsJob |
    Receive-Job -Wait

# Start Failover
Start-VMFailover -Prepare -VMName $VMName -Confirm:$false
Start-VMFailover -VMName $VMName -ComputerName $DestinationHost -Confirm:$false

# Promote Replica to Primary
Set-VMReplication -Reverse -VMName $VMName -ComputerName $DestinationHost -CertificateThumbprint $CertificateThumbprint

# Remove temporary replication
Remove-VMReplication -VMName $VMName 
Remove-VMReplication -VMName $VMName -ComputerName $DestinationHost

# Connect VM to switch
Get-VMNetworkAdapter -ComputerName $DestinationHost -VMName $VMName |
    Connect-VMNetworkAdapter -SwitchName 'SWITCH'

# Start VM
$vm = Start-VM -VMName $VMName -ComputerName $DestinationHost -Passthru

# Wait for VM
$heartbeatService = $vm | Get-VMIntegrationService -Name 'Heartbeat'
$vmOnline = $false
do { 
    Start-Sleep -Seconds 1
    $vmOnline = $heartbeatService.PrimaryStatusDescription -eq 'OK'
} until ($vmOnline)

# If VM is responding on new server, remove the source VM (do not erase .VHDXs)
if ($vmOnline) {
    Remove-VM -VMName $VMName -Force
}
