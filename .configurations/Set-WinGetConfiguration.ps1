<#
.SYNOPSIS
Validates and applies the yaml winget configuration to a Windows machine.

.DESCRIPTION
This script validates the winget configuration using winget's built-in validation capability, it runs any manual
installers required because of gaps or bugs in winget or DSC packages, and it applies the yaml configuration.
Admin rights are required to run this script because the Visual Studio 2022 configuration command will fail without
admin access instead of initiating a UAC prompt.

.PARAMETER YamlConfigFilePath
File path to the yaml configuration file to be applied by winget.

.EXAMPLE
Set-WinGetConfiguration.ps1 -YamlConfigFilePath ".\radius.dsc.yaml"
#>

#Requires -RunAsAdministrator

param (
    [string]$YamlConfigFilePath = "$PSScriptRoot\radius.dsc.yaml",

    [bool]$ValidateFirst = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Check for WinGet
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Error "WinGet is not installed."
}

winget configure --enable

if ($ValidateFirst) {
    Write-Host "Validating WinGet configuration..."
    winget configure validate --file $YamlConfigFilePath --disable-interactivity
}

Write-Host "Starting WinGet configuration from $YamlConfigFilePath..."
winget configure --file $YamlConfigFilePath --accept-configuration-agreements --disable-interactivity

Write-Host "WinGet configuration complete. A reboot may be required to finish setting up WSL and Docker Desktop."
