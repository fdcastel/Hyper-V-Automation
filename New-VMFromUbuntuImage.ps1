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

    [int64]$VMProcessorCount = 2,

    [string]$VMSwitchName = 'SWITCH',

    [string]$VMSecondarySwitchName,

    [string]$VMMacAddress,

    [string]$NetworkConfig,

    [switch]$EnableRouting,

    [switch]$InstallDocker
)

$ErrorActionPreference = 'Stop'

function New-MetadataIso($IsoFile) {
    # Creates a NoCloud data source for cloud-init.
    #   More info: http://cloudinit.readthedocs.io/en/latest/topics/datasources/nocloud.html

    $instanceId = [Guid]::NewGuid().ToString()
 
    $metadata = @"
instance-id: $instanceId
local-hostname: $VMName
"@

    $sectionRunCmd = @'
runcmd:
 - 'apt-get update'
 - 'echo "eth0: \134\64{eth0}" >> /etc/issue'
 - 'mv /etc/network/interfaces.d/50-cloud-init.cfg /etc/network/interfaces.d/80-static.cfg'
 - 'touch /etc/cloud/cloud-init.disabled'
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

 - 'iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE'
 - 'iptables -A FORWARD -i eth0 -o eth1 -m state --state RELATED,ESTABLISHED -j ACCEPT'
 - 'iptables -A FORWARD -i eth1 -o eth0 -j ACCEPT'
 - 'iptables-save > /etc/iptables.rules'
"@
    }

    if ($InstallDocker) {
        $sectionRunCmd += @'

 - 'apt install docker.io -y'
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
# Sets Secure Boot Template. 
#   Set-VMFirmware -SecureBootTemplate 'MicrosoftUEFICertificateAuthority' doesn't work anymore (!?).
$vm | Set-VMFirmware -SecureBootTemplateId ([guid]'272e7447-90a4-4563-a4b9-8e4ab00526ce')


# Ubuntu 16.04/18.04 startup hangs without a serial port (!?)
$vm | Set-VMComPort -Number 1 -Path "\\.\pipe\$VMName-COM1"

# Sets VM Mac Address
if ($VMMacAddress) {
    $vm | Set-VMNetworkAdapter -StaticMacAddress ($VMMacAddress -replace ':','')
}

# Adds secondary network adapter
if ($VMSecondarySwitchName) {
    $vm | Add-VMNetworkAdapter -SwitchName $VMSecondarySwitchName
}

# Adds DVD with metadata.iso
$dvd = $vm | Add-VMDvdDrive -Path $metadataIso -Passthru
$vm | Start-VM

# Wait for VM
Write-Verbose 'Waiting for VM integration services (1)...'
Wait-VM -Name $VMName -For Heartbeat

# Wait for installation complete
Write-Verbose 'Waiting for VM initial setup...'
Wait-VM -Name $VMName -For Reboot

Write-Verbose 'Waiting for VM integration services (2)...'
Wait-VM -Name $VMName -For Heartbeat

# Removes DVD and metadata.iso
$dvd | Remove-VMDvdDrive
$metadataIso | Remove-Item -Force

# Return the VM created.
Write-Verbose 'All done!'
$vm
