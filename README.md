# Hyper-V automation scripts

Collection of Powershell scripts to create Windows VMs in Hyper-V.

For Windows Server 2016 / Hyper-V Server 2016 / Windows 10 only.

For Hyper-V Generation 2 VMs only.



## New-WindowsUnattendFile

```
New-WindowsUnattendFile.ps1 [-AdministratorPassword] <string> [-Version] <string> [[-ComputerName] <string>] [[-FilePath] <string>] [[-Locale] <string>] [<CommonParameters>]
```

Creates an `unattend.xml` file to initialize a Windows VM. Used by `New-VMFromWindowsImage`.

Returns the full path of created file.



## New-VMFromWindowsImage (*)

```
New-VMFromWindowsImage.ps1 [-SourcePath] <string> [-Edition] <string> [-VMName] <string> [-VHDXSizeBytes] <uint64> [-AdministratorPassword] <string> [-Version] <string> [-MemoryStartupBytes] <long> [[-VMProcessorCount] <long>] [[-VMSwitchName] <string>] [[-Locale] <string>] [<CommonParameters>]
```

Creates a Windows VM from .ISO image. 

For the -Edition parameter use `Get-WindowsImage -ImagePath <path-to-install.wim>` to see all available images. Or just use "1" for the first one.

The -Version parameter is needed to set the product key (required for a full unattended install).

Returns the `VirtualMachine` created.

**(*) Requires administrative privileges**.



## New-VMSession

```
New-VMSession.ps1 [-VMName] <string> [-AdministratorPassword] <string> [<CommonParameters>]
```

Creates a new `PSSession` into a VM.

Returns the `PSSession` created.



## Set-NetIPAddressViaSession

```
Set-NetIPAddressViaSession.ps1 [-Session] <PSSession[]> [-IPAddress] <string> [-PrefixLength] <byte> [-DefaultGateway] <string> [[-DnsAddresses] <string[]>] [[-NetworkCategory] <string>] [<CommonParameters>]
```

Sets TCP/IP configuration for a VM.



## Enable-RemoteManagementViaSession

```
Enable-RemoteManagementViaSession.ps1 [-Session] <PSSession[]> [<CommonParameters>]
```

Enables Powershell Remoting, CredSSP server authentication and sets WinRM firewall rule to `Any` remote address (default: `LocalSubnet`).



## Move-VMOffline

```
Move-VMOffline.ps1 [-VMName] <string> [-DestinationHost] <string> [-CertificateThumbprint] <string> [<CommonParameters>]
```

Uses Hyper-V replica to move a VM between hosts not joined in a domain.



## Usage sample

```powershell
$isoFile = '.\14393.0.160715-1616.RS1_RELEASE_SERVER_EVAL_X64FRE_EN-US.ISO'
$vmName = 'test'
$pass = 'P@ssw0rd'

.\New-VMFromWindowsImage.ps1 -SourcePath $isoFile -Edition 'ServerStandardCore' -VMName $vmName -VHDXSizeBytes 60GB -AdministratorPassword $pass -Version 'Server2016Standard' -MemoryStartupBytes 2GB -VMProcessorCount 2

$sess = .\New-VMSession.ps1 -VMName $vmName -AdministratorPassword $pass

.\Set-NetIPAddressViaSession.ps1 -Session $sess -IPAddress 10.10.1.195 -PrefixLength 16 -DefaultGateway 10.10.1.250 -DnsAddresses '8.8.8.8','8.8.4.4' -NetworkCategory 'Public'

.\Enable-RemoteManagementViaSession.ps1 -Session $sess

Remove-PSSession -Session $sess
```
