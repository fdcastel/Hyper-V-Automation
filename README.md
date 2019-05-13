# Hyper-V automation scripts

Collection of Powershell scripts to create Windows and Ubuntu VMs in Hyper-V.

For Windows Server 2016 / Hyper-V Server 2016 / Windows 10 / 8.1 only.

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
    - [New-VMSession](#New-VMSession)
    - [Set-NetIPAddressViaSession](#Set-NetIPAddressViaSession)
    - [Enable-RemoteManagementViaSession](#Enable-RemoteManagementViaSession)
  - For Ubuntu VMs
    - [Get-UbuntuImage](#Get-UbuntuImage)
    - [New-VMFromUbuntuImage](#New-VMFromUbuntuImage-) (*)
  - For any VMs
    - [Move-VMOffline](#move-vmoffline)

**(*) Requires administrative privileges**.



## For Windows VMs

### New-WindowsUnattendFile

```
New-WindowsUnattendFile.ps1 [-AdministratorPassword] <string> [-Version] <string> [[-ComputerName] <string>] [[-FilePath] <string>] [[-Locale] <string>] [<CommonParameters>]
```

Creates an `unattend.xml` file to initialize a Windows VM. Used by `New-VMFromWindowsImage`.

Returns the full path of created file.



### New-VMFromWindowsImage (*)

```
New-VMFromWindowsImage.ps1 [-SourcePath] <string> [-Edition] <string> [-VMName] <string> [-VHDXSizeBytes] <uint64> [-AdministratorPassword] <string> [-Version] <string> [-MemoryStartupBytes] <long> [[-VMProcessorCount] <long>] [[-VMSwitchName] <string>] [[-VMMacAddress] <string>] [[-Locale] <string>] [-EnableDynamicMemory] [<CommonParameters>]
```

Creates a Windows VM from .ISO image. 

For the `-Edition` parameter use `Get-WindowsImage -ImagePath <path-to-install.wim>` to see all available images. Or just use "1" for the first one.

The `-Version` parameter is required to set the product key (required for a full unattended install).

Returns the `VirtualMachine` created.

**(*) Requires administrative privileges**.



### New-VMSession

```
New-VMSession.ps1 [-VMName] <string> [-AdministratorPassword] <string> [[-DomainName] <string>] [<CommonParameters>]
```

Creates a new `PSSession` into a VM. In case of error, keeps retrying until connected.

Returns the `PSSession` created.



### Set-NetIPAddressViaSession

```
Set-NetIPAddressViaSession.ps1 [-Session] <PSSession[]> [-IPAddress] <string> [-PrefixLength] <byte> [-DefaultGateway] <string> [[-DnsAddresses] <string[]>] [[-NetworkCategory] <string>] [<CommonParameters>]
```

Sets TCP/IP configuration for a VM.



### Enable-RemoteManagementViaSession

```
Enable-RemoteManagementViaSession.ps1 [-Session] <PSSession[]> [<CommonParameters>]
```

Enables Powershell Remoting, CredSSP server authentication and sets WinRM firewall rule to `Any` remote address (default: `LocalSubnet`).



### Usage sample

```powershell
$isoFile = '.\14393.0.160715-1616.RS1_RELEASE_SERVER_EVAL_X64FRE_EN-US.ISO'
$vmName = 'test'
$pass = 'u531@rg3pa55w0rd$!'

.\New-VMFromWindowsImage.ps1 -SourcePath $isoFile -Edition 'ServerStandardCore' -VMName $vmName -VHDXSizeBytes 60GB -AdministratorPassword $pass -Version 'Server2016Standard' -MemoryStartupBytes 2GB -VMProcessorCount 2

$sess = .\New-VMSession.ps1 -VMName $vmName -AdministratorPassword $pass

.\Set-NetIPAddressViaSession.ps1 -Session $sess -IPAddress 10.10.1.195 -PrefixLength 16 -DefaultGateway 10.10.1.250 -DnsAddresses '8.8.8.8','8.8.4.4' -NetworkCategory 'Public'

.\Enable-RemoteManagementViaSession.ps1 -Session $sess

Remove-PSSession -Session $sess
```



## For Ubuntu VMs

### Get-UbuntuImage

```
Get-UbuntuImage.ps1 [[-OutputPath] <string>] [<CommonParameters>]
```

Downloads latest Ubuntu 18.04 LTS cloud image and verify its integrity.

Use `-OutputPath` parameter to set download location. If not informed, the current folder will be used.

Returns the path for downloaded file.



### New-VMFromUbuntuImage (*)

```
New-VMFromUbuntuImage.ps1 -SourcePath <string> -VMName <string> -RootPassword <string> -EnableRouting -SecondarySwitchName <string> [-FQDN <string>] [-VHDXSizeBytes <uint64>] [-MemoryStartupBytes <long>] [-EnableDynamicMemory] [-ProcessorCount <long>] [-SwitchName <string>] [-MacAddress <string>] [-IPAddress <string>] [-Gateway <string>] [-DnsAddresses <string[]>] [-InterfaceName <string>] [-SecondaryMacAddress <string>] [-SecondaryIPAddress <string>] [-SecondaryInterfaceName <string>] [-LoopbackIPAddress <string>] [-InstallDocker] [<CommonParameters>]

New-VMFromUbuntuImage.ps1 -SourcePath <string> -VMName <string> -RootPassword <string> [-FQDN <string>] [-VHDXSizeBytes <uint64>] [-MemoryStartupBytes <long>] [-EnableDynamicMemory] [-ProcessorCount <long>] [-SwitchName <string>] [-MacAddress <string>] [-IPAddress <string>] [-Gateway <string>] [-DnsAddresses <string[]>] [-InterfaceName <string>] [-EnableRouting] [-SecondarySwitchName <string>] [-SecondaryMacAddress <string>] [-SecondaryIPAddress <string>] [-SecondaryInterfaceName <string>] [-LoopbackIPAddress <string>] [-InstallDocker] [<CommonParameters>]

New-VMFromUbuntuImage.ps1 -SourcePath <string> -VMName <string> -RootPublicKey <string> -EnableRouting -SecondarySwitchName <string> [-FQDN <string>] [-VHDXSizeBytes <uint64>] [-MemoryStartupBytes <long>] [-EnableDynamicMemory] [-ProcessorCount <long>] [-SwitchName <string>] [-MacAddress <string>] [-IPAddress <string>] [-Gateway <string>] [-DnsAddresses <string[]>] [-InterfaceName <string>] [-SecondaryMacAddress <string>] [-SecondaryIPAddress <string>] [-SecondaryInterfaceName <string>] [-LoopbackIPAddress <string>] [-InstallDocker] [<CommonParameters>]

New-VMFromUbuntuImage.ps1 -SourcePath <string> -VMName <string> -RootPublicKey <string> [-FQDN <string>] [-VHDXSizeBytes <uint64>] [-MemoryStartupBytes <long>] [-EnableDynamicMemory] [-ProcessorCount <long>] [-SwitchName <string>] [-MacAddress <string>] [-IPAddress <string>] [-Gateway <string>] [-DnsAddresses <string[]>] [-InterfaceName <string>] [-EnableRouting] [-SecondarySwitchName <string>] [-SecondaryMacAddress <string>] [-SecondaryIPAddress <string>] [-SecondaryInterfaceName <string>] [-LoopbackIPAddress <string>] [-InstallDocker] [<CommonParameters>]
```

Creates a Ubuntu VM from Ubuntu Cloud image. For Ubuntu 18.04 LTS only.

You must have [qemu-img](https://cloudbase.it/qemu-img-windows/) installed. If you have [chocolatey](https://chocolatey.org/) you can install it with:

```
choco install qemu-img -y
```

You can download Ubuntu cloud images from [here](https://cloud-images.ubuntu.com/releases/18.04/release/) (get the AMD64 IMG version). Or just use `Get-UbuntuImage.ps1`.

You must use `-RootPassword` to set a password or `-RootPublicKey` to set a public key for default `ubuntu` user.

You may configure network using `-IPAddress`, `-Gateway` and `-DnsAddresses` options. `-IPAddress` must be in `address/prefix` format. If not specified the network will be configured via DHCP.

You may rename interfaces with `-InterfaceName` and `-SecondaryInterfaceName`. This will set Hyper-V network adapter name and also set the interface name in Ubuntu.

You may add a second network using `-SecondarySwitchName`. You may configure it with `-Secondary*` options.

You may configure it as a router using `-EnableRouting` switch. In this case you must inform a second network using `-SecondarySwitchName` (which will be the LAN segment).

You may install Docker using `-InstallDocker` switch.

Returns the `VirtualMachine` created.

**(*) Requires administrative privileges**.



### Usage samples

```powershell
# Create a VM with static IP configuration and ssh public key access
$imgFile = '.\ubuntu-18.04-server-cloudimg-amd64.img'
$vmName = 'test'
$fqdn = 'test.example.com'
$rootPublicKey = Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub"

.\New-VMFromUbuntuImage.ps1 -SourcePath $imgFile -VMName $vmName -FQDN $fqdn -RootPublicKey $rootPublicKey -VHDXSizeBytes 60GB -MemoryStartupBytes 2GB -ProcessorCount 2 -IPAddress 10.10.1.195/16 -Gateway 10.10.1.250 -DnsAddresses '8.8.8.8','8.8.4.4' -Verbose

ssh ubuntu@10.10.1.195
```


## For any VMs

### Move-VMOffline

```
Move-VMOffline.ps1 [-VMName] <string> [-DestinationHost] <string> [-CertificateThumbprint] <string> [<CommonParameters>]
```

Uses Hyper-V replica to move a VM between hosts not joined in a domain.
