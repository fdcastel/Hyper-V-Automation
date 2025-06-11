# Hyper-V automation scripts

Collection of Powershell scripts to create Windows, Ubuntu and Debian VMs in Hyper-V.

For Windows Server 2016+, Windows 8.1+ only.

For Hyper-V Generation 2 (UEFI) VMs only.

To migrate an existing Windows VM from Hyper-V to Proxmox (QEMU) see [Prepare a VHDX for QEMU migration](#prepare-a-vhdx-for-qemu-migration).



## How to install

To download all scripts into your `$env:TEMP` folder:

```powershell
iex (iwr 'bit.ly/h-v-a' -UseBasicParsing)
```


# Examples

## Create a new VM for Hyper-V

```powershell
$isoFile = '.\en_windows_server_2019_x64_dvd_4cb967d8.iso'
$vmName = 'TstWindows'
$pass = 'u531@rg3pa55w0rd$!'

.\New-VMFromWindowsImage.ps1 `
    -SourcePath $isoFile `
    -Edition 'Windows Server 2019 Standard' `
    -VMName $vmName `
    -VHDXSizeBytes 60GB `
    -AdministratorPassword $pass `
    -Version 'Server2019Standard' `
    -MemoryStartupBytes 2GB `
    -VMProcessorCount 2

$sess = .\New-VMSession.ps1 -VMName $vmName -AdministratorPassword $pass

.\Set-NetIPAddressViaSession.ps1 `
    -Session $sess `
    -IPAddress 10.10.1.195 `
    -PrefixLength 16 `
    -DefaultGateway 10.10.1.250 `
    -DnsAddresses '8.8.8.8','8.8.4.4' `
    -NetworkCategory 'Public'

.\Enable-RemoteManagementViaSession.ps1 -Session $sess

# You can run any commands on VM with Invoke-Command:
Invoke-Command -Session $sess {
    echo "Hello, world! (from $env:COMPUTERNAME)"

    # Install chocolatey
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

    # Install 7-zip
    choco install 7zip -y
}

Remove-PSSession -Session $sess
```



## Prepare a VHDX for QEMU migration

```powershell
$vmName = 'TstWindows'

# Shutdown VM
Stop-VM $vmName

# Get VirtIO ISO
$virtioIso = .\Get-VirtioImage.ps1 -OutputPath $env:TEMP

# Install VirtIO drivers to Windows VM (offline)
$vhdxFile = "C:\Hyper-V\Virtual Hard Disks\$vmName.vhdx"
.\Add-VirtioDrivers.ps1 -VirtioIsoPath $virtioIso -ImagePath $vhdxFile

# Copy VHDX file to QEMU host
scp $vhdxFile "root@pve-host:/tmp/"
```

After the copy is complete, you may use [`new-vm-windows`](https://github.com/fdcastel/Proxmox-Automation#new-vm-windows) on Proxmox to import the `vhdx` file and create the Windows VM.

Once the VM is running, ensure that the [QEMU Guest Agent](https://pve.proxmox.com/wiki/Qemu-guest-agent) is installed within the guest environment.



## Create a Windows `vhdx` template for QEMU

```powershell
$isoFile = '.\en-us_windows_server_2025_x64_dvd_ccbcec44.iso'
$targetVhdx = '.\Server2025Standard-template.vhdx'

# Get VirtIO ISO
$virtioIso = .\Get-VirtioImage.ps1 -OutputPath $env:TEMP

# Get Cloudbase-Init installer
$cloudbaseInitMsi = .\Get-CloudBaseInit.ps1 -OutputPath $env:TEMP

# Create VHDX
New-VHDXFromWindowsImage.ps1 `
    -SourcePath $isoFile `
    -Edition 'Windows Server 2025 Standard' `
    -VHDXPath $targetVhdx `
    -VHDXSizeBytes 60GB `
    -Version 'Server2025Standard' `
    -AddVirtioDrivers $virtioIso `
    -AddCloudBaseInit $cloudbaseInitMsi

# Copy VHDX file to QEMU host
scp $vhdxFile "root@pve-host:/tmp/"
```

After the copy is complete, you may use [`new-vm-windows`](https://github.com/fdcastel/Proxmox-Automation#new-vm-windows) on Proxmox to import the `vhdx` file and create the Windows VM.

The guest VM will come pre-installed with the following software:
- [Windows VirtIO Drivers](https://pve.proxmox.com/wiki/Windows_VirtIO_Drivers)
- [QEMU Guest Agent](https://pve.proxmox.com/wiki/Qemu-guest-agent)
- [Cloudbase-Init](https://cloudbase.it/cloudbase-init/)



# Command summary
  - For Windows VMs
    - [New-VMFromWindowsImage](#new-vmfromwindowsimage-) (*)
    - [New-VHDXFromWindowsImage](#new-vhdxfromwindowsimage-) (*)
    - [New-VMSession](#new-vmsession)
    - [Set-NetIPAddressViaSession](#set-netipaddressviasession)
    - [Set-NetIPv6AddressViaSession](#set-netipv6addressviasession)
    - [Get-CloudBaseInit](#get-cloudbaseinit)
    - [Get-VirtioImage](#get-virtioimage)
    - [Add-VirtioDrivers](#add-virtiodrivers)
    - [Enable-RemoteManagementViaSession](#enable-remotemanagementviasession)
  - For Ubuntu VMs
    - [Get-UbuntuImage](#get-ubuntuimage)
    - [New-VMFromUbuntuImage](#new-vmfromubuntuimage-) (*)
  - For Debian VMs
    - [Get-DebianImage](#get-debianimage)
    - [New-VMFromDebianImage](#new-vmfromdebianimage-) (*)
  - For images with no `cloud-init` support
    - [Get-OPNsenseImage](#get-opnsenseimage)
    - [New-VMFromIsoImage](#new-vmfromisoimage-) (*)
  - Other commands
    - [Download-VerifiedFile](#download-verifiedfile)
    - [Move-VMOffline](#move-vmoffline)

**(*) Requires administrative privileges**.



# For Windows VMs

## New-VMFromWindowsImage (*)

```powershell
New-VMFromWindowsImage.ps1 [-SourcePath] <string> [-Edition] <string> [-VMName] <string> [-VHDXSizeBytes] <uint64> [-AdministratorPassword] <string> [-Version] <string> [-MemoryStartupBytes] <long> [[-VMProcessorCount] <long>] [[-VMSwitchName] <string>] [[-VMMacAddress] <string>] [[-Locale] <string>] [-EnableDynamicMemory] [<CommonParameters>]
```

Creates a Windows VM from an ISO image.

For the `-Edition` parameter use `Get-WindowsImage -ImagePath <path-to-install.wim>` to see all available images. Or just use "1" for the first one.

The `-Version` parameter is required to set the product key (required for a full unattended install).

Returns the `VirtualMachine` created.

**(*) Requires administrative privileges**.



## New-VHDXFromWindowsImage (*)

```powershell
New-VHDXFromWindowsImage.ps1 [-SourcePath] <string> [-Edition] <string> [[-ComputerName] <string>] [[-VHDXPath] <string>] [[-VHDXSizeBytes] <uint64>] [[-AdministratorPassword] <string>] [-Version] <string> [[-Locale] <string>] [[-AddVirtioDrivers] <string>] [[-AddCloudBaseInit] <string>] [<CommonParameters>]
```

Creates a Windows VHDX from an ISO image. Similar to `New-VMFromWindowsImage` but without creating a VM.

You can add [Windows VirtIO Drivers](https://pve.proxmox.com/wiki/Windows_VirtIO_Drivers) and the [QEMU Guest Agent](https://pve.proxmox.com/wiki/Qemu-guest-agent) with `-AddVirtioDrivers`. In this case you must provide the path of VirtIO ISO (see [`Get-VirtioImage`](#Get-VirtioImage)) to this parameter. This is useful if you wish to import the created VHDX in a KVM environment.

Returns the path for the VHDX file created.

**(*) Requires administrative privileges**.



## New-VMSession

```powershell
New-VMSession.ps1 [-VMName] <string> [-AdministratorPassword] <string> [[-DomainName] <string>] [<CommonParameters>]
```

Creates a new `PSSession` into a VM. In case of error, keeps retrying until connected. Useful for wait until a VM is ready to accept commands.

Returns the `PSSession` created.



## Set-NetIPAddressViaSession

```powershell
Set-NetIPAddressViaSession.ps1 [-Session] <PSSession[]> [[-AdapterName] <string>] [-IPAddress] <string> [-PrefixLength] <byte> [-DefaultGateway] <string> [[-DnsAddresses] <string[]>] [[-NetworkCategory] <string>] [<CommonParameters>]
```

Sets IPv4 configuration for a Windows VM.



## Set-NetIPv6AddressViaSession

```powershell
Set-NetIPv6AddressViaSession.ps1 [-Session] <PSSession[]> [[-AdapterName] <string>] [-IPAddress] <ipaddress> [-PrefixLength] <byte> [[-DnsAddresses] <string[]>] [<CommonParameters>]
```

Sets IPv6 configuration for a Windows VM.



## Get-CloudBaseInit

```powershell
Get-CloudBaseInit.ps1 [[-OutputPath] <string>] [<CommonParameters>]
```

Downloads latest stable MSI installer of [Cloudbase-Init](https://cloudbase.it/cloudbase-init/).

Use `-OutputPath` parameter to set download location. If not informed, the current folder will be used.

Returns the path for downloaded file.



## Get-VirtioImage

```powershell
Get-VirtioImage.ps1 [[-OutputPath] <string>] [<CommonParameters>]
```

Downloads latest stable ISO image of [Windows VirtIO Drivers](https://pve.proxmox.com/wiki/Windows_VirtIO_Drivers).

Use `-OutputPath` parameter to set download location. If not informed, the current folder will be used.

Returns the path for downloaded file.



## Add-VirtioDrivers

```powershell
Add-VirtioDrivers.ps1 [-VirtioIsoPath] <string> [-ImagePath] <string> [-Version] <string> [[-ImageIndex] <int>] [<CommonParameters>]
```

Adds [Windows VirtIO Drivers](https://pve.proxmox.com/wiki/Windows_VirtIO_Drivers) into a WIM or VHDX file.

You must inform the path of VirtIO ISO with `-VirtioIsoPath`. You can download the latest image from [here](https://pve.proxmox.com/wiki/Windows_VirtIO_Drivers#Using_the_ISO). Or just use [`Get-VirtioImage.ps1`](#Get-VirtioImage).

You must use `-ImagePath` to inform the path of file.

You may use `-Version` to specify the Windows version of the image (recommended). This ensures that all appropriate drivers for the system are installed correctly.

For WIM files you must also use `-ImageIndex` to inform the image index inside of WIM. For VHDX files the image index must be always `1` (the default).

Please note that -- unlike the `-AddVirtioDrivers` option from `New-VHDXFromWindowsImage` -- this script cannot install the [QEMU Guest Agent](https://pve.proxmox.com/wiki/Qemu-guest-agent) in an existing `vhdx`, as its operations are limited to the offline image (cannot run the installer).



## Enable-RemoteManagementViaSession

```powershell
Enable-RemoteManagementViaSession.ps1 [-Session] <PSSession[]> [<CommonParameters>]
```

Enables Powershell Remoting, CredSSP server authentication and sets WinRM firewall rule to `Any` remote address (default: `LocalSubnet`).



# For Ubuntu VMs

## Get-UbuntuImage

```powershell
Get-UbuntuImage.ps1 [[-OutputPath] <string>] [-Previous] [<CommonParameters>]
```

Downloads latest Ubuntu LTS cloud image and verify its integrity.

Use `-OutputPath` parameter to set download location. If not informed, the current folder will be used.

Use `-Previous` parameter to download the previous LTS image instead of the current LTS.

Returns the path for downloaded file.



## New-VMFromUbuntuImage (*)

```powershell
New-VMFromUbuntuImage.ps1 -SourcePath <string> -VMName <string> -RootPassword <string> [-FQDN <string>] [-VHDXSizeBytes <uint64>] [-MemoryStartupBytes <long>] [-EnableDynamicMemory] [-ProcessorCount <long>] [-SwitchName <string>] [-MacAddress <string>] [-IPAddress <string>] [-Gateway <string>] [-DnsAddresses <string[]>] [-InterfaceName <string>] [-VlanId <string>] [-SecondarySwitchName <string>] [-SecondaryMacAddress <string>] [-SecondaryIPAddress <string>] [-SecondaryInterfaceName <string>] [-SecondaryVlanId <string>] [-InstallDocker] [<CommonParameters>]

New-VMFromUbuntuImage.ps1 -SourcePath <string> -VMName <string> -RootPublicKey <string> [-FQDN <string>] [-VHDXSizeBytes <uint64>] [-MemoryStartupBytes <long>] [-EnableDynamicMemory] [-ProcessorCount <long>] [-SwitchName <string>] [-MacAddress <string>] [-IPAddress <string>] [-Gateway <string>] [-DnsAddresses <string[]>] [-InterfaceName <string>] [-VlanId <string>] [-SecondarySwitchName <string>] [-SecondaryMacAddress <string>] [-SecondaryIPAddress <string>] [-SecondaryInterfaceName <string>] [-SecondaryVlanId <string>] [-InstallDocker] [<CommonParameters>]
```

Creates a Ubuntu VM from Ubuntu Cloud image.

You must have [qemu-img](https://github.com/fdcastel/qemu-img-windows-x64) installed. If you have [chocolatey](https://chocolatey.org/) you can install it with:

```
choco install qemu-img -y
```

You can download Ubuntu cloud images from [here](https://cloud-images.ubuntu.com/releases/focal/release/) (get the `amd64.img` version). Or just use [`Get-UbuntuImage.ps1`](#Get-UbuntuImage).

You must use `-RootPassword` to set a password or `-RootPublicKey` to set a public key for default `ubuntu` user.

You may configure network using `-VlanId`, `-IPAddress`, `-Gateway` and `-DnsAddresses` options. `-IPAddress` must be in `address/prefix` format. If not specified the network will be configured via DHCP.

You may rename interfaces with `-InterfaceName` and `-SecondaryInterfaceName`. This will set Hyper-V network adapter name and also set the interface name in Ubuntu.

You may add a second network using `-SecondarySwitchName`. You may configure it with `-Secondary*` options.

You may install Docker using `-InstallDocker` switch.

Returns the `VirtualMachine` created.

**(*) Requires administrative privileges**.



## Ubuntu: Example

```powershell
# Create a VM with static IP configuration and ssh public key access
$imgFile = .\Get-UbuntuImage.ps1 -Verbose
$vmName = 'TstUbuntu'
$fqdn = 'test.example.com'
$rootPublicKey = Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub"

.\New-VMFromUbuntuImage.ps1 `
    -SourcePath $imgFile `
    -VMName $vmName `
    -FQDN $fqdn `
    -RootPublicKey $rootPublicKey `
    -VHDXSizeBytes 60GB `
    -MemoryStartupBytes 2GB `
    -ProcessorCount 2 `
    -IPAddress 10.10.1.196/16 `
    -Gateway 10.10.1.250 `
    -DnsAddresses '8.8.8.8','8.8.4.4' `
    -Verbose

# Your public key is installed. This should not ask you for a password.
ssh ubuntu@10.10.1.196
```



# For Debian VMs

## Get-DebianImage

```powershell
Get-DebianImage.ps1 [[-OutputPath] <string>] [<CommonParameters>]
```

Downloads latest Debian cloud image.

Use `-OutputPath` parameter to set download location. If not informed, the current folder will be used.

Returns the path for downloaded file.



## New-VMFromDebianImage (*)

```powershell
New-VMFromDebianImage.ps1 -SourcePath <string> -VMName <string> -RootPassword <string> [-FQDN <string>] [-VHDXSizeBytes <uint64>] [-MemoryStartupBytes <long>] [-EnableDynamicMemory] [-ProcessorCount <long>] [-SwitchName <string>] [-MacAddress <string>] [-IPAddress <string>] [-Gateway <string>] [-DnsAddresses <string[]>] [-InterfaceName <string>] [-VlanId <string>] [-SecondarySwitchName <string>] [-SecondaryMacAddress <string>] [-SecondaryIPAddress <string>] [-SecondaryInterfaceName <string>] [-SecondaryVlanId <string>] [-InstallDocker] [<CommonParameters>]

New-VMFromDebianImage.ps1 -SourcePath <string> -VMName <string> -RootPublicKey <string> [-FQDN <string>] [-VHDXSizeBytes <uint64>] [-MemoryStartupBytes <long>] [-EnableDynamicMemory] [-ProcessorCount <long>] [-SwitchName <string>] [-MacAddress <string>] [-IPAddress <string>] [-Gateway <string>] [-DnsAddresses <string[]>] [-InterfaceName <string>] [-VlanId <string>] [-SecondarySwitchName <string>] [-SecondaryMacAddress <string>] [-SecondaryIPAddress <string>] [-SecondaryInterfaceName <string>] [-SecondaryVlanId <string>] [-InstallDocker] [<CommonParameters>]
```

Creates a Debian VM from Debian Cloud image. For Debian 11 only.

You must have [qemu-img](https://github.com/fdcastel/qemu-img-windows-x64) installed. If you have [chocolatey](https://chocolatey.org/) you can install it with:

```
choco install qemu-img -y
```

You can download Debian cloud images from [here](https://cloud.debian.org/images/cloud/bullseye/daily) (get the `genericcloud-amd64 version`). Or just use [`Get-DebianImage.ps1`](#Get-DebianImage).

You must use `-RootPassword` to set a password or `-RootPublicKey` to set a public key for default `debian` user.

You may configure network using `-VlanId`, `-IPAddress`, `-Gateway` and `-DnsAddresses` options. `-IPAddress` must be in `address/prefix` format. If not specified the network will be configured via DHCP.

You may rename interfaces with `-InterfaceName` and `-SecondaryInterfaceName`. This will set Hyper-V network adapter name and also set the interface name in Debian.

You may add a second network using `-SecondarySwitchName`. You may configure it with `-Secondary*` options.

You may install Docker using `-InstallDocker` switch.

Returns the `VirtualMachine` created.

**(*) Requires administrative privileges**.



## Debian: Example

```powershell
# Create a VM with static IP configuration and ssh public key access
$imgFile = .\Get-DebianImage.ps1 -Verbose
$vmName = 'TstDebian'
$fqdn = 'test.example.com'
$rootPublicKey = Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub"

.\New-VMFromDebianImage.ps1 `
    -SourcePath $imgFile `
    -VMName $vmName `
    -FQDN $fqdn `
    -RootPublicKey $rootPublicKey `
    -VHDXSizeBytes 60GB `
    -MemoryStartupBytes 2GB `
    -ProcessorCount 2 `
    -IPAddress 10.10.1.197/16 `
    -Gateway 10.10.1.250 `
    -DnsAddresses '8.8.8.8','8.8.4.4' `
    -Verbose

# Your public key is installed. This should not ask you for a password.
ssh debian@10.10.1.197
```



# For images with no `cloud-init` support

## Get-OPNsenseImage

```powershell
Get-OPNsenseImage.ps1 [[-OutputPath] <string>] [<CommonParameters>]
```

Downloads latest OPNsense ISO image.

Use `-OutputPath` parameter to set download location. If not informed, the current folder will be used.

Returns the path for downloaded file.



## New-VMFromIsoImage (*)

```powershell
New-VMFromIsoImage.ps1 [-IsoPath] <string> [-VMName] <string> [[-VHDXSizeBytes] <uint64>] [[-MemoryStartupBytes] <long>] [[-ProcessorCount] <long>] [[-SwitchName] <string>] [[-MacAddress] <string>] [[-InterfaceName] <string>] [[-VlanId] <string>] [[-SecondarySwitchName] <string>] [[-SecondaryMacAddress] <string>] [[-SecondaryInterfaceName] <string>] [[-SecondaryVlanId] <string>] [-EnableDynamicMemory] [-EnableSecureBoot] [<CommonParameters>]
```

Creates a VM and boot it from a ISO image.

Returns the `VirtualMachine` created.

After installation, remember to remove the ISO mounted drive with:

```powershell
Get-VMDvdDrive -VMName 'vm-name' | Remove-VMDvdDrive
```

**(*) Requires administrative privileges**.



## OPNsense: Example

The following example will create a OPNsense router and a Windows VM in a private network which will have internet access through OPNsense.

It requires two Hyper-V Virtual Switches:

- `SWITCH` (type: External), connected to a network with internet access and DHCP; and
- `ISWITCH` (type: Internal), for the private netork.

From OPNsense convention, the first network interface will be assigned as LAN.
> **Note**: The default network address will be `192.168.1.1/24` with DHCP enabled.

```powershell
$isoFile = .\Get-OPNsenseImage.ps1 -Verbose
$vmName = 'TstOpnRouter'

.\New-VMFromIsoImage.ps1 `
    -IsoPath $isoFile `
    -VMName $vmName `
    -VHDXSizeBytes 60GB `
    -MemoryStartupBytes 2GB `
    -ProcessorCount 2 `
    -SwitchName 'ISWITCH' `
    -InterfaceName 'lan' `
    -SecondarySwitchName 'SWITCH' `
    -SecondaryInterfaceName 'wan' `
    -Verbose

# Windows Server 2022 image
$isoFile = 'C:\Adm\SW_DVD9_Win_Server_STD_CORE_2022__64Bit_English_DC_STD_MLF_X22-74290.ISO'
$vmName = 'TstOpnClient'
$pass = 'u531@rg3pa55w0rd$!'

.\New-VMFromWindowsImage.ps1 `
    -SourcePath $isoFile `
    -Edition 'Windows Server 2022 Standard (Desktop Experience)' `
    -VMName $vmName `
    -VHDXSizeBytes 60GB `
    -AdministratorPassword $pass `
    -Version 'Server2022Standard' `
    -MemoryStartupBytes 4GB `
    -VMProcessorCount 2 `
    -VMSwitchName 'ISWITCH'
```

The Windows VM should get an internal IP address (from `192.168.1.x/24` range) via DHCP from OPNsense and it should have working internet access.

Remember that OPNsense will be running in _live_ mode from ISO image. To install it logon via console with `installer` user and `opnsense` password.

After the installation, remove the installation media with:

```powershell
Get-VMDvdDrive -VMName 'TstOpnRouter' | Remove-VMDvdDrive
```



# Other commands

## Download-VerifiedFile

```powershell
Download-VerifiedFile.ps1 [-Url] <string> [-ExpectedHash] <string> [[-TargetDirectory] <string>] [<CommonParameters>]
```

Downloads a file and validates its integrity through SHA256 hash verification.

If the file is already present and the hashes match, the download is skipped.



## Move-VMOffline

```powershell
Move-VMOffline.ps1 [-VMName] <string> [-DestinationHost] <string> [-CertificateThumbprint] <string> [<CommonParameters>]
```

Uses Hyper-V replica to move a VM between hosts not joined in a domain.
