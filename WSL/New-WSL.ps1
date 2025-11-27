<#
.SYNOPSIS
    Creates and configures a new Ubuntu 24.04 WSL instance with cloud-init support.

.DESCRIPTION
    This script automates the creation of a new Ubuntu 24.04 WSL instance by:
    - Downloading the Ubuntu 24.04 WSL image (if not already cached)
    - Configuring cloud-init with custom user data
    - Installing the instance to a specified location
    - Launching the instance for initial setup

.PARAMETER Name
    The name for the new WSL instance. This will be used as both the instance name
    and hostname in the WSL instance.

.PARAMETER Username
    Username for the new WSL user.
    Default: The Windows username to create a matching user in the WSL instance.

.EXAMPLE
    .\New-WSLUbuntu.ps1 -Name "ubuntu-dev"
    Creates a new WSL instance named "ubuntu-dev"

.NOTES
    Requires WSL2 to be installed and enabled on Windows.
    Cloud-init documentation:
    - https://github.com/canonical/cloud-init/blob/main/doc/rtd/reference/datasources/wsl.rst#user-data-configuration
    - https://github.com/ubuntu/WSL/blob/main/docs/tutorials/cloud-init.md
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Username = $env:USERNAME
)

# Set strict error handling
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region Path Configuration
# Template file containing cloud-init configuration with placeholders
$cloudInitConfigTmpl = Join-Path "$PSScriptRoot" '.cloud-init' 'Ubuntu-24.04.user-data.yml'

# Installation directory for this specific WSL instance
$installPath = Join-Path $env:LOCALAPPDATA 'WSL' $Name

# Shared directory for cached WSL images to avoid re-downloading
$imagesPath = Join-Path $env:LOCALAPPDATA 'WSL' '.images'

# Ubuntu 24.04 LTS (Noble Numbat) WSL image download URL
$downloadUrl = 'https://releases.ubuntu.com/noble/ubuntu-24.04.3-wsl-amd64.wsl'

# Local path for the cached Ubuntu image
$imageFile = Join-Path $imagesPath 'ubuntu-24.04.3-wsl-amd64.wsl'
#endregion

#region Prerequisites Validation
Write-Verbose "Checking prerequisites..."

# Verify cloud-init template exists
if (-not (Test-Path $cloudInitConfigTmpl)) {
    throw "Cloud-init template not found at: $cloudInitConfigTmpl"
}

# Check if WSL is available
try {
    $null = wsl --status 2>&1
}
catch {
    throw "WSL is not installed or not available. Please install WSL first."
}
#endregion

#region Directory Setup
# Create user's cloud-init directory if it doesn't exist
# This directory stores cloud-init configuration files
if (-not (Test-Path '~\.cloud-init')) {
    Write-Verbose "Creating cloud-init directory at ~\.cloud-init"
    New-Item -ItemType Directory -Path '~\.cloud-init' | Out-Null
}

# Create images cache directory if it doesn't exist
# This directory stores downloaded WSL images for reuse
if (-not (Test-Path $imagesPath)) {
    Write-Verbose "Creating images cache directory at $imagesPath"
    New-Item -ItemType Directory -Path $imagesPath | Out-Null
}
#endregion

#region Image Download
# Download Ubuntu WSL image if not already cached
if (-not (Test-Path $imageFile)) {
    Write-Host "Downloading Ubuntu 24.04 WSL image from $downloadUrl..." -ForegroundColor Cyan
    Write-Host "This may take several minutes depending on your connection speed." -ForegroundColor Yellow

    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $imageFile -UseBasicParsing
        Write-Host "Download completed successfully." -ForegroundColor Green
    }
    catch {
        throw "Failed to download Ubuntu WSL image: $_"
    }
}
else {
    Write-Verbose "Using cached Ubuntu image at $imageFile"
}
#endregion

#region Cloud-Init Configuration
Write-Verbose "Preparing cloud-init configuration..."

# Load the cloud-init template and replace placeholders with actual values
# __USERNAME__: Windows username, used to create matching user in WSL
# __HOSTNAME__: Instance name, used as the hostname in WSL
try {
    $cloudInitConfig = Get-Content $cloudInitConfigTmpl
    $cloudInitConfig = $cloudInitConfig | ForEach-Object { $_ -replace '__USERNAME__', $Username }
    $cloudInitConfig = $cloudInitConfig | ForEach-Object { $_ -replace '__HOSTNAME__', $Name }
}
catch {
    throw "Failed to process cloud-init template: $_"
}

# Write the processed cloud-init configuration to user's home directory
# WSL will read this file during first boot to configure the system
$cloudInitConfigFile = Join-Path '~\.cloud-init' 'Ubuntu-24.04.user-data'
try {
    $cloudInitConfig | Out-File -FilePath $cloudInitConfigFile -Encoding utf8 -Force
    Write-Verbose "Cloud-init configuration written to $cloudInitConfigFile"
}
catch {
    throw "Failed to write cloud-init configuration: $_"
}
#endregion

#region Instance Installation
# Check if a instance with this name already exists
if (Test-Path $installPath) {
    throw "WSL instance '$Name' is already installed at $installPath. Please choose a different name or remove the existing instance."
}

# Verify the instance name is not already registered with WSL
$existingDistros = wsl --list --quiet | ForEach-Object { $_.Trim() }
if ($existingDistros -contains $Name) {
    throw "A WSL instance named '$Name' is already registered. Please choose a different name."
}

Write-Host "Installing WSL instance '$Name'..." -ForegroundColor Cyan

try {
    # Install the WSL instance from the downloaded image file
    # --from-file: Specifies the WSL image file to install from
    # --name: Sets the instance name
    # --location: Specifies where to install the instance
    # --version 2: Uses WSL2 (required for better performance and features)
    # --no-launch: Prevents automatic launch after installation (we'll launch it manually)
    wsl --install --from-file "$imageFile" --name "$Name" --location "$installPath" --version 2 --no-launch

    if ($LASTEXITCODE -ne 0) {
        throw "WSL installation failed with exit code: $LASTEXITCODE"
    }

    Write-Host "Instance installed successfully." -ForegroundColor Green
}
catch {
    throw "Failed to install WSL instance: $_"
}
#endregion

#region Initial Launch
Write-Host "Launching WSL instance '$Name' for initial setup..." -ForegroundColor Cyan
Write-Host "Cloud-init will configure the system on first boot. This may take a few minutes." -ForegroundColor Yellow

try {
    # Launch the instance for the first time
    # This triggers cloud-init to run and configure the system based on the user-data file
    wsl --distribution "$Name"

    Write-Host "`nWSL instance '$Name' has been successfully created and configured!" -ForegroundColor Green
    Write-Host "You can access it anytime using: wsl -d $Name" -ForegroundColor Cyan
}
catch {
    Write-Warning "Instance was installed but failed to launch: $_"
    Write-Host "You can try launching it manually with: wsl -d $Name" -ForegroundColor Yellow
}
#endregion
