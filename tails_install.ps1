# Bugs to fix:
# The script works to download all the items needed to manually perform
# the check and write operation, but the automatic “piping” for Gpg4win
# to check in cli mode and Balena's automatic opening are not working.
# It should also be noted that Balena treats the iso as an MBR and
# therefore only accepts legacy boot mode in the BIOS.

########################################################################
# File Name    : tails_install.ps1
# Description  : This script downloads, checks, and writes Tails from a
#                Windows system to a selected USB device. It includes
#                the installation of BalenaEtcher and Gpg4win.
# Dependencies : PowerShell, Gpg4win, BalenaEtcher Portable
# Usage        : • Open PowerShell with administrative privileges:
#                   - Right-click on the Start menu, and select
#                      'Windows PowerShell (Admin)'
#                • In PowerShell, set the execution policy typing
#                   Set-ExecutionPolicy Bypass -Scope Process -Force
#                • Run the script from the folder where you downloaded
#                  C:\Users\User\Downloads\tails_install.ps1
# Author       : Me and the bois
# License      : Free of charge, no warranty
# Last edited  : 2024-11-09
# Reference    : https://tails.net/install/windows/
########################################################################

# Variables
$tailsBaseUrl = "https://download.tails.net/tails/stable/"
$gpg4winUrl = "https://files.gpg4win.org/gpg4win-4.3.1.exe"
$etcherUrl = "https://tails.net/etcher/balenaEtcher-portable.exe"
$gpg4winPath = "$env:USERPROFILE\Downloads\gpg4win-latest.exe"
$etcherPath = "$env:USERPROFILE\Downloads\balenaEtcher-portable.exe"
$tailsIsoPath = "$env:USERPROFILE\Downloads\tails.iso"
$tailsSigPath = "$env:USERPROFILE\Downloads\tails.iso.sig"
$tailsKeyPath = "$env:USERPROFILE\Downloads\tails-signing.key"
$tailsGpgKeyId = "DBB802B258ACD84F"  # Update this key ID if needed

# Function to download files
function Download-File {
    param (
        [string]$url,
        [string]$outputPath
    )

    Write-Host ("Downloading " + $url + "...")
    try {
        Invoke-WebRequest -Uri $url -OutFile $outputPath -ErrorAction Stop
    } catch {
        Write-Host ("Error downloading " + $url + ": " + $_.Exception.Message)
        exit 1
    }
}

# Function to check if Gpg4win is installed
function Check-Gpg4win {
    return Test-Path $gpg4winPath
}

# Function to check if BalenaEtcher is downloaded
function Check-Etcher {
    return Test-Path $etcherPath
}

# Function to check if GPG is installed
function Check-GPG {
    try {
        & gpg --version | Out-Null
        return $true
    } catch {
        return $false
    }
}

# Function to check if the key is already imported
function Is-Key-Imported {
    param (
        [string]$keyId
    )

    $keyList = & gpg --list-keys $keyId 2>&1
    return $keyList -match $keyId
}

# Function to import and trust GPG key
function Import-And-Trust-Key {
    param (
        [string]$keyPath
    )

    if (-not (Is-Key-Imported -keyId $tailsGpgKeyId)) {
        Write-Host "Importing GPG key..."
        & gpg --import $keyPath 2>&1 | Write-Host
    } else {
        Write-Host "GPG key is already imported."
    }

    Write-Host "Trusting GPG key to ultimate trust..."
    $trustCommand = @"
5
y
"@
    $trustCommand | & gpg --command-fd 0 --edit-key $tailsGpgKeyId trust quit
}

# Fetch the latest Tails version
Write-Host "Fetching the latest Tails version..."
$tailsVersionPage = Invoke-WebRequest -Uri $tailsBaseUrl

# Regex to find Tails version directories (allow multiple decimals)
$regex = [regex] "tails-amd64-(\d+\.\d+(\.\d+)?)/?"
$matches = $regex.Matches($tailsVersionPage.Content)

if ($matches.Count -eq 0) {
    Write-Host "Could not detect the latest version of Tails."
    exit 1
}

# Extract the latest version
$latestVersion = $matches | Sort-Object -Property Value -Descending | Select-Object -First 1 -ExpandProperty Value
$tailsVersion = $latestVersion -replace "tails-amd64-", "" -replace "/", ""
Write-Host ("Latest Tails version detected: " + $tailsVersion)

# Construct URLs for ISO, signature, and key
$tailsIsoUrl = "$tailsBaseUrl$latestVersion/tails-amd64-$tailsVersion.iso"
$tailsSigUrl = "$tailsBaseUrl$latestVersion/tails-amd64-$tailsVersion.iso.sig"
$tailsKeyUrl = "https://tails.net/tails-signing.key"

# Print constructed URLs for verification
Write-Host ("Constructed ISO URL: " + $tailsIsoUrl)
Write-Host ("Constructed Signature URL: " + $tailsSigUrl)

# Download Tails ISO, signature, and signing key
Download-File -url $tailsIsoUrl -outputPath $tailsIsoPath
Download-File -url $tailsSigUrl -outputPath $tailsSigPath
Download-File -url $tailsKeyUrl -outputPath $tailsKeyPath

# Main Script: Install Gpg4win
if (-not (Check-Gpg4win)) {
    Write-Host "Fetching Gpg4win..."
    Download-File -url $gpg4winUrl -outputPath $gpg4winPath
    Write-Host "Installing Gpg4win..."
    Start-Process -FilePath $gpg4winPath -ArgumentList "/VERYSILENT" -Wait -NoNewWindow
    Write-Host "Gpg4win installed successfully."
}

# Install BalenaEtcher
if (-not (Check-Etcher)) {
    Write-Host "Fetching BalenaEtcher..."
    Download-File -url $etcherUrl -outputPath $etcherPath
    Write-Host "BalenaEtcher downloaded successfully."
}

# Check if GPG is installed
if (-not (Check-GPG)) {
    Write-Host "GPG is not installed. Please install GPG manually before proceeding."
    return
}

# Import and Trust Tails GPG Key
Import-And-Trust-Key -keyPath $tailsKeyPath

# Verify Tails ISO Signature
Write-Host "Verifying Tails ISO signature..."
try {
    & gpg --verify $tailsSigPath $tailsIsoPath 2>&1 | Write-Host
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Tails ISO signature verification succeeded."
    } else {
        Write-Host "Tails ISO signature verification failed."
        return
    }
} catch {
    Write-Host "Error verifying Tails ISO signature: " + $_.Exception.Message
    return
}

# Prompt user to use BalenaEtcher GUI
Write-Host "Please open BalenaEtcher and select the following options:"
Write-Host "• Image: $tailsIsoPath"
Write-Host "• Target Drive: Select the correct USB drive in BalenaEtcher"
Write-Host "After selecting these options, click 'Flash!' to write Tails to the USB drive."
$null = Read-Host "Press Enter to open BalenaEtcher..."

# Launch BalenaEtcher
Start-Process -FilePath $etcherPath -NoNewWindow -Wait

# Wait for user input
Write-Host "Press any key to exit the script after you have completed the process."
$null = Read-Host "Press Enter to exit..."
