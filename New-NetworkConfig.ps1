[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, ParameterSetName='Dynamic')]
    [Switch]$Dhcp,

    [Parameter(Mandatory=$true, ParameterSetName='Static')]
    [string]$IPAddress,

    [Parameter(Mandatory=$true, ParameterSetName='Static')]
    [string]$PrefixLength,

    [Parameter(Mandatory=$true, ParameterSetName='Static')]
    [string]$DefaultGateway,

    [Parameter(ParameterSetName='Static')]
    [string[]]$DnsAddresses = @('1.1.1.1','1.0.0.1')
)

$ErrorActionPreference = 'Stop'

if ($IPAddress) {
    $sectionEth0 = @"
    addresses: [$IPAddress/$PrefixLength]
    gateway4: $DefaultGateway
    nameservers:
      addresses: [$($DnsAddresses -join ', ')]
"@
} else {
    $sectionEth0 = @"
    dhcp4: true
"@
}

if ($PrefixLength -eq 32) {
    # Workaround for /32 addresses. Netplan won't generate correct routes without this.
    $sectionEth0 += @"

    routes:
      - to: 0.0.0.0/0
        via: $DefaultGateway
        on-link: true
"@
}

$networkConfig = @"
version: 2
ethernets:
  eth0:
$sectionEth0
"@

$networkConfig