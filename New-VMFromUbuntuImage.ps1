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

    [int64]$VMProcessorCount = 2,

    [string]$VMSwitchName = 'SWITCH',

    [string]$NetworkConfig
)

$ErrorActionPreference = 'Stop'

function New-MetadataIso($IsoFile) {
    $instanceId = [Guid]::NewGuid().ToString()
 
    $metadata = @"
instance-id: $instanceId
local-hostname: $VMName
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

    $userdata = @"
#cloud-config
$sectionPasswd
$sectionUsers
runcmd:
 - [ hostname, $FQDN ]
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
        & {            $ErrorActionPreference = 'Continue'
            & $oscdimgPath $tempPath $metadataIso -j2 -lcidata
            if ($LASTEXITCODE -gt 0) {
                throw "oscdimg.exe returned $LASTEXITCODE."
            }
        }    }
    finally {
        rmdir -Path $tempPath –Recurse -Force
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
$vm | Set-VMFirmware -SecureBootTemplate 'MicrosoftUEFICertificateAuthority'

# Ubuntu 16.04 startup hangs without a serial port (!?)
$vm | Set-VMComPort -Number 1 -Path "\\.\pipe\$VMName-COM1"

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
