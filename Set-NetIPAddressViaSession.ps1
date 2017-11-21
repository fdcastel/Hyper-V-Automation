[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [System.Management.Automation.Runspaces.PSSession[]]$Session,

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

Invoke-Command -Session $Session { 
    Remove-NetRoute -NextHop $using:DefaultGateway -Confirm:$false -ErrorAction SilentlyContinue
    $neta = Get-NetAdapter 'Ethernet'        # Use the exact adapter name for multi-adapter VMs
    $neta | Set-NetConnectionProfile -NetworkCategory $using:NetworkCategory
    $neta | Set-NetIPInterface -Dhcp Disabled
    $neta | Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false 
    $neta | New-NetIPAddress -IPAddress $using:IPAddress -PrefixLength $using:PrefixLength -DefaultGateway $using:DefaultGateway
    $neta | Set-DnsClientServerAddress -Addresses $using:DnsAddresses
} | Out-Null
