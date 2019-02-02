#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SourcePath,
    
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

    [string]$MacAddress,

    [string]$IPAddress,

    [string]$Gateway,

    [string[]]$DnsAddresses = @('1.1.1.1','1.0.0.1'),

    [string]$InterfaceName = 'eth0',

    [Parameter(Mandatory=$false, ParameterSetName='RootPassword')]
    [Parameter(Mandatory=$false, ParameterSetName='RootPublicKey')]
    [Parameter(Mandatory=$true, ParameterSetName='EnableRouting')]
    [switch]$EnableRouting,

    [Parameter(Mandatory=$false, ParameterSetName='RootPassword')]
    [Parameter(Mandatory=$false, ParameterSetName='RootPublicKey')]
    [Parameter(Mandatory=$true, ParameterSetName='EnableRouting')]
    [string]$SecondarySwitchName,

    [string]$SecondaryMacAddress,

    [string]$SecondaryIPAddress,

    [string]$SecondaryInterfaceName,

    [string]$LoopbackIPAddress,

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
$vmms = gwmi -namespace root\virtualization\v2 Msvm_VirtualSystemManagementService
$vmmsSettings = gwmi -namespace root\virtualization\v2 Msvm_VirtualSystemManagementServiceSettingData
$vhdxPath = Join-Path $vmmsSettings.DefaultVirtualHardDiskPath "$VMName.vhdx"
$metadataIso = Join-Path $vmmsSettings.DefaultVirtualHardDiskPath "$VMName-metadata.iso"

# Convert cloud image to VHDX
Write-Verbose 'Creating VHDX from cloud image...'
$ErrorActionPreference = 'Continue'
& {
    & qemu-img.exe convert -f qcow2 $SourcePath -O vhdx -o subformat=dynamic $vhdxPath
    if ($LASTEXITCODE -ne 0) {
        throw "qemu-img returned $LASTEXITCODE. Aborting."
    }
}
$ErrorActionPreference = 'Stop'
if ($VHDXSizeBytes) {
    Resize-VHD -Path $vhdxPath -SizeBytes $VHDXSizeBytes
}

# Create VM
Write-Verbose 'Creating VM...'
$vm = New-VM -Name $VMName -Generation 2 -MemoryStartupBytes $MemoryStartupBytes -VHDPath $vhdxPath -SwitchName $SwitchName
$vm | Set-VMProcessor -Count $ProcessorCount
$vm | Get-VMIntegrationService -Name "Guest Service Interface" | Enable-VMIntegrationService
if ($EnableDynamicMemory) {
    $vm | Set-VMMemory -DynamicMemoryEnabled $true 
}
# Sets Secure Boot Template. 
#   Set-VMFirmware -SecureBootTemplate 'MicrosoftUEFICertificateAuthority' doesn't work anymore (!?).
$vm | Set-VMFirmware -SecureBootTemplateId ([guid]'272e7447-90a4-4563-a4b9-8e4ab00526ce')

# Ubuntu 16.04/18.04 startup hangs without a serial port (!?) -- https://bit.ly/2AhsihL
$vm | Set-VMComPort -Number 2 -Path "\\.\pipe\dbg1"

# Setup first network adapter
if ($MacAddress) {
    $MacAddress = Normalize-MacAddress $MacAddress
    $vm | Set-VMNetworkAdapter -StaticMacAddress $MacAddress.Replace(':', '')
}
$eth0 = Get-VMNetworkAdapter -VMName $VMName 
$eth0 | Rename-VMNetworkAdapter -NewName $InterfaceName

if ($SecondarySwitchName) {
    # Add secondary network adapter
    $eth1 = Add-VMNetworkAdapter -VMName $VMName -Name $SecondaryInterfaceName -SwitchName $SecondarySwitchName -PassThru

    if ($SecondaryMacAddress) {
        $SecondaryMacAddress = Normalize-MacAddress $SecondaryMacAddress
        $eth1 | Set-VMNetworkAdapter -StaticMacAddress $SecondaryMacAddress.Replace(':', '')
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
#   More info: http://cloudinit.readthedocs.io/en/latest/topics/datasources/nocloud.html
Write-Verbose 'Creating metadata ISO image...'
$instanceId = [Guid]::NewGuid().ToString()
 
$metadata = @"
instance-id: $instanceId
local-hostname: $VMName
"@

$RouterMark = if ($EnableRouting) { '<->' } else { '   ' }
$IpForward = if ($EnableRouting) { 'IPForward=yes' } else { '' }
$IpMasquerade = if ($EnableRouting) { 'IPMasquerade=yes' } else { '' }
if ($SecondarySwitchName) {
    $DisplayInterfaces = "     $($InterfaceName): \4{$InterfaceName}  $RouterMark  $($SecondaryInterfaceName): \4{$SecondaryInterfaceName}"
} else {
    $DisplayInterfaces = "     $($InterfaceName): \4{$InterfaceName}"
}

$sectionWriteFiles = @"
write_files:
 - content: |
     \S{PRETTY_NAME} \n \l

$DisplayInterfaces
     
   path: /etc/issue
   owner: root:root
   permissions: '0644'

 - content: |
     [Match]
     MACAddress=$MacAddress

     [Link]
     Name=$InterfaceName
   path: /etc/systemd/network/20-$InterfaceName.link
   owner: root:root
   permissions: '0644'

 - content: |
     # Please see /etc/systemd/network/ for current configuration.
     # 
     # systemd.network(5) was used directly to configure this system
     # due to limitations of netplan(5).
   path: /etc/netplan/README
   owner: root:root
   permissions: '0644'

"@

if ($IPAddress) {
    # eth0 (Static)

    # Fix for /32 addresses
    if ($IPAddress.EndsWith('/32')) {
        $RouteForSlash32 = @"

     [Route]
     Destination=0.0.0.0/0
     Gateway=$Gateway
     GatewayOnlink=true
"@
    }

    $sectionWriteFiles += @"
 - content: |
     [Match]
     Name=$InterfaceName

     [Network]
     Address=$IPAddress
     Gateway=$Gateway
     DNS=$($DnsAddresses[0])
     DNS=$($DnsAddresses[1])
     $IpForward
     $RouteForSlash32
   path: /etc/systemd/network/20-$InterfaceName.network
   owner: root:root
   permissions: '0644'

"@
} else {
    # eth0 (DHCP)
    $sectionWriteFiles += @"
 - content: |
     [Match]
     Name=$InterfaceName

     [Network]
     DHCP=true
     $IpForward

     [DHCP]
     UseMTU=true
   path: /etc/systemd/network/20-$InterfaceName.network
   owner: root:root
   permissions: '0644'

"@
}

if ($SecondarySwitchName) {
    $sectionWriteFiles += @"
 - content: |
     [Match]
     MACAddress=$SecondaryMacAddress

     [Link]
     Name=$SecondaryInterfaceName
   path: /etc/systemd/network/20-$SecondaryInterfaceName.link
   owner: root:root
   permissions: '0644'

"@

    if ($SecondaryIPAddress) {
        # eth1 (Static)
        $sectionWriteFiles += @"
 - content: |
     [Match]
     Name=$SecondaryInterfaceName

     [Network]
     Address=$SecondaryIPAddress
     $IpForward
     $IpMasquerade
   path: /etc/systemd/network/20-$SecondaryInterfaceName.network
   owner: root:root
   permissions: '0644'

"@
    } else {
        # eth1 (DHCP)
        $sectionWriteFiles += @"
 - content: |
     [Match]
     Name=$SecondaryInterfaceName

     [Network]
     DHCP=true
     $IpForward
     $IpMasquerade

     [DHCP]
     UseMTU=true
   path: /etc/systemd/network/20-$SecondaryInterfaceName.network
   owner: root:root
   permissions: '0644'

"@
    }
}

if ($LoopbackIPAddress) {
    # lo
    $sectionWriteFiles += @"
 - content: |
     [Match]
     Name=lo

     [Network]
     Address=$LoopbackIPAddress
   path: /etc/systemd/network/20-lo.network
   owner: root:root
   permissions: '0644'

"@
}
    
$sectionRunCmd = @'
runcmd:
 - 'apt-get update'
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

 - 'apt install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common'
 - 'curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -'
 - 'add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"'
 - 'apt update -y'
 - 'apt install -y docker-ce docker-ce-cli containerd.io docker-compose'
'@
}

$userdata = @"
#cloud-config
hostname: $FQDN
fqdn: $FQDN

$sectionPasswd
$sectionWriteFiles
$sectionRunCmd

power_state:
  mode: reboot
  timeout: 300
"@

# Uses netplan to setup first network interface on first boot (due to cloud-init).
#   Then erase netplan and uses systemd-network for everything.
if ($IPAddress) {
    # Fix for /32 addresses
    if ($IPAddress.EndsWith('/32')) {
        $RouteForSlash32 = @"

    routes:
      - to: 0.0.0.0/0
        via: $Gateway
        on-link: true
"@
    }

    $NetworkConfig = @"
version: 2
ethernets:
  eth0:
    addresses: [$IPAddress]
    gateway4: $Gateway
    nameservers:
      addresses: [$($DnsAddresses -join ', ')]
    $RouteForSlash32
"@
} else {
    $NetworkConfig = @"
version: 2
ethernets:
  eth0:
    dhcp4: true
"@
}

# Save all files in temp folder and create metadata .iso from it
$tempPath = Join-Path ([System.IO.Path]::GetTempPath()) $instanceId
mkdir $tempPath | Out-Null
try {
    $metadata | Out-File "$tempPath\meta-data" -Encoding ascii
    $userdata | Out-File "$tempPath\user-data" -Encoding ascii
    $NetworkConfig | Out-File "$tempPath\network-config" -Encoding ascii

    $oscdimgPath = Join-Path $PSScriptRoot '.\tools\oscdimg.exe'
    & {
        $ErrorActionPreference = 'Continue'
        & $oscdimgPath $tempPath $metadataIso -j2 -lcidata
        if ($LASTEXITCODE -gt 0) {
            throw "oscdimg.exe returned $LASTEXITCODE."
        }
    }
}
finally {
    rmdir -Path $tempPath -Recurse -Force
    $ErrorActionPreference = 'Stop'
}

# Adds DVD with metadata.iso
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
