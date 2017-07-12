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
    [string[]]$DnsAddresses = @('8.8.8.8','8.8.4.4')
)

$ErrorActionPreference = 'Stop'

if ($IPAddress) {
    if ($DnsAddresses) {
        $sep = "`n          - "
        $sectionDnsNameServers = 'dns_nameservers:' + $sep + ($DnsAddresses -join $sep)
    }

    $sectionSubnets = @"
      - type: static
        address: $IPAddress/$PrefixLength
        gateway: $DefaultGateway
        $sectionDnsNameServers
"@
    } else {
        $sectionSubnets = @"
      - type: dhcp
"@
    }

$networkConfig = @"
version: 1
config:
  - type: physical
    name: eth0
    subnets:
$sectionSubnets
"@

$networkConfig