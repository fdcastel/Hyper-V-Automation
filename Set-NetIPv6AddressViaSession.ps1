[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [System.Management.Automation.Runspaces.PSSession[]]$Session,

    [string]$AdapterName,

    [ValidateScript({
        if ($_.AddressFamily -ne 'InterNetworkV6') {
            throw 'IPAddress must be an IPv6 address.'
        }
        $true
    })]
    [Parameter(Mandatory=$true)]
    [ipaddress]$IPAddress,

    [Parameter(Mandatory=$true)]
    [byte]$PrefixLength,
    
    [string[]]$DnsAddresses = @('2001:4860:4860::8888','2001:4860:4860::8844')
)

$ErrorActionPreference = 'Stop'

Invoke-Command -Session $Session { 
    $ifName = $using:AdapterName

    if (-not $ifName) {
        # Get the gateway interface for IPv4
        $ifName = (Get-NetIPConfiguration | Foreach IPv4DefaultGateway).InterfaceAlias
    }

    $neta = Get-NetAdapter -Name $ifName
    $neta | Get-NetIPAddress -AddressFamily IPv6 -PrefixOrigin Manual -ErrorAction SilentlyContinue | Remove-NetIPAddress -Confirm:$false 
    $neta | New-NetIPAddress -AddressFamily IPv6 -IPAddress $using:IPAddress -PrefixLength $using:PrefixLength

    $neta | Set-DnsClientServerAddress -Addresses $using:DnsAddresses
} | Out-Null
