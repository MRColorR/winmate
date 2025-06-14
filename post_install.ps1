<#
.SYNOPSIS
    Entry point for Windows Post-Install Script
.DESCRIPTION
    Loads modules, ensures admin, executes installation phases, and checks for updates.
#>

param(
    [string]$ConfigPath = "$PSScriptRoot\config\config.json",
    [string]$LogPath = "$PSScriptRoot\logs\postinstall.log",
    [string]$GitHubToken = $null
)

# Load GitHub token from config/token.json if not provided as a parameter
if (-not $GitHubToken) {
    $tokenFile = Join-Path $PSScriptRoot 'config/token.json'
    if (Test-Path $tokenFile) {
        try {
            $tokenObj = Get-Content $tokenFile | ConvertFrom-Json
            if ($tokenObj.GitHubToken -and $tokenObj.GitHubToken -ne "") {
                $GitHubToken = $tokenObj.GitHubToken
            }
        }
        catch {
            Write-Host "WARNING: Could not parse config/token.json. Proceeding without GitHub token."
        }
    }
}

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
    if ($config.metadata -and $config.metadata.repo) {
        Check-LatestVersion -Config $config
    }
    else {
        Write-Log "Repository not defined in config. Skipping version check." "WARNING"
    }

    # Debloat Phase
    if ($config.PSObject.Properties.Name -contains 'apps_debloater' -and $null -ne $config.apps_debloater.enabled -and $config.apps_debloater.enabled -eq $true) {
        Write-Log "Running Debloat Phase" "INFO"
        Invoke-WindowsDebloat -Config $config
    }

    # Fonts Phase
    if ($config.PSObject.Properties.Name -contains 'fonts_provisioner' -and $null -ne $config.fonts_provisioner.enabled -and $config.fonts_provisioner.enabled -eq $true) {
        Write-Log "Running Font Installation Phase" "INFO"
        Install-Fonts -Config $config
    }

    # Applications Phase
    if ($config.PSObject.Properties.Name -contains 'apps_provisioner' -and $null -ne $config.apps_provisioner.enabled -and $config.apps_provisioner.enabled -eq $true) {
        if ($GitHubToken) {
            Write-Log "Running Application Installation Phase (GitHub token detected, using authenticated API requests)" "INFO"
        }
        else {
            Write-Log "Running Application Installation Phase (no GitHub token, using unauthenticated API requests)" "INFO"
        }
        Install-Applications -Config $config -GitHubToken $GitHubToken
    }

    # Cleanup
    Write-Log "Starting Cleanup Phase" "INFO"
    Invoke-Cleanup
    Write-Log "Cleanup Phase Complete" "SUCCESS"

    # Summary
    Show-InstallationSummary

}
catch {
    Write-Log "Fatal error occurred: $_" "ERROR"
    Show-InstallationSummary
    exit 1
}

exit 0
