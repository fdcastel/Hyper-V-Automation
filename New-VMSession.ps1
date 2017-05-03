[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$VMName,

    [Parameter(Mandatory=$true)]
    [string]$AdministratorPassword
)

$ErrorActionPreference = 'Stop'

$pass = ConvertTo-SecureString $AdministratorPassword -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('administrator', $pass)
New-PSSession -VMName $VMName -Credential $cred
