#
# Functions for working with Virtio drivers in Windows images.
#

function Get-VirtioDrivers($VirtioDriveLetter)
{
    $virtioInstaller = "$($virtioDriveLetter):\virtio-win-gt-x64.msi"
    $exists = Test-Path $virtioInstaller
    if (-not $exists)
    {
        throw "The specified ISO does not appear to be a valid Virtio installation media."
    }

    return @(
        "$($VirtioDriveLetter):\vioscsi\w10\amd64",
        "$($VirtioDriveLetter):\NetKVM\w10\amd64",
        "$($VirtioDriveLetter):\Balloon\w10\amd64"
    )
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
