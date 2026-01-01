[CmdletBinding()]
param(
    [string]$AdapterName = 'Ethernet',

    [Parameter(Mandatory=$true)]
    [string]$IPAddress,

    [Parameter(Mandatory=$true)]
    [byte]$PrefixLength,
    
    [Parameter(Mandatory=$true)]
    [string]$DefaultGateway,
    
    [string[]]$DnsAddresses = @('8.8.8.8','8.8.4.4'),

    [ValidateSet('Public', 'Private')]
    [string]$NetworkCategory = 'Public'
)

$ErrorActionPreference = 'Stop'

Remove-NetRoute -NextHop $DefaultGateway -Confirm:$false -ErrorAction SilentlyContinue
$neta = Get-NetAdapter $AdapterName        # Use the exact adapter name for multi-adapter VMs
$neta | Set-NetConnectionProfile -NetworkCategory $NetworkCategory
$neta | Set-NetIPInterface -Dhcp Disabled
$neta | Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false 

# New-NetIPAddress may fail for certain scenarios (e.g. PrefixLength = 32). Using netsh instead.
$mask = [IPAddress](([UInt32]::MaxValue) -shl (32 - $PrefixLength) -shr (32 - $PrefixLength))
netsh interface ipv4 set address name="$($neta.InterfaceAlias)" static $IPAddress $mask.IPAddressToString $DefaultGateway

$neta | Set-DnsClientServerAddress -Addresses $DnsAddresses
