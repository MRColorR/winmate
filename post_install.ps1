<#
.SYNOPSIS
    Entry point for Windows Post-Install Script
.DESCRIPTION
    Loads modules, ensures admin, executes installation phases, and checks for updates.
#>

param(
    [string]$ConfigPath = "$PSScriptRoot\config.json",
    [string]$LogPath = "$PSScriptRoot\logs\postinstall.log"
)

# Ensure Admin Privileges
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

# Import Importer Module
$ScriptBaseDir = $PSScriptRoot # Define base directory for module paths
. "$ScriptBaseDir\modules\importer.ps1" # Using $ScriptBaseDir for clarity and correctness
Import-ModuleFromFolder -name "logging"
Import-ModuleFromFolder -name "configuration"
Import-ModuleFromFolder -name "providers"
Import-ModuleFromFolder -name "debloat"
Import-ModuleFromFolder -name "fonts"
Import-ModuleFromFolder -name "apps"
Import-ModuleFromFolder -name "settings"
Import-ModuleFromFolder -name "cleanup"
Import-ModuleFromFolder -name "updater"

try {
    Write-Host "DEBUG: post_install.ps1 - About to call Initialize-Logging. Value of \$LogPath is '$LogPath'"
    Initialize-Logging -LogPath $LogPath
    Write-Host "DEBUG: post_install.ps1 - Returned from Initialize-Logging call."
    Write-Host "DEBUG: post_install.ps1 - About to call Write-Log for the first time."
    Write-Log "Windows Post-Installation started" "INFO"

    $config = Get-Configuration -Path $ConfigPath
    Test-Configuration -Config $config

    # Version Check
    if ($config.repo) {
        Check-LatestVersion -Repo $config.repo -Config $config
    } else {
        Write-Log "Repository not defined in config. Skipping version check." "WARNING"
    }

    # Providers
    Ensure-PackageProviders

    # Debloat Phase
    if ($config.steps.debloat.enabled) {
        Write-Log "Running Debloat Phase" "INFO"
        Invoke-WindowsDebloat -Config $config
    }

    # Fonts Phase
    if ($config.steps.fonts.enabled) {
        Write-Log "Running Font Installation Phase" "INFO"
        Install-Fonts -Config $config
    }

    # Applications Phase
    if ($config.steps.apps.enabled) {
        Write-Log "Running Application Installation Phase" "INFO"
        Install-Applications -Config $config
    }

    # Settings Phase
    if ($config.steps.settings.enabled) {
        Write-Log "Running System Settings Phase" "INFO"
        Set-SystemConfiguration -Config $config
    }

    # Cleanup
    Write-Log "Starting Cleanup Phase" "INFO"
    Invoke-Cleanup
    Write-Log "Cleanup Phase Complete" "SUCCESS"

    # Summary
    Show-InstallationSummary

} catch {
    Write-Log "Fatal error occurred: $_" "ERROR"
    Show-InstallationSummary
    exit 1
}

exit 0
