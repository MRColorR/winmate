<#
.SYNOPSIS
    Entry point for Windows Post-Install Script
.DESCRIPTION
    Loads modules, ensures admin, executes installation phases, and checks for updates.
#>

param(
    [string]$ConfigPath = "$PSScriptRoot\config\config.json",
    [string]$LogPath = "$PSScriptRoot\logs\postinstall.log"
)

$ScriptBaseDir = $PSScriptRoot # Define base directory for module paths

# Ensure Admin Privileges
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

# New Module Import Mechanism
Write-Host "DEBUG: post_install.ps1 - Importing modules..."
Import-Module "$ScriptBaseDir\modules\logging.psm1"
Import-Module "$ScriptBaseDir\modules\configuration.psm1"
Import-Module "$ScriptBaseDir\modules\providers.psm1"
Import-Module "$ScriptBaseDir\modules\debloat.psm1"
Import-Module "$ScriptBaseDir\modules\fonts.psm1"
Import-Module "$ScriptBaseDir\modules\apps.psm1"
Import-Module "$ScriptBaseDir\modules\cleanup.psm1"
Import-Module "$ScriptBaseDir\modules\updater.psm1"
Write-Host "DEBUG: post_install.ps1 - All modules imported."

try {
    # The debug lines below were added in a previous subtask.
    Write-Host "DEBUG: post_install.ps1 - About to call Initialize-Logging. Value of \$LogPath is '$LogPath'"
    Initialize-Logging -LogPath $LogPath
    Write-Host "DEBUG: post_install.ps1 - Returned from Initialize-Logging call."
    Write-Host "DEBUG: post_install.ps1 - About to call Write-Log for the first time."
    Write-Log "Windows Post-Installation started" "INFO"

    $config = Get-Configuration -Path $ConfigPath
    Test-Configuration -Config $config

    # Version Check
    if ($config.repo) {
        Check-LatestVersion -Repo $config.repo
    } else {
        Write-Log "Repository not defined in config. Skipping version check." "WARNING"
    }

    # Providers
    Ensure-PackageProviders

    # Debloat Phase
    if ($config.PSObject.Properties.Name -contains 'debloat' -and $null -ne $config.debloat.enabled -and $config.debloat.enabled -eq $true) {
        Write-Log "Running Debloat Phase" "INFO"
        Invoke-WindowsDebloat -Config $config
    }

    # Fonts Phase
    if ($config.PSObject.Properties.Name -contains 'fonts' -and $null -ne $config.fonts.enabled -and $config.fonts.enabled -eq $true) {
        Write-Log "Running Font Installation Phase" "INFO"
        Install-Fonts -Config $config
    }

    # Applications Phase
    if ($config.PSObject.Properties.Name -contains 'apps' -and $null -ne $config.apps.enabled -and $config.apps.enabled -eq $true) {
        Write-Log "Running Application Installation Phase" "INFO"
        Install-Applications -Config $config
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
