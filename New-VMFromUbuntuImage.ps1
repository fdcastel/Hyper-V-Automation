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

    [string]$VMMacAddress,

    [string]$NetworkConfig,

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
 - 'mv /etc/netplan/50-cloud-init.yaml /etc/netplan/80-static.yaml'
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

    if ($InstallDocker) {
        $sectionRunCmd += @'

 - 'apt install docker.io docker-compose -y'
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
        $ErrorActionPreference = 'Stop'
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
$ErrorActionPreference = 'Stop'
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

# Adds DVD with metadata.iso
$dvd = $vm | Add-VMDvdDrive -Path $metadataIso -Passthru
$vm | Start-VM

# Wait for VM
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
