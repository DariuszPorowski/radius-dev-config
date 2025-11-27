<#
.SYNOPSIS
    Creates or mounts a Windows Dev Drive (ReFS volume optimized for development workloads).

.DESCRIPTION
    This script creates a new virtual hard disk (VHDX) formatted as a Dev Drive, or mounts an existing
    Dev Drive VHDX file. Dev Drives use the ReFS file system with performance optimizations for developer
    scenarios such as build outputs, package caches, and source repositories.

    The script handles three scenarios:
    1. If the VHDX path does not exist: Creates a new dynamic VHDX, mounts it, initializes the disk,
       creates a partition, and formats it as a Dev Drive with ReFS.
    2. If the VHDX exists but is not mounted: Mounts the existing VHDX without re-initializing or formatting.
    3. If the VHDX exists and is already mounted: Throws an error to prevent conflicts.

.PARAMETER Path
    The full path to the VHDX file. If the file does not exist, a new VHDX will be created at this location.
    Default: "$env:USERPROFILE\DevDrive.vhdx"

.PARAMETER Size
    The maximum size of the VHDX file (for new VHDXs only). Accepts standard size units like GB, TB, etc.
    The VHDX is created as a dynamic disk, so it will only consume space as needed up to this limit.
    Default: "100GB"

.PARAMETER DriveLetter
    The drive letter to assign to the volume (e.g., "D", "E"). If not specified or empty, Windows will
    automatically assign the next available drive letter. Only used when creating a new VHDX.
    Default: "" (auto-assign)

.EXAMPLE
    .\New-DevDrive.ps1
    Creates a new 100GB Dev Drive at the default location with an auto-assigned drive letter.

.EXAMPLE
    .\New-DevDrive.ps1 -Path "D:\DevDrives\MyDevDrive.vhdx" -Size 50GB -DriveLetter "R"
    Creates a new 50GB Dev Drive at the specified path and assigns it to drive letter R.

.EXAMPLE
    .\New-DevDrive.ps1 -Path "C:\Existing\DevDrive.vhdx"
    Mounts an existing Dev Drive VHDX file (if not already mounted).

.NOTES
    Requires:
    - Windows 11 or Windows Server with Dev Drive support
    - Administrator privileges (enforced by #Requires statement)
    - Hyper-V module for VHD management cmdlets
#>

#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(
        Mandatory = $false,
        HelpMessage = "Full path to the VHDX file. Will be created if it doesn't exist."
    )]
    [ValidateNotNullOrEmpty()]
    [string]$Path = "$env:USERPROFILE\DevDrive.vhdx",

    [Parameter(
        Mandatory = $false,
        HelpMessage = "Maximum size for new VHDX (e.g., 50GB, 100GB, 1TB). Only used when creating new VHDX."
    )]
    [ValidateNotNullOrEmpty()]
    [ValidatePattern('^\d+\s?(B|KB|MB|GB|TB)$')]
    [string]$Size = "100GB",

    [Parameter(
        Mandatory = $false,
        HelpMessage = "Drive letter to assign (e.g., 'D', 'R'). Leave empty for auto-assignment."
    )]
    [ValidatePattern('^[A-Z]?$')]
    [string]$DriveLetter = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region Helper Functions

function Write-ProgressMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Verbose $Message
    Write-Host "  $Message" -ForegroundColor Cyan
}

#endregion

#region Main Script Logic

try {
    Write-Host "`nDev Drive Setup Script" -ForegroundColor Green
    Write-Host ("=" * 60) -ForegroundColor Green

    # Normalize and validate the path
    $ResolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
    Write-Verbose "Resolved VHDX path: $ResolvedPath"

    # Ensure the parent directory exists
    $ParentDirectory = Split-Path -Path $ResolvedPath -Parent
    if (-not (Test-Path -Path $ParentDirectory -PathType Container)) {
        Write-Verbose "Creating parent directory: $ParentDirectory"
        New-Item -Path $ParentDirectory -ItemType Directory -Force | Out-Null
    }

    $disk = $null
    $isNewVhd = -not (Test-Path -Path $ResolvedPath -PathType Leaf)

    if ($isNewVhd) {
        # Scenario 1: Create new VHDX
        Write-ProgressMessage "Creating new VHDX at: $ResolvedPath"
        Write-ProgressMessage "Size: $Size (dynamic allocation)"

        if ($PSCmdlet.ShouldProcess($ResolvedPath, "Create new VHDX with size $Size")) {
            $vhdx = New-VHD -Path $ResolvedPath -Dynamic -SizeBytes $Size
            Write-Verbose "VHDX created successfully: $($vhdx.Path)"

            Write-ProgressMessage "Mounting VHDX..."
            $disk = $vhdx | Mount-VHD -Passthru
            Write-Verbose "VHDX mounted as Disk Number: $($disk.Number)"

            Write-ProgressMessage "Initializing disk (GPT partition style)..."
            $init = $disk | Initialize-Disk -PartitionStyle GPT -PassThru

            Write-ProgressMessage "Creating partition..."
            $partitionParams = @{
                UseMaximumSize = $true
            }

            if ([string]::IsNullOrWhiteSpace($DriveLetter)) {
                Write-Verbose "No drive letter specified; auto-assigning next available letter"
                $partitionParams.AssignDriveLetter = $true
            }
            else {
                Write-Verbose "Assigning drive letter: $DriveLetter"
                $partitionParams.DriveLetter = $DriveLetter
            }

            $part = $init | New-Partition @partitionParams
            Write-Verbose "Partition created: $($part.DriveLetter):"

            Write-ProgressMessage "Formatting as Dev Drive (ReFS)..."
            $volume = $part | Format-Volume -DevDrive -FileSystem ReFS -NewFileSystemLabel 'DevDrive' -Confirm:$false -Force

            Write-Host "`n  SUCCESS: Dev Drive created and ready!" -ForegroundColor Green
            Write-Host "  Drive Letter: $($volume.DriveLetter):" -ForegroundColor Yellow
            Write-Host "  File System: $($volume.FileSystem)" -ForegroundColor Yellow
            Write-Host "  Size: $($volume.Size / 1GB) GB" -ForegroundColor Yellow
        }
    }
    else {
        # Scenario 2 or 3: VHDX file exists
        Write-ProgressMessage "Existing VHDX found at: $ResolvedPath"

        Write-Verbose "Checking if VHDX is already mounted..."
        $existingVhd = Get-VHD -Path $ResolvedPath

        if ($existingVhd.Attached) {
            # Scenario 3: Already mounted - throw error
            $errorMessage = "The VHDX at '$ResolvedPath' is already attached/mounted.`n" +
            "  Disk Number: $($existingVhd.DiskNumber)`n" +
            "  To avoid conflicts, this script will not proceed.`n" +
            "  Dismount the VHDX first using: Dismount-VHD -Path '$ResolvedPath'"
            throw $errorMessage
        }

        # Scenario 2: Exists but not mounted - mount it
        Write-ProgressMessage "VHDX is not mounted. Mounting now..."

        if ($PSCmdlet.ShouldProcess($ResolvedPath, "Mount existing VHDX")) {
            $disk = $existingVhd | Mount-VHD -Passthru
            Write-Verbose "VHDX mounted successfully as Disk Number: $($disk.Number)"

            # Get volume information
            $volumes = Get-Partition -DiskNumber $disk.Number -ErrorAction SilentlyContinue |
            Get-Volume -ErrorAction SilentlyContinue |
            Where-Object { $null -ne $_.DriveLetter }

            Write-Host "`n  SUCCESS: Existing Dev Drive mounted!" -ForegroundColor Green
            foreach ($vol in $volumes) {
                Write-Host "  Drive Letter: $($vol.DriveLetter):" -ForegroundColor Yellow
                Write-Host "  File System: $($vol.FileSystem)" -ForegroundColor Yellow
                Write-Host "  Size: $([Math]::Round($vol.Size / 1GB, 2)) GB" -ForegroundColor Yellow
            }
        }
    }

    Write-Host "`n" -NoNewline
}
catch {
    Write-Host "`n  ERROR: Failed to create or mount Dev Drive" -ForegroundColor Red
    Write-Host "  Details: $($_.Exception.Message)" -ForegroundColor Red
    Write-Verbose "Full error: $($_ | Out-String)"

    # Attempt cleanup on failure for new VHDs
    if ($isNewVhd -and (Test-Path -Path $ResolvedPath -ErrorAction SilentlyContinue)) {
        Write-Warning "Attempting to clean up partially created VHDX..."
        try {
            Dismount-VHD -Path $ResolvedPath -ErrorAction SilentlyContinue
            Remove-Item -Path $ResolvedPath -Force -ErrorAction SilentlyContinue
            Write-Verbose "Cleanup completed"
        }
        catch {
            Write-Warning "Could not clean up VHDX file. You may need to manually remove: $ResolvedPath"
        }
    }

    throw
}
finally {
    Write-Verbose "Script execution completed"
}

#endregion
