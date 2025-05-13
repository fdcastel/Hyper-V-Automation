#Requires -RunAsAdministrator
# 04/03/2022 Adding Secrity Profile

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SourcePath,
    [Parameter(Mandatory=$true)]
    [string]$VMName,
  	[Parameter(Mandatory=$false)]
	  [string]$DomainName = 'local',
	  [Parameter(Mandatory=$false)]
    [string]$RootUsername='admin',
    [Parameter(Mandatory=$true, ParameterSetName='RootPassword')]
    [string]$RootPassword='P@ssw0rd',
    [uint64]$VHDXSizeBytes = 128GB,
    [int64]$MemoryStartupBytes = 1GB,
    [switch]$EnableDynamicMemory,
    [int64]$ProcessorCount = 2,
    [string]$SwitchName = 'New Virtual Switch',
    [string]$MacAddress,
	  [string]$IPAddress,
    [string]$Gateway,
	  [string]$Subnet,
    [string[]]$DnsAddresses = @('1.1.1.1','1.0.0.1'),
    [string]$InterfaceName = 'eth0',
    [string]$VlanId,
	  [string]$SecondaryIPAddress,
	  [string]$SecondaryGateway,
  	[string]$SecondarySubnet,
    [string]$SecondarySwitchName,
    [string]$SecondaryMacAddress,
    [string]$SecondaryInterfaceName = 'eth1',
    [string]$SecondaryVlanId,
    [string]$ThirdSwitchName,
    [string]$ThirdMacAddress,
    [string]$ThirdInterfaceName = 'eth2',
    [string]$ThirdVlanId,
  	[string]$ThirdIPAddress,
    [string]$ThirdGateway,
	  [string]$ThirdSubnet,
    [switch]$EnableSecureBoot,
		[switch]$EnableProtectionProfile
)

$ErrorActionPreference = 'Stop'

Write-Host "SourcePath: $SourcePath"

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
#$metadataIso = Join-Path $vmmsSettings.DefaultVirtualHardDiskPath "$VMName-metadata.iso"
$configIso = Join-Path $vmmsSettings.DefaultVirtualHardDiskPath "$VMName-config.iso"

# Create VM
Write-Verbose 'Creating VM...'
$vm = New-VM -Name $VMName -Generation 2 -MemoryStartupBytes $MemoryStartupBytes -NewVHDPath $vhdxPath -NewVHDSizeBytes $VHDXSizeBytes -SwitchName $SwitchName
$vm | Set-VMProcessor -Count $ProcessorCount
$vm | Get-VMIntegrationService -Name "Guest Service Interface" | Enable-VMIntegrationService
$vm | Set-VMMemory -DynamicMemoryEnabled:$EnableDynamicMemory.IsPresent
#$vm | Set-VM -AutomaticCheckpointsEnabled $false

# Adds DVD with image
$dvd = $vm | Add-VMDvdDrive -Path $SourcePath -Passthru
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


# ETH0
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
if ($IPAddress) {
	$BootProto="static"
	if ($Subnet) {
		$IPAddress+=" --netmask=$Subnet "
	}
} else {
    $IPAddress = "auto"
  	$BootProto="dhcp"
}

if ($Gateway){
	  Write-Host "eth0: Gateway:" $Gateway
} else {
	  $Gateway="auto"
}
	  Write-Host "eth0: BootProto:" $BootProto
    Write-Host "eth0: IPAddress:" $IPAddress   
	  Write-Host "eth0: Gateway:" $Gateway

# ETH1
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
if ($SecondaryIPAddress) {
	$SecondaryBootProto="static"
	if ($SecondarySubnet) {
		$SecondaryIPAddress+=" --netmask=$SecondarySubnet "
	} else {
		$SecondaryIPAddress = "auto"
		$SecondaryBootProto="dhcp"
	}
	if ($SecondaryGateway){
    # Nothing yet
	} else {
		$SecondaryGateway="auto"
	}
} else {
	$SecondaryIPAddress = "auto"
	$SecondaryBootProto="dhcp"
}
	Write-Host "eth1: BootProto:" $SecondaryBootProto
	Write-Host "eth1: IPAddress:" $SecondaryIPAddress
	Write-Host "eth1: Gateway:" $SecondaryGateway

# ETH2 
if ($ThirdSwitchName) {
    # Add secondary network adapter
    $eth2 = Add-VMNetworkAdapter -VMName $VMName -Name $ThirdInterfaceName -SwitchName $ThirdSwitchName -PassThru

    if ($ThirdMacAddress) {
        $ThirdMacAddress = Normalize-MacAddress $ThirdMacAddress
        $eth2 | Set-VMNetworkAdapter -StaticMacAddress $ThirdMacAddress.Replace(':', '')
        if ($ThirdVlanId) {
            $eth2 | Set-VMNetworkAdapterVlan -Access -VlanId $ThirdVlanId
        } 
	}
}	

if ($ThirdIPAddress) {
	$ThirdBootProto="static"
	if ($ThirdSubnet) {
		$ThirdIPAddress+=" --netmask=$ThirdSubnet "
	} else {
		$ThirdIPAddress = "auto"
		$ThirdBootProto="dhcp"
	}
	if ($ThirdGateway){
    # Nothing yet
	} else {
		$ThirdGateway="auto"
	}
} else {
	$ThirdIPAddress = "auto"
	$ThirdBootProto="dhcp"
}

	Write-Host "eth2: BootProto:" $ThirdBootProto
	Write-Host "eth2: IPAddress:" $ThirdIPAddress
	Write-Host "eth2: Gateway:" $ThirdGateway

#   Creates a NoCloud data source for cloud-init.
#   More info: http://cloudinit.readthedocs.io/en/latest/topics/datasources/nocloud.html
Write-Verbose 'Creating config ISO image...'
$instanceId = [Guid]::NewGuid().ToString()
# Will need to download the openssl.exe
$Hash=.\tools\openssl\openssl.exe passwd -6 $RootPassword

$ProtectedPackages=@"
@^server-product-environment
aide
audispd-plugins
audit
chrony
crypto-policies
dnf-automatic
dnf-plugin-subscription-manager
fapolicyd
firewalld
gnutls-utils
openscap
openscap-scanner
openssh-clients
openssh-server
policycoreutils
policycoreutils-python-utils
rsyslog
rsyslog-gnutls
scap-security-guide
subscription-manager
sudo
tmux
usbguard
-abrt
-abrt-addon-ccpp
-abrt-addon-kerneloops
-abrt-addon-python
-abrt-cli
-abrt-plugin-logger
-abrt-plugin-rhtsupport
-abrt-plugin-sosreport
-iprutils
-krb5-workstation
-nfs-utils
-sendmail
"@

$DefaultPackages=@"
@^minimal-environment
@standard
git
wget
-telnet-server
"@

$ProtectedDiskConfig=@"
# Protected Disk Configuration
ignoredisk --only-use=sda
# System bootloader configuration
bootloader --location=mbr --boot-drive=sda
# Partition clearing information
clearpart --none --initlabel
# Disk partitioning information
part / --fstype="xfs" --ondisk=sda --size=5120
part /var --fstype="xfs" --ondisk=sda --size=4096
part /var/log --fstype="xfs" --ondisk=sda --size=2048
part /var/log/audit --fstype="xfs" --ondisk=sda --size=2048
part /boot --fstype="xfs" --ondisk=sda --size=1024
part /boot/efi --fstype="efi" --ondisk=sda --size=1024 --fsoptions="umask=0077,shortname=winnt"
part /tmp --fstype="xfs" --ondisk=sda --size=2048
part /var/tmp --fstype="xfs" --ondisk=sda --size=2048
part swap --fstype="swap" --ondisk=sda --size=2048
part /home --fstype="xfs" --ondisk=sda --grow
"@

$DefaultDiskConfiguration=@"
# Default System bootloader configurations
bootloader --append=" crashkernel=auto" --location=mbr --boot-drive=sda
autopart --type=lvm
# Partition clearing information
clearpart --none --initlabel
"@
 
 #If Protection Profile is enabled then we need to add/remove packages and partition the disk
 if($EnableProtectionProfile) {
	$Packages=$ProtectedPackages
	$DiskConfiguration=$ProtectedDiskConfig

 } else {
	$Packages=$DefaultPackages
	$DiskConfiguration=$DefaultDiskConfiguration
 }
 
$config = @"
#version=RHEL8/UEFI/DISC

# Enables Graphical Menu during Install
#graphical
# Enable Text Mode during Install
text

################################
# Installation & Package Setup #
################################
# Use CDROM installation media
cdrom

# Addition Repositories Beyond BaseOS
repo --name="ks-AppStream" --baseurl=file:///run/install/repo/AppStream

# Package Configuration
%packages
# Packages to Add or Remove
$Packages
%end

#################
# System Config #
#################

##############
# User Setup #
##############
# Root password
rootpw --iscrypted $Hash

# Default Administrative User Account
user --groups=wheel --name=$RootUsername --password=$Hash --iscrypted --gecos="$RootUsername"

# Disk Configuration
$DiskConfiguration

#################
# Network Setup #
#################
# Network Device Setup via DCHP or Static
# EHT0
network  --bootproto=$BootProto --device=$InterfaceName --ip=$IPAddress --gateway=$Gateway --noipv6 --activate --nodefroute
# ETH1
network  --bootproto=$SecondaryBootProto --device=$SecondaryInterfaceName --ip=$SecondaryIPAddress --gateway=$SecondaryGateway --noipv6 --activate
# ETH2
network  --bootproto=$ThirdBootProto --device=$ThirdInterfaceName --ip=$ThirdIPAddress --gateway=$ThirdGateway --noipv6 --activate --hostname=$VMName.$DomainName --nameserver=8.8.8.8 --activate

##############
# Misc Setup #
##############
# System language
lang en_AU.UTF-8
#lang en_US.UTF-8

# Keyboard layouts
#keyboard --xlayouts='us'
keyboard --xlayouts='au'

# System timezone
timezone Australia/Sydney --isUtc

# /etc/shadow password hashed with sha512
auth --passalgo=sha512 --useshadow

# Disable First Boot application
firstboot --disable


# Disable Kernel Dumps
%addon com_redhat_kdump --disable
%end

%post --interpreter=/usr/bin/bash --log=/var/log/kickstart_bash_post.log
echo "Executing post installation commands.."
nmcli con up *
%end
# Reboot after Install
reboot
"@

# Save all files in temp folder and create config .iso from it
$tempPath = Join-Path ([System.IO.Path]::GetTempPath()) $instanceId
mkdir $tempPath | Out-Null
try {
    $config | Out-File "$tempPath\ks.cfg" -Encoding ascii

    $oscdimgPath = Join-Path $PSScriptRoot '.\tools\oscdimg.exe'
    & {
        $ErrorActionPreference = 'Continue'
        & $oscdimgPath $tempPath $configIso -j2 -lOEMDRV
        if ($LASTEXITCODE -gt 0) {
            throw "oscdimg.exe returned $LASTEXITCODE."
        }
    }
}
finally {
    rmdir -Path $tempPath -Recurse -Force
    $ErrorActionPreference = 'Stop'
}

# Adds DVD with config.iso
$dvd = $vm | Add-VMDvdDrive -Path $configIso -Passthru

# Disable Automatic Checkpoints. Check if command is available since it doesn't exist in Server 2016.
$command = Get-Command Set-VM
if ($command.Parameters.AutomaticCheckpointsEnabled) {
    $vm | Set-VM -AutomaticCheckpointsEnabled $false
}

# Wait for VM
$vm | Start-VM
Write-Verbose 'Waiting for VM integration services...'
Wait-VM -Name $VMName -For Heartbeat
#Wait-VM -Name $VMName -For IPAddress

Write-Verbose 'All done!'
Write-Verbose 'After finished, please remember to remove the installation media with:'
Write-Verbose "Get-VMDvdDrive -VMName '$VMName' | Remove-VMDvdDrive"

# Return the VM created.
$vm
