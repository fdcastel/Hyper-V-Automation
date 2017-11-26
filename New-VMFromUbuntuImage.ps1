#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SourcePath,
    
    [Parameter(Mandatory=$true)]
    [string]$VMName,

    [string]$FQDN = $VMName,

    [Parameter(Mandatory=$true, ParameterSetName='Root')]
    [string]$RootPassword,

    [Parameter(Mandatory=$true, ParameterSetName='User')]
    [string]$UserName,

    [Parameter(Mandatory=$true, ParameterSetName='User')]
    [string]$UserPublicKey,

    [uint64]$VHDXSizeBytes,

    [int64]$MemoryStartupBytes = 1GB,

    [switch]$EnableDynamicMemory,

    [int64]$VMProcessorCount = 2,

    [string]$VMSwitchName = 'SWITCH',

    [string]$VMSecondarySwitchName,

    [string]$NetworkConfig,

    [switch]$EnableRouting
)

$ErrorActionPreference = 'Stop'

function New-MetadataIso($IsoFile) {
    $instanceId = [Guid]::NewGuid().ToString()
 
    $metadata = @"
instance-id: $instanceId
local-hostname: $VMName
"@

    $sectionRunCmd = @"
runcmd:
 - [ hostname, $FQDN ]
"@

    if ($RootPassword) {
        $sectionPasswd = @"
password: $RootPassword
chpasswd: { expire: False }
ssh_pwauth: True
"@
    }

    if ($UserName) {
        if ($UserPublicKey) {
            $sectionSshAuthorizedKeys = @"
    ssh-authorized-keys:
      - $UserPublicKey
"@
        }
    
        $sectionUsers = @"
users:
 - name: $UserName
   gecos: $UserName
   sudo: ['ALL=(ALL) NOPASSWD:ALL']
   groups: users, admin
   lock_passwd: true
$sectionSshAuthorizedKeys
"@
    }

    if ($EnableRouting) {
        # https://help.ubuntu.com/community/IptablesHowTo#Configuration_on_startup
        $sectionWriteFiles = @"
write_files:
 - content: |
      # Turn on IP forwarding
      net.ipv4.ip_forward=1
   owner: root:root
   permissions: '0644'
   path: /etc/sysctl.d/50-enable-routing.conf

 - content: |
      #!/bin/sh
      # Reload iptables
      iptables-restore < /etc/iptables.rules
      exit 0
   owner: root:root
   permissions: '0755'
   path: /etc/network/if-pre-up.d/iptables-load

 - content: |
      #!/bin/sh
      iptables-save -c > /etc/iptables.rules
      if [ -f /etc/iptables.downrules ]; then
         iptables-restore < /etc/iptables.downrules
      fi
      exit 0
   owner: root:root
   permissions: '0755'
   path: /etc/network/if-post-down.d/iptables-save
"@

        # https://askubuntu.com/a/885967
        $sectionRunCmd += @"

 - [ iptables, -t, nat, -A, POSTROUTING, -o, eth0, -j, MASQUERADE ]
 - [ iptables, -A, FORWARD, -i, eth0, -o, eth1, -m, state, --state, "RELATED,ESTABLISHED", -j, ACCEPT ]
 - [ iptables, -A, FORWARD, -i, eth1, -o, eth0, -j, ACCEPT, ]
 - [ sh, -c, "iptables-save > /etc/iptables.rules" ]
"@

        $sectionReboot = @"
power_state:
 mode: reboot
"@
    }

    $userdata = @"
#cloud-config
$sectionPasswd
$sectionUsers
$sectionWriteFiles
$sectionRunCmd
$sectionReboot
"@

    if (-not $NetworkConfig) {
        $NetworkConfig = & .\New-NetworkConfig.ps1 -Dhcp
    }

    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) $instanceId
    mkdir $tempPath
    try {
        $metadata | Out-File "$tempPath\meta-data" -Encoding ascii
        $userdata | Out-File "$tempPath\user-data" -Encoding ascii
        $networkConfig | Out-File "$tempPath\network-config" -Encoding ascii

        $oscdimgPath = Join-Path $PSScriptRoot '.\tools\oscdimg.exe'
        echo $oscdimgPath
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
    }
}

# Get default VHD path (requires administrative privileges)
$vmms = gwmi -namespace root\virtualization\v2 Msvm_VirtualSystemManagementService
$vmmsSettings = gwmi -namespace root\virtualization\v2 Msvm_VirtualSystemManagementServiceSettingData
$vhdxPath = Join-Path $vmmsSettings.DefaultVirtualHardDiskPath "$VMName.vhdx"
$metadataIso = Join-Path $vmmsSettings.DefaultVirtualHardDiskPath "$VMName-metadata.iso"

# Create metadata ISO image
Write-Verbose 'Creating metadata ISO image...'
New-MetadataIso -IsoFile $metadataIso

# Convert cloud image to VHDX
Write-Verbose 'Creating VHDX from cloud image...'
    $ErrorActionPreference = 'Continue'
& {
    & qemu-img.exe convert -f qcow2 $SourcePath -O vhdx -o subformat=dynamic $vhdxPath
}
if ($VHDXSizeBytes) {
    Resize-VHD -Path $vhdxPath -SizeBytes $VHDXSizeBytes
}

# Create VM
Write-Verbose 'Creating VM...'
$vm = New-VM -Name $VMName -Generation 2 -MemoryStartupBytes $MemoryStartupBytes -VHDPath $vhdxPath -SwitchName $VMSwitchName
$vm | Set-VMProcessor -Count $VMProcessorCount
$vm | Get-VMIntegrationService -Name "Guest Service Interface" | Enable-VMIntegrationService
if ($EnableDynamicMemory) {
    $vm | Set-VMMemory -DynamicMemoryEnabled $true 
}
$vm | Set-VMFirmware -SecureBootTemplate 'MicrosoftUEFICertificateAuthority'

# Ubuntu 16.04 startup hangs without a serial port (!?)
$vm | Set-VMComPort -Number 1 -Path "\\.\pipe\$VMName-COM1"

# Adds secondary network adapter
if ($VMSecondarySwitchName) {
    $vm | Add-VMNetworkAdapter -SwitchName $VMSecondarySwitchName
}

$dvd = $vm | Add-VMDvdDrive -Path $metadataIso -Passthru
$vm | Start-VM

# Wait for VM
Write-Verbose 'Waiting for VM integration services...'
Wait-VM -Name $VMName -For Heartbeat

# Wait for installation complete
Write-Verbose 'Waiting for VM initial setup...'
Start-Sleep -Seconds 20

# Return the VM created.
Write-Verbose 'All done!'
$vm
