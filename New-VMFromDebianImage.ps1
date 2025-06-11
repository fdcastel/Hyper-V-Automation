#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SourcePath,

    [ValidateScript({
        $existingVm = Get-VM -Name $_ -ErrorAction SilentlyContinue
        if (-not $existingVm) {
            return $True
        }
        throw "There is already a VM named '$VMName' in this server."
        
    })]
    [Parameter(Mandatory=$true)]
    [string]$VMName,

    [string]$FQDN = $VMName,

    [Parameter(Mandatory=$true, ParameterSetName='RootPassword')]
    [string]$RootPassword,

    [Parameter(Mandatory=$true, ParameterSetName='RootPublicKey')]
    [string]$RootPublicKey,

    [uint64]$VHDXSizeBytes,

    [int64]$MemoryStartupBytes = 1GB,

    [switch]$EnableDynamicMemory,

    [int64]$ProcessorCount = 2,

    [string]$SwitchName = 'SWITCH',

    [ValidateScript({
        if ($_ -match '^([0-9A-Fa-f]{2}:){5}([0-9A-Fa-f]{2})$') {
            return $True
        }
        throw "-MacAddress must be in format 'xx:xx:xx:xx:xx:xx'."
    })]
    [string]$MacAddress,

    [ValidateScript({
        $sIp, $suffix = $_.Split('/')
        if ($ip = $sIp -as [ipaddress]) {
            $maxSuffix = if ($ip.AddressFamily -eq 'InterNetworkV6') { 128 } else { 32 }
            if ($suffix -in 1..$maxSuffix) {
                return $True
            }
            throw "Invalid -IPAddress suffix ($suffix)."
        }
        throw "Invalid -IPAddress ($sIp)."
    })]
    [string]$IPAddress,

    [string]$Gateway,

    [string[]]$DnsAddresses = @('1.1.1.1','1.0.0.1'),

    [string]$InterfaceName = 'eth0',

    [string]$VlanId,

    [Parameter(Mandatory=$false, ParameterSetName='RootPassword')]
    [Parameter(Mandatory=$false, ParameterSetName='RootPublicKey')]
    [string]$SecondarySwitchName,

    [ValidateScript({
        if ($_ -match '^([0-9A-Fa-f]{2}:){5}([0-9A-Fa-f]{2})$') {
            return $True
        }
        throw "-SecondaryMacAddress must be in format 'xx:xx:xx:xx:xx:xx'."
    })]
    [string]$SecondaryMacAddress,

    [ValidateScript({
        $sIp, $suffix = $_.Split('/')
        if ($ip = $sIp -as [ipaddress]) {
            $maxSuffix = if ($ip.AddressFamily -eq 'InterNetworkV6') { 128 } else { 32 }
            if ($suffix -in 1..$maxSuffix) {
                return $True
            }
            throw "Invalid -SecondaryIPAddress suffix ($suffix)."
        }
        throw "Invalid -SecondaryIPAddress ($sIp)."
    })]
    [string]$SecondaryIPAddress,

    [string]$SecondaryInterfaceName,

    [string]$SecondaryVlanId,

    [switch]$InstallDocker
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
$vmmsSettings = Get-WmiObject -namespace root\virtualization\v2 Msvm_VirtualSystemManagementServiceSettingData
$vhdxPath = Join-Path $vmmsSettings.DefaultVirtualHardDiskPath "$VMName.vhdx"

# Convert cloud image to VHDX
Write-Verbose 'Creating VHDX from cloud image...'
& qemu-img.exe convert -f qcow2 $SourcePath -O vhdx -o subformat=dynamic $vhdxPath 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "qemu-img returned $LASTEXITCODE. Aborting."
}

# Latest versions of qemu-img create VHDX files with the sparse flag set (even with -S 0).
#   This causes issues with Hyper-V, so we need to clear it.
& fsutil.exe sparse setflag $vhdxPath 0 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "fsutil returned $LASTEXITCODE. Aborting."
}

if ($VHDXSizeBytes) {
    Resize-VHD -Path $vhdxPath -SizeBytes $VHDXSizeBytes
}

# Create VM
Write-Verbose 'Creating VM...'
$vm = New-VM -Name $VMName -Generation 2 -MemoryStartupBytes $MemoryStartupBytes -VHDPath $vhdxPath -SwitchName $SwitchName
$vm | Set-VMProcessor -Count $ProcessorCount
$vm | Get-VMIntegrationService -Name "Guest Service Interface" | Enable-VMIntegrationService
$vm | Set-VMMemory -DynamicMemoryEnabled:$EnableDynamicMemory.IsPresent

# Sets Secure Boot Template. 
#   Set-VMFirmware -SecureBootTemplate 'MicrosoftUEFICertificateAuthority' doesn't work anymore (!?).
$vm | Set-VMFirmware -SecureBootTemplateId ([guid]'272e7447-90a4-4563-a4b9-8e4ab00526ce')

# Cloud-init startup hangs without a serial port -- https://bit.ly/2AhsihL
$vm | Set-VMComPort -Number 2 -Path "\\.\pipe\dbg1"

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

# Start VM just to create MAC Addresses
$vm | Start-VM
Start-Sleep -Seconds 1
$vm | Stop-VM -Force

# Wait for Mac Addresses
Write-Verbose "Waiting for MAC addresses..."
do {
    $eth0 = Get-VMNetworkAdapter -VMName $VMName -Name $InterfaceName
    $MacAddress = Normalize-MacAddress $eth0.MacAddress
    Start-Sleep -Seconds 1
} while ($MacAddress -eq '00:00:00:00:00:00')

if ($SecondarySwitchName) {
    do {
        $eth1 = Get-VMNetworkAdapter -VMName $VMName -Name $SecondaryInterfaceName
        $SecondaryMacAddress = Normalize-MacAddress $eth1.MacAddress
        Start-Sleep -Seconds 1
    } while ($SecondaryMacAddress -eq '00:00:00:00:00:00')
}

# Create metadata ISO image
#   Creates a NoCloud data source for cloud-init.
#   More info: https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html
$instanceId = [Guid]::NewGuid().ToString()
 
$metadata = @"
instance-id: $instanceId
local-hostname: $VMName
"@

$displayInterface = "     $($InterfaceName): \4{$InterfaceName}    \6{$InterfaceName}"
$displaySecondaryInterface = ''
if ($SecondarySwitchName) {
    $displaySecondaryInterface = "     $($SecondaryInterfaceName): \4{$SecondaryInterfaceName}    \6{$SecondaryInterfaceName}`n"
}

$sectionWriteFiles = @"
write_files:
 - content: |
     \S{PRETTY_NAME}    \n    \l

$displayInterface
$displaySecondaryInterface
   path: /etc/issue
   owner: root:root
   permissions: '0644'

"@

$sectionRunCmd = @'
runcmd:
 - 'apt-get update'
 - 'grep -o "^[^#]*" /etc/netplan/50-cloud-init.yaml > /etc/netplan/80-static.yaml'        # https://unix.stackexchange.com/a/157607
 - 'rm /etc/netplan/50-cloud-init.yaml'
 - 'touch /etc/cloud/cloud-init.disabled'
 - 'update-grub'     # fix "error: no such device: root." -- https://bit.ly/2TBEdjl
'@

if ($RootPassword) {
    $sectionPasswd = @"
password: $RootPassword
chpasswd: { expire: False }
ssh_pwauth: True
"@
} elseif ($RootPublicKey) {
    $sectionPasswd = @"
ssh_authorized_keys:
  - $RootPublicKey
"@
}

if ($InstallDocker) {
    $sectionRunCmd += @'

 - 'apt update -y'
 - 'apt install -y ca-certificates curl gnupg lsb-release'
 - 'mkdir -p /etc/apt/keyrings'
 - 'curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg'
 - 'echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null'
 - 'apt update -y'
 - 'apt install -y docker-ce docker-ce-cli containerd.io docker-compose'
'@
}

$userdata = @"
#cloud-config
hostname: $FQDN
fqdn: $FQDN

disable_root: false
$sectionPasswd
$sectionWriteFiles
$sectionRunCmd

power_state:
  mode: reboot
  timeout: 300
"@

# Uses netplan to setup network.
if ($IPAddress) {
    $NetworkConfig = @"
version: 2
ethernets:
  $($InterfaceName):
    match:
      macaddress: $MacAddress
    set-name: $($InterfaceName)
    addresses: [$IPAddress]
    nameservers:
      addresses: [$($DnsAddresses -join ', ')]
    routes:
      - to: 0.0.0.0/0
        via: $Gateway
        on-link: true

"@
} else {
    $NetworkConfig = @"
version: 2
ethernets:
  $($InterfaceName):
    match:
      macaddress: $MacAddress
    set-name: $($InterfaceName)
    dhcp4: true
    dhcp-identifier: mac

"@
}

if ($SecondarySwitchName) {
    if ($SecondaryIPAddress) {
        $NetworkConfig += @"
  $($SecondaryInterfaceName):
    match:
      macaddress: $SecondaryMacAddress
    set-name: $($SecondaryInterfaceName)
    addresses: [$SecondaryIPAddress]

"@
    } else {
        $NetworkConfig += @"
  $($SecondaryInterfaceName):
    match:
      macaddress: $SecondaryMacAddress
    set-name: $($SecondaryInterfaceName)
    dhcp4: true
    dhcp-identifier: mac

"@
    }
}

# Adds DVD with metadata.iso
. .\tools\Metadata-Functions.ps1
$metadataIso = New-MetadataIso -VMName $VMName $metadata -UserData $userdata -NetworkConfig $NetworkConfig
$dvd = $vm | Add-VMDvdDrive -Path $metadataIso -Passthru

# Disable Automatic Checkpoints. Check if command is available since it doesn't exist in Server 2016.
$command = Get-Command Set-VM
if ($command.Parameters.AutomaticCheckpointsEnabled) {
    $vm | Set-VM -AutomaticCheckpointsEnabled $false
}

# Wait for VM
$vm | Start-VM
Write-Verbose 'Waiting for VM integration services (1)...'
Wait-VM -Name $VMName -For Heartbeat

# Cloud-init will reboot after initial machine setup. Wait for it...
Write-Verbose 'Waiting for VM initial setup...'
try {
    Wait-VM -Name $VMName -For Reboot
} catch {
    # Win 2016 RTM doesn't have "Reboot" in WaitForVMTypes type. 
    #   Wait until heartbeat service stops responding.
    $heartbeatService = ($vm | Get-VMIntegrationService -Name 'Heartbeat')
    while ($heartbeatService.PrimaryStatusDescription -eq 'OK') { Start-Sleep  1 }
}

Write-Verbose 'Waiting for VM integration services (2)...'
Wait-VM -Name $VMName -For Heartbeat

# Removes DVD and metadata.iso
$dvd | Remove-VMDvdDrive
$metadataIso | Remove-Item -Force

# Return the VM created.
Write-Verbose 'All done!'
$vm
