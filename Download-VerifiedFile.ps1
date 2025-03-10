#
# Develop a Windows PowerShell function that downloads a file to a target directory based on a specified URL and SHA-256 hash. 
# The target directory can be specified as a parameter. If not provided, the default location will be $env:TEMP.
# The function should verify whether the file already exists. If the file is not present, it must be downloaded. 
# After downloading, the function must compute the file's SHA-256 hash and compare it to the expected value. If the hashes do not match, an error should be raised. 
# In cases where the file already exists but fails the hash validation, the function must re-download the file and overwrite the existing version.
#
# GitHub Copilot > Claude 3.7 Sonnect (Preview)
#
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$Url,
    
    [Parameter(Mandatory = $true)]
    [string]$ExpectedHash,
    
    [Parameter(Mandatory = $false)]
    [string]$TargetDirectory = $env:TEMP
)

# Ensure target directory exists
if (-not (Test-Path -Path $TargetDirectory -PathType Container)) {
    New-Item -Path $TargetDirectory -ItemType Directory -Force | Out-Null
    Write-Verbose "Created directory: $TargetDirectory"
}

# Extract filename from URL
$fileName = [System.IO.Path]::GetFileName($Url)
$filePath = Join-Path -Path $TargetDirectory -ChildPath $fileName

# Flag to determine if download is needed
$downloadRequired = $true

# Check if file already exists
if (Test-Path -Path $filePath -PathType Leaf) {
    Write-Verbose "File already exists: $filePath. Verifying hash..."
    
    # Calculate hash of existing file
    $fileHash = (Get-FileHash -Path $filePath -Algorithm SHA256).Hash
    
    # Compare hash
    if ($fileHash -eq $ExpectedHash) {
        Write-Verbose "Hash verification successful for existing file."
        $downloadRequired = $false
    }
    else {
        Write-Warning "Existing file hash does not match expected hash. Re-downloading..."
    }
}

# Download file if required
if ($downloadRequired) {
    try {
        Write-Verbose "Downloading $Url to $filePath..."
        Invoke-WebRequest -Uri $Url -OutFile $filePath -UseBasicParsing
        
        # Verify hash of downloaded file
        $fileHash = (Get-FileHash -Path $filePath -Algorithm SHA256).Hash
        
        if ($fileHash -ne $ExpectedHash) {
            Remove-Item -Path $filePath -Force
            throw "Downloaded file hash ($fileHash) does not match expected hash ($ExpectedHash)."
        }
        
        Write-Verbose "Download complete and hash verification successful."
    }
    catch {
        throw "Failed to download or verify file: $_"
    }
}

# Return the file path
return $filePath
