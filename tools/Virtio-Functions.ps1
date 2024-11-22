#
# Functions for working with Virtio drivers in Windows images.
#

# All drivers installed by virtio-win-gt-x64.msi.
$InstallerVirtioDrivers = @(
    'Balloon',
    'fwcfg',
    'NetKVM',
    'pvpanic',
    'qemupciserial',
    'viofs',
    'viogpudo',
    'vioinput',
    'viomem',
    'viorng',
    'vioscsi',
    'vioserial',
    'viostor'
)

function Get-VirtioDriverFolderName([string]$Version)
{
    $folder = switch ($Version) {
        'Server2025Datacenter'  {'2k25'}
        'Server2025Standard'    {'2k25'}
        'Server2022Datacenter'  {'2k22'}
        'Server2022Standard'    {'2k22'}
        'Server2019Datacenter'  {'2k19'}
        'Server2019Standard'    {'2k19'}
        'Server2016Datacenter'  {'2k16'}
        'Server2016Standard'    {'2k16'}
        'Windows11Enterprise'   {'w11'}
        'Windows11Professional' {'w11'}
        'Windows10Enterprise'   {'w10'}
        'Windows10Professional' {'w10'}
        'Windows81Professional' {'w8.1'}
        default {'2k25'}
    }
    return $folder
}

function Get-VirtioDrivers([string]$VirtioDriveLetter, [string]$Version)
{
    $virtioInstaller = "$($virtioDriveLetter):\virtio-win-gt-x64.msi"
    $exists = Test-Path $virtioInstaller
    if (-not $exists)
    {
        throw "The specified ISO does not appear to be a valid Virtio installation media."
    }

    $folder = Get-VirtioDriverFolderName $Version

    # All AMD64 drivers for the specified Windows version
    $allDrivers = Get-ChildItem "$($VirtioDriveLetter):\*\$folder\amd64\*.inf" 
    
    # Just the drivers installed by virtio-win-gt-x64.msi
    $filteredDrivers = $allDrivers | Where-Object { 
        $_.Directory.Parent.Parent.BaseName -in $InstallerVirtioDrivers
    }

    return $filteredDrivers.Directory.FullName
}

function With-IsoImage([string]$IsoFileName, [scriptblock]$ScriptBlock)
{
    $IsoFileName = (Resolve-Path $IsoFileName).Path

    Write-Verbose "Mounting '$IsoFileName'..."
    $mountedImage = Mount-DiskImage -ImagePath $IsoFileName -StorageType ISO -PassThru
    try 
    {
        $driveLetter = ($mountedImage | Get-Volume).DriveLetter
        Invoke-Command $ScriptBlock -ArgumentList $driveLetter
    }
    finally
    {
        Write-Verbose "Dismounting '$IsoFileName'..."
        Dismount-DiskImage -ImagePath $IsoFileName | Out-Null
    }
}

function With-WindowsImage([string]$ImagePath, [int]$ImageIndex, [string]$VirtioDriveLetter, [scriptblock]$ScriptBlock)
{
    $mountPath = Join-Path ([System.IO.Path]::GetTempPath()) "winmount\"

    Write-Verbose "Mounting '$ImagePath' ($ImageIndex)..."
    mkdir $mountPath -Force | Out-Null
    Mount-WindowsImage -Path $mountPath -ImagePath $ImagePath -Index $ImageIndex | Out-Null
    try
    {
        Invoke-Command $ScriptBlock -ArgumentList $mountPath
    }
    finally
    {
        Write-Verbose "Dismounting '$ImagePath' ($ImageIndex)..."
        Dismount-WindowsImage -Path $mountPath -Save | Out-Null
    }
}
