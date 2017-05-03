[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [System.Management.Automation.Runspaces.PSSession[]]$Session
)

$ErrorActionPreference = 'Stop'

Invoke-Command -Session $Session { 
    # Enable remote administration
    Enable-PSRemoting -SkipNetworkProfileCheck -Force
    Enable-WSManCredSSP -Role server -Force

    # Default rule is for 'Local Subnet' only. Change to 'Any'.
    Set-NetFirewallRule -DisplayName 'Windows Remote Management (HTTP-In)' -RemoteAddress Any
} | Out-Null
