# Hyper-V automation scripts

Collection of Powershell scripts to create Windows, Ubuntu and Debian VMs in Hyper-V.

For Windows Server 2016/2019, Windows 8.1/10 only.

For Hyper-V Generation 2 VMs only.



## How to install

To download all scripts into your `$env:temp` folder:

```powershell
iex (iwr 'bit.ly/h-v-a')
```



## Command summary
  - For Windows VMs
    - [New-WindowsUnattendFile](#New-WindowsUnattendFile)
    - [New-VMFromWindowsImage](#New-VMFromWindowsImage-) (*)
    - [New-VHDXFromWindowsImage](#New-VHDXFromWindowsImage-) (*)
    - [New-VMSession](#New-VMSession)
    - [Enable-RemoteManagementViaSession](#Enable-RemoteManagementViaSession)
    - [Set-NetIPAddressViaSession](#Set-NetIPAddressViaSession)
    - [Get-VirtioImage](#Get-VirtioImage)
    - [Add-VirtioDrivers](#Add-VirtioDrivers)
  - For Ubuntu VMs
    - [Get-UbuntuImage](#Get-UbuntuImage)
    - [New-VMFromUbuntuImage](#New-VMFromUbuntuImage-) (*)
  - For Debian VMs
    - [Get-DebianImage](#Get-DebianImage)
    - [New-VMFromDebianImage](#New-VMFromDebianImage-) (*)
  - Other commands
    - [Move-VMOffline](#move-vmoffline)

**(*) Requires administrative privileges**.



## For Windows VMs

### New-WindowsUnattendFile

```powershell
New-WindowsUnattendFile.ps1 [-AdministratorPassword] <string> [-Version] <string> [[-ComputerName] <string>] [[-FilePath] <string>] [[-Locale] <string>] [<CommonParameters>]
```

Creates an `unattend.xml` file to initialize a Windows VM. Used by `New-VMFromWindowsImage`.

Returns the full path of created file.



### New-VMFromWindowsImage (*)

```powershell
New-VMFromWindowsImage.ps1 [-SourcePath] <string> [-Edition] <string> [-VMName] <string> [-VHDXSizeBytes] <uint64> [-AdministratorPassword] <string> [-Version] <string> [-MemoryStartupBytes] <long> [[-VMProcessorCount] <long>] [[-VMSwitchName] <string>] [[-VMMacAddress] <string>] [[-Locale] <string>] [-EnableDynamicMemory] [<CommonParameters>]
```

Creates a Windows VM from an ISO image. 

For the `-Edition` parameter use `Get-WindowsImage -ImagePath <path-to-install.wim>` to see all available images. Or just use "1" for the first one.

The `-Version` parameter is required to set the product key (required for a full unattended install).

Returns the `VirtualMachine` created.

**(*) Requires administrative privileges**.



### New-VHDXFromWindowsImage (*)

```powershell
New-VHDXFromWindowsImage.ps1 [-SourcePath] <string> [-Edition] <string> [-ComputerName] <string> [[-VHDXPath] <string>] [-VHDXSizeBytes] <uint64> [-AdministratorPassword] <string> [-Version] <string> [[-Locale] <string>] [[-AddVirtioDrivers] <string>] [<CommonParameters>]
```

Creates a Windows VHDX from an ISO image. Similar to `New-VMFromWindowsImage` but without creating a VM.

You can add VirtIO drivers with `-AddVirtioDrivers`. In this case you must inform the path of VirtIO ISO (see [`Get-VirtioImage`](#Get-VirtioImage)). This is useful if you wish to import the created VHDX in a KVM environment.

Returns the path for the VHDX file created.

**(*) Requires administrative privileges**.



### New-VMSession

```powershell
New-VMSession.ps1 [-VMName] <string> [-AdministratorPassword] <string> [[-DomainName] <string>] [<CommonParameters>]
```

Creates a new `PSSession` into a VM. In case of error, keeps retrying until connected. Useful for wait until a VM is ready to accept commands.

Returns the `PSSession` created.



### Enable-RemoteManagementViaSession

```powershell
Enable-RemoteManagementViaSession.ps1 [-Session] <PSSession[]> [<CommonParameters>]
```

Enables Powershell Remoting, CredSSP server authentication and sets WinRM firewall rule to `Any` remote address (default: `LocalSubnet`).



### Set-NetIPAddressViaSession

```powershell
Set-NetIPAddressViaSession.ps1 [-Session] <PSSession[]> [-IPAddress] <string> [-PrefixLength] <byte> [-DefaultGateway] <string> [[-DnsAddresses] <string[]>] [[-NetworkCategory] <string>] [<CommonParameters>]
```

Sets TCP/IP configuration for a VM.



### Get-VirtioImage

```powershell
Get-VirtioImage.ps1 [[-OutputPath] <string>] [<CommonParameters>]
```

Downloads latest stable ISO image of [Windows VirtIO Drivers](https://pve.proxmox.com/wiki/Windows_VirtIO_Drivers).

Use `-OutputPath` parameter to set download location. If not informed, the current folder will be used.

Returns the path for downloaded file.



### Add-VirtioDrivers

```powershell
Add-VirtioDrivers.ps1 [-VirtioIsoPath] <string> [-ImagePath] <string> [[-ImageIndex] <int>] [<CommonParameters>]
```

Adds [Windows VirtIO Drivers](https://pve.proxmox.com/wiki/Windows_VirtIO_Drivers) into a WIM or VHDX file.

You must inform the path of VirtIO ISO with `-VirtioIsoPath`. You can download the latest image from [here](https://pve.proxmox.com/wiki/Windows_VirtIO_Drivers#Using_the_ISO). Or just use [`Get-VirtioImage.ps1`](#Get-VirtioImage).

You must use `-ImagePath` to inform the path of file. For WIM files you must also use `-ImageIndex` to inform the image index inside of WIM. For VHDX files the image index must be always `1` (the default).



### Usage sample

```powershell
$isoFile = '.\en_windows_server_2019_x64_dvd_4cb967d8.iso'
$vmName = 'TstWindows'
$pass = 'u531@rg3pa55w0rd$!'

.\New-VMFromWindowsImage.ps1 -SourcePath $isoFile -Edition 'Windows Server 2019 Standard' -VMName $vmName -VHDXSizeBytes 60GB -AdministratorPassword $pass -Version 'Server2019Standard' -MemoryStartupBytes 2GB -VMProcessorCount 2

$sess = .\New-VMSession.ps1 -VMName $vmName -AdministratorPassword $pass

.\Set-NetIPAddressViaSession.ps1 -Session $sess -IPAddress 10.10.1.195 -PrefixLength 16 -DefaultGateway 10.10.1.250 -DnsAddresses '8.8.8.8','8.8.4.4' -NetworkCategory 'Public'

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



## For Ubuntu VMs

### Get-UbuntuImage

```powershell
Get-UbuntuImage.ps1 [[-OutputPath] <string>] [-Previous] [<CommonParameters>]
```

Downloads latest Ubuntu 20.04 LTS cloud image and verify its integrity.

Use `-OutputPath` parameter to set download location. If not informed, the current folder will be used.

Use `-Previous` parameter to download Ubuntu 18.04 LTS image instead of 20.04 LTS.

Returns the path for downloaded file.



### New-VMFromUbuntuImage (*)

```powershell
New-VMFromUbuntuImage.ps1 -SourcePath <string> -VMName <string> -RootPassword <string> [-FQDN <string>] [-VHDXSizeBytes <uint64>] [-MemoryStartupBytes <long>] [-EnableDynamicMemory] [-ProcessorCount <long>] [-SwitchName <string>] [-MacAddress <string>] [-IPAddress <string>] [-Gateway <string>] [-DnsAddresses <string[]>] [-InterfaceName <string>] [-VlanId <string>] [-EnableRouting] [-SecondarySwitchName <string>] [-SecondaryMacAddress <string>] [-SecondaryIPAddress <string>] [-SecondaryInterfaceName <string>] [-SecondaryVlanId <string>] [-LoopbackIPAddress <string>] [-InstallDocker] [<CommonParameters>]

New-VMFromUbuntuImage.ps1 -SourcePath <string> -VMName <string> -RootPublicKey <string> [-FQDN <string>] [-VHDXSizeBytes <uint64>] [-MemoryStartupBytes <long>] [-EnableDynamicMemory] [-ProcessorCount <long>] [-SwitchName <string>] [-MacAddress <string>] [-IPAddress <string>] [-Gateway <string>] [-DnsAddresses <string[]>] [-InterfaceName <string>] [-VlanId <string>] [-EnableRouting] [-SecondarySwitchName <string>] [-SecondaryMacAddress <string>] [-SecondaryIPAddress <string>] [-SecondaryInterfaceName <string>] [-SecondaryVlanId <string>] [-LoopbackIPAddress <string>] [-InstallDocker] [<CommonParameters>]

New-VMFromUbuntuImage.ps1 -SourcePath <string> -VMName <string> -EnableRouting -SecondarySwitchName <string> [-FQDN <string>] [-VHDXSizeBytes <uint64>] [-MemoryStartupBytes <long>] [-EnableDynamicMemory] [-ProcessorCount <long>] [-SwitchName <string>] [-MacAddress <string>] [-IPAddress <string>] [-Gateway <string>] [-DnsAddresses <string[]>] [-InterfaceName <string>] [-VlanId <string>] [-SecondaryMacAddress <string>] [-SecondaryIPAddress <string>] [-SecondaryInterfaceName <string>] [-SecondaryVlanId <string>] [-LoopbackIPAddress <string>] [-InstallDocker] [<CommonParameters>]
```

Creates a Ubuntu VM from Ubuntu Cloud image. For Ubuntu 18.04 LTS or 20.04 LTS only.

You must have [qemu-img](https://cloudbase.it/qemu-img-windows/) installed. If you have [chocolatey](https://chocolatey.org/) you can install it with:

```
choco install qemu-img -y
```

You can download Ubuntu cloud images from [here](https://cloud-images.ubuntu.com/releases/focal/release/) (get the `amd64.img` version). Or just use [`Get-UbuntuImage.ps1`](#Get-UbuntuImage).

You must use `-RootPassword` to set a password or `-RootPublicKey` to set a public key for default `ubuntu` user.

You may configure network using `-VlanId`, `-IPAddress`, `-Gateway` and `-DnsAddresses` options. `-IPAddress` must be in `address/prefix` format. If not specified the network will be configured via DHCP.

You may rename interfaces with `-InterfaceName` and `-SecondaryInterfaceName`. This will set Hyper-V network adapter name and also set the interface name in Ubuntu.

You may add a second network using `-SecondarySwitchName`. You may configure it with `-Secondary*` options.

You may configure it as a router using `-EnableRouting` switch. In this case you must inform a second network using `-SecondarySwitchName` (which will be the LAN segment).

You may install Docker using `-InstallDocker` switch.

Returns the `VirtualMachine` created.

**(*) Requires administrative privileges**.



### Usage sample

```powershell
# Create a VM with static IP configuration and ssh public key access
$imgFile = .\Get-UbuntuImage.ps1 -Verbose
$vmName = 'TstUbuntu'
$fqdn = 'test.example.com'
$rootPublicKey = Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub"

.\New-VMFromUbuntuImage.ps1 -SourcePath $imgFile -VMName $vmName -FQDN $fqdn -RootPublicKey $rootPublicKey -VHDXSizeBytes 60GB -MemoryStartupBytes 2GB -ProcessorCount 2 -IPAddress 10.10.1.196/16 -Gateway 10.10.1.250 -DnsAddresses '8.8.8.8','8.8.4.4' -Verbose

# Your public key is installed. This should not ask you for a password.
ssh ubuntu@10.10.1.196
```



## For Debian VMs

### Get-DebianImage

```powershell
Get-DebianImage.ps1 [[-OutputPath] <string>] [<CommonParameters>]
```

Downloads latest Debian 10 cloud image.

**IMPORTANT:** Unlike `Get-UbuntuImage.ps1`, this script doesn't check the integrity of the downloaded file.

Use `-OutputPath` parameter to set download location. If not informed, the current folder will be used.

Returns the path for downloaded file.



### New-VMFromDebianImage (*)

```powershell
New-VMFromDebianImage.ps1 -SourcePath <string> -VMName <string> -RootPassword <string> [-FQDN <string>] [-VHDXSizeBytes <uint64>] [-MemoryStartupBytes <long>] [-EnableDynamicMemory] [-ProcessorCount <long>] [-SwitchName <string>] [-MacAddress <string>] [-IPAddress <string>] [-Gateway <string>] [-DnsAddresses <string[]>] [-InterfaceName <string>] [-EnableRouting] [-SecondarySwitchName <string>] [-SecondaryMacAddress <string>] [-SecondaryIPAddress <string>] [-SecondaryInterfaceName <string>] [-LoopbackIPAddress <string>] [-InstallDocker] [<CommonParameters>]

New-VMFromDebianImage.ps1 -SourcePath <string> -VMName <string> -RootPublicKey <string> [-FQDN <string>] [-VHDXSizeBytes <uint64>] [-MemoryStartupBytes <long>] [-EnableDynamicMemory] [-ProcessorCount <long>] [-SwitchName <string>] [-MacAddress <string>] [-IPAddress <string>] [-Gateway <string>] [-DnsAddresses <string[]>] [-InterfaceName <string>] [-EnableRouting] [-SecondarySwitchName <string>] [-SecondaryMacAddress <string>] [-SecondaryIPAddress <string>] [-SecondaryInterfaceName <string>] [-LoopbackIPAddress <string>] [-InstallDocker] [<CommonParameters>]

New-VMFromDebianImage.ps1 -SourcePath <string> -VMName <string> -EnableRouting -SecondarySwitchName <string> [-FQDN <string>] [-VHDXSizeBytes <uint64>] [-MemoryStartupBytes <long>] [-EnableDynamicMemory] [-ProcessorCount <long>] [-SwitchName <string>] [-MacAddress <string>] [-IPAddress <string>] [-Gateway <string>] [-DnsAddresses <string[]>] [-InterfaceName <string>] [-SecondaryMacAddress <string>] [-SecondaryIPAddress <string>] [-SecondaryInterfaceName <string>] [-LoopbackIPAddress <string>] [-InstallDocker] [<CommonParameters>]
```

Creates a Debian VM from Debian Cloud image. For Debian 10 only.

**IMPORTANT:** Unlike `New-VMFromUbuntuImage.ps1`, this script create VMs with **Secure Boot disabled** (Debian 10 [should support it](https://bit.ly/2wkRzd1), but I cannot make it work).

You must have [qemu-img](https://cloudbase.it/qemu-img-windows/) installed. If you have [chocolatey](https://chocolatey.org/) you can install it with:

```
choco install qemu-img -y
```

You can download Debian cloud images from [here](https://cloud.debian.org/images/cloud/buster/) (get the `generic-amd64 version`). Or just use [`Get-DebianImage.ps1`](#Get-DebianImage).

You must use `-RootPassword` to set a password or `-RootPublicKey` to set a public key for default `debian` user.

You may configure network using `-IPAddress`, `-Gateway` and `-DnsAddresses` options. `-IPAddress` must be in `address/prefix` format. If not specified the network will be configured via DHCP.

You may rename interfaces with `-InterfaceName` and `-SecondaryInterfaceName`. This will set Hyper-V network adapter name and also set the interface name in Debian.

You may add a second network using `-SecondarySwitchName`. You may configure it with `-Secondary*` options.

You may configure it as a router using `-EnableRouting` switch. In this case you must inform a second network using `-SecondarySwitchName` (which will be the LAN segment).

You may install Docker using `-InstallDocker` switch.

Returns the `VirtualMachine` created.

**(*) Requires administrative privileges**.



### Usage sample

```powershell
# Create a VM with static IP configuration and ssh public key access
$imgFile = .\Get-DebianImage.ps1 -Verbose
$vmName = 'TstDebian'
$fqdn = 'test.example.com'
$rootPublicKey = Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub"

.\New-VMFromDebianImage.ps1 -SourcePath $imgFile -VMName $vmName -FQDN $fqdn -RootPublicKey $rootPublicKey -VHDXSizeBytes 60GB -MemoryStartupBytes 2GB -ProcessorCount 2 -IPAddress 10.10.1.197/16 -Gateway 10.10.1.250 -DnsAddresses '8.8.8.8','8.8.4.4' -Verbose

# Your public key is installed. This should not ask you for a password.
ssh debian@10.10.1.197
```



## Other commands

### Move-VMOffline

```powershell
Move-VMOffline.ps1 [-VMName] <string> [-DestinationHost] <string> [-CertificateThumbprint] <string> [<CommonParameters>]
```

Uses Hyper-V replica to move a VM between hosts not joined in a domain.
