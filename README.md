# Hyper-V automation scripts

Collection of Powershell scripts to create Windows and Ubuntu VMs in Hyper-V.

For Windows Server 2016 / Hyper-V Server 2016 / Windows 10 / 8.1 only.

For Hyper-V Generation 2 VMs only.



## For Windows VMs

### New-WindowsUnattendFile

```
New-WindowsUnattendFile.ps1 [-AdministratorPassword] <string> [-Version] <string> [[-ComputerName] <string>] [[-FilePath] <string>] [[-Locale] <string>] [<CommonParameters>]
```

Creates an `unattend.xml` file to initialize a Windows VM. Used by `New-VMFromWindowsImage`.

Returns the full path of created file.



### New-VMFromWindowsImage (*)

```
New-VMFromWindowsImage.ps1 [-SourcePath] <string> [-Edition] <string> [-VMName] <string> [-VHDXSizeBytes] <uint64> [-AdministratorPassword] <string> [-Version] <string> [-MemoryStartupBytes] <long> [[-VMProcessorCount] <long>] [[-VMSwitchName] <string>] [[-Locale] <string>] [-EnableDynamicMemory] [<CommonParameters>]
```

Creates a Windows VM from .ISO image. 

For the `-Edition` parameter use `Get-WindowsImage -ImagePath <path-to-install.wim>` to see all available images. Or just use "1" for the first one.

The `-Version` parameter is needed to set the product key (required for a full unattended install).

Returns the `VirtualMachine` created.

**(*) Requires administrative privileges**.



### New-VMSession

```
New-VMSession.ps1 [-VMName] <string> [-AdministratorPassword] <string> [<CommonParameters>]
```

Creates a new `PSSession` into a VM.

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
$pass = 'a*e3JHrUq!cMm&'

.\New-VMFromWindowsImage.ps1 -SourcePath $isoFile -Edition 'ServerStandardCore' -VMName $vmName -VHDXSizeBytes 60GB -AdministratorPassword $pass -Version 'Server2016Standard' -MemoryStartupBytes 2GB -VMProcessorCount 2

$sess = .\New-VMSession.ps1 -VMName $vmName -AdministratorPassword $pass

.\Set-NetIPAddressViaSession.ps1 -Session $sess -IPAddress 10.10.1.195 -PrefixLength 16 -DefaultGateway 10.10.1.250 -DnsAddresses '8.8.8.8','8.8.4.4' -NetworkCategory 'Public'

.\Enable-RemoteManagementViaSession.ps1 -Session $sess

Remove-PSSession -Session $sess
```



## For Ubuntu VMs

### New-NetworkConfig.ps1

```
New-NetworkConfig.ps1 -Dhcp [<CommonParameters>]
New-NetworkConfig.ps1 -IPAddress <string> -PrefixLength <string> -DefaultGateway <string> [-DnsAddresses <string[]>] [<CommonParameters>]
```

Creates a `network-config` file to initialize a Ubuntu VM. Used by `New-VMFromUbuntuImage`.

Returns the content of generated file as string.



### New-VMFromUbuntuImage (*)

```
New-VMFromUbuntuImage.ps1 -SourcePath <string> -VMName <string> -RootPassword <string> [-FQDN <string>] [-VHDXSizeBytes <uint64>] [-MemoryStartupBytes <long>] [-VMProcessorCount <long>] [-VMSwitchName <string>] [-NetworkConfig <string>] [<CommonParameters>]
New-VMFromUbuntuImage.ps1 -SourcePath <string> -VMName <string> -UserName <string> -UserPublicKey <string> [-FQDN <string>] [-VHDXSizeBytes <uint64>] [-MemoryStartupBytes <long>] [-VMProcessorCount <long>] [-VMSwitchName <string>] [-NetworkConfig <string>] [<CommonParameters>]
```

Creates a Ubuntu VM from Ubuntu Cloud image. For Ubuntu 16.04 LTS only.

You will need [qemu-img](https://cloudbase.it/qemu-img-windows/) installed. If you have [chocolatey](https://chocolatey.org/) you can install it with:

```
choco install qemu-img -y
```

You can download Ubuntu cloud images from [here](https://cloud-images.ubuntu.com/releases/16.04/release/) (get the AMD64 UEFI version).

You may use `-RootPassword` to set a root password (for the default `ubuntu` user) or use `-UserName` and `-UserPublicKey` to create a new user and its public key.

For the `-NetworkConfig` parameter you may pass a `network-config` content. If not specified the network will be set up via DHCP. 

You can read the documentation for `network-config` [here](http://cloudinit.readthedocs.io/en/latest/topics/network-config-format-v1.html). For Ubuntu 16.04 you must use the version 1.

Alternatively, you may use `New-NetworkConfig.ps1` to create a file with basic network settings.

Returns the `VirtualMachine` created.

**(*) Requires administrative privileges**.



### Usage sample

```powershell
$imgFile = '.\ubuntu-16.04-server-cloudimg-amd64-uefi1.img'
$vmName = 'test'
$fqdn = 'test.example.com'
$userName = 'admin'
$userPublicKey = Get-Content "$env:USERPROFILE\.ssh\id_rsa.pub"

$netConfig = .\New-NetworkConfig.ps1 -IPAddress 10.10.1.195 -PrefixLength 16 -DefaultGateway 10.10.1.250 -DnsAddresses '8.8.8.8','8.8.4.4'

.\New-VMFromUbuntuImage.ps1 -SourcePath $imgFile -VMName $vmName -FQDN $fqdn -UserName $userName -UserPublicKey -VHDXSizeBytes 60GB -MemoryStartupBytes 2GB -VMProcessorCount 2 -NetworkConfig $netConfig

ssh admin@10.10.1.195
```



## For all VMs

## Move-VMOffline

```
Move-VMOffline.ps1 [-VMName] <string> [-DestinationHost] <string> [-CertificateThumbprint] <string> [<CommonParameters>]
```

Uses Hyper-V replica to move a VM between hosts not joined in a domain.
