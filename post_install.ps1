<#
.SYNOPSIS
    Automates Windows post-installation setup including debloating, font installation,
    and application provisioning.
.DESCRIPTION
    This script is the main entry point for the Windows post-installation automation framework.
    It orchestrates the entire setup process based on a user-provided or default JSON configuration file.
    Key operations include:
    - Loading a GitHub Personal Access Token (PAT) if available (from parameter or 'config/token.json').
    - Ensuring the script is run with Administrator privileges; attempts to relaunch if not.
    - Importing all necessary PowerShell modules from the './modules' directory.
    - Initializing the logging system.
    - Loading and validating the main configuration file.
    - Optionally checking for a newer version of the script/configuration on GitHub.
    - Executing distinct phases based on configuration:
        - Windows Debloating: Removes specified applications.
        - Font Installation: Installs specified Nerd Fonts and custom fonts.
        - Application Provisioning: Installs applications using providers like Winget, Chocolatey, Scoop, etc.
    - Performing cleanup operations.
    - Displaying a comprehensive summary of all operations, including per-phase statistics.

    The script is designed to be modular and configurable, with detailed logging for traceability and debugging.
.PARAMETER ConfigPath
    Specifies the path to the JSON configuration file that dictates the script's behavior.
    Defaults to '$PSScriptRoot\config\config.json'.
.PARAMETER LogPath
    Specifies the path for the main log file where all operations and their outcomes will be recorded.
    Defaults to '$PSScriptRoot\logs\postinstall.log'.
.PARAMETER GitHubToken
    Optional. A GitHub Personal Access Token (PAT). This token is used for authenticated requests
    to the GitHub API, which is relevant for:
    - The version update check ('updater.psm1').
    - Downloading application assets for the 'github_release' provider in 'apps.psm1'.
    - Potentially by 'wingetcreate' if used by 'Get-ManifestDefaultPath' for 'AUTO' install locations.
    Providing a token helps avoid GitHub API rate limits for anonymous requests. If not provided as a
    parameter, the script will attempt to load it from './config/token.json'.
.EXAMPLE
    PS C:\Path\To\Script> .\post_install.ps1
    Runs the script using the default 'config\config.json' and 'logs\postinstall.log' relative to the script's location.
    It will operate without a GitHub token unless 'config\token.json' is present and valid.
.EXAMPLE
    PS C:\Path\To\Script> .\post_install.ps1 -ConfigPath "C:\custom_setup\my_config.json" -LogPath "C:\custom_setup\logs\install.txt" -GitHubToken "ghp_YourPersonalAccessTokenHere"
    Runs the script with a custom configuration file, a custom log file path, and a specified GitHub token.
.NOTES
    Requires Administrator privileges to run. If not executed as an administrator, the script will attempt
    to relaunch itself with elevated privileges. This relaunch will open a new PowerShell window.

    All dependent PowerShell modules (.psm1 files) are expected to be located in a subdirectory named 'modules'
    relative to this script's location ($PSScriptRoot\modules).

    For details on structuring the configuration JSON, refer to the 'config.json.example' file typically
    provided with this script suite.

    The script uses a global variable '$ScriptBaseDir' set to '$PSScriptRoot' for consistent module path resolution.
    Error handling is implemented to catch fatal errors, log them, display a summary, and then exit.
.LINK
    # Link to project repository or further documentation can be added here.
    # Example: https://github.com/yourusername/yourproject
#>

param(
    [string]$ConfigPath = "$PSScriptRoot\config\config.json",
    [string]$LogPath = "$PSScriptRoot\logs\postinstall.log",
    [string]$GitHubToken = $null # Optional: Can also be loaded from config/token.json
)

# --- Initial Setup and Configuration ---

# Attempt to load GitHub token from 'config/token.json' if not provided as a parameter.
# This allows storing the token separately from command-line arguments.
if (-not $GitHubToken) {
    $tokenFilePath = Join-Path $PSScriptRoot 'config\token.json' # Corrected variable name
    if (Test-Path $tokenFilePath) {
        try {
            $tokenObject = Get-Content $tokenFilePath | ConvertFrom-Json # Corrected variable name
            if ($tokenObject.GitHubToken -and -not [string]::IsNullOrWhiteSpace($tokenObject.GitHubToken)) { # Check for null or empty
                $GitHubToken = $tokenObject.GitHubToken
                Write-Host "[INFO] GitHub token loaded from config/token.json." # Use Write-Host before logging is up
            }
        }
        catch {
            # Non-critical error, script can proceed with anonymous API calls (subject to rate limits).
            Write-Host "[WARNING] Could not parse 'config/token.json' or token is empty. Proceeding without GitHub token from file. Error: $($_.Exception.Message)"
        }
    }
}

# Define the base directory for loading modules, typically where the script itself resides.
$ScriptBaseDir = $PSScriptRoot

# --- Administrator Privileges Check ---
# Ensure the script is running with Administrator privileges. If not, attempt to relaunch as admin.
# This is crucial for many system-level operations like software installation, UWP app removal, etc.
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Warning "Administrator privileges are required. Attempting to relaunch as Administrator..."
    # Construct arguments for the new PowerShell process.
    # -ExecutionPolicy Bypass: Temporarily bypasses execution policy for this instance.
    # -File `"$PSCommandPath`": Specifies the current script file to be re-run.
    # Any original parameters would need to be re-passed here if complex scenarios are needed.
    # For simplicity, this example doesn't re-pass $ConfigPath, $LogPath, $GitHubToken to the elevated instance.
    # Consider adding parameter re-passing if elevation is a common use case with custom params.
    $powershellArgs = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($ConfigPath -ne "$PSScriptRoot\config\config.json") { $powershellArgs += " -ConfigPath `"$ConfigPath`"" }
    if ($LogPath -ne "$PSScriptRoot\logs\postinstall.log") { $powershellArgs += " -LogPath `"$LogPath`"" }
    if ($GitHubToken) { $powershellArgs += " -GitHubToken `"$GitHubToken`"" } # Be cautious with tokens in command line

    Start-Process powershell.exe -ArgumentList $powershellArgs -Verb RunAs
    Exit # Exit the current non-elevated instance.
}

# --- Module Importing ---
# Import all necessary custom modules from the './modules' subdirectory.
# The Write-Host messages below are for initial script bootstrap debugging; regular logging uses Write-Log.
Write-Host "[DEBUG] post_install.ps1 - Importing modules from '$ScriptBaseDir\modules'..."
Import-Module "$ScriptBaseDir\modules\logging.psm1"
Import-Module "$ScriptBaseDir\modules\configuration.psm1"
Import-Module "$ScriptBaseDir\modules\providers.psm1"
Import-Module "$ScriptBaseDir\modules\debloat.psm1"
Import-Module "$ScriptBaseDir\modules\fonts.psm1"
Import-Module "$ScriptBaseDir\modules\apps.psm1"
Import-Module "$ScriptBaseDir\modules\cleanup.psm1"
Import-Module "$ScriptBaseDir\modules\updater.psm1"
Write-Host "[DEBUG] post_install.ps1 - All modules imported."

# --- Main Script Execution Block ---
try {
    # Initialize the logging system. This must be the first operation that uses Write-Log.
    # The Write-Host lines here are for pre-logging diagnostics if Initialize-Logging itself fails.
    Write-Host "[DEBUG] post_install.ps1 - Initializing logging. LogPath: '$LogPath'"
    Initialize-Logging -LogPath $LogPath
    Write-Host "[DEBUG] post_install.ps1 - Logging system initialized."

    Write-Log "Windows Post-Installation Script started." "INFO"
    if ($GitHubToken) { Write-Log "GitHub Token provided and loaded." "DEBUG"} else { Write-Log "No GitHub Token provided or loaded." "DEBUG"}

    # Load and validate the main configuration file.
    Write-Log "Loading configuration from '$ConfigPath'..." "INFO"
    $config = Get-Configuration -Path $ConfigPath
    Write-Log "Validating loaded configuration..." "INFO"
    Test-Configuration -Config $config

    # --- Optional: Script Version Update Check ---
    # Checks if a newer version of this script/configuration is available on GitHub.
    if ($config.metadata -and $config.metadata.repo) {
        Test-ScriptUpdateAvailable -Config $config -GitHubToken $GitHubToken
    }
    else {
        Write-Log "Updater: 'metadata.repo' not defined in config. Skipping update check." "WARNING"
    }

    # --- Debloat Phase ---
    # Removes unwanted applications if enabled in the configuration.
    if ($config.PSObject.Properties.Name -contains 'apps_debloater' -and $null -ne $config.apps_debloater.enabled -and $config.apps_debloater.enabled -eq $true) {
        Write-Log "Starting Debloat Phase..." "INFO"
        Invoke-WindowsDebloat -Config $config
        Write-Log "Debloat Phase completed." "INFO"
    } else {
        Write-Log "Debloat Phase skipped (disabled or not configured)." "INFO"
    }

    # --- Font Installation Phase ---
    # Installs Nerd Fonts and custom fonts if enabled.
    if ($config.PSObject.Properties.Name -contains 'fonts_provisioner' -and $null -ne $config.fonts_provisioner.enabled -and $config.fonts_provisioner.enabled -eq $true) {
        Write-Log "Starting Font Installation Phase..." "INFO"
        Install-Fonts -Config $config
        Write-Log "Font Installation Phase completed." "INFO"
    } else {
        Write-Log "Font Installation Phase skipped (disabled or not configured)." "INFO"
    }

    # --- Application Provisioning Phase ---
    # Installs desired applications using configured providers.
    if ($config.PSObject.Properties.Name -contains 'apps_provisioner' -and $null -ne $config.apps_provisioner.enabled -and $config.apps_provisioner.enabled -eq $true) {
        if ($GitHubToken) {
            Write-Log "Starting Application Installation Phase (GitHub token loaded, authenticated API requests where applicable)." "INFO"
        }
        else {
            Write-Log "Starting Application Installation Phase (No GitHub token, anonymous API requests where applicable)." "INFO"
        }
        Install-Applications -Config $config -GitHubToken $GitHubToken
        Write-Log "Application Installation Phase completed." "INFO"
    } else {
        Write-Log "Application Installation Phase skipped (disabled or not configured)." "INFO"
    }

    # --- Cleanup Phase ---
    # Performs cleanup of temporary files.
    Write-Log "Starting Cleanup Phase..." "INFO"
    Invoke-Cleanup
    Write-Log "Cleanup Phase completed." "SUCCESS" # Assuming Invoke-Cleanup logs its own errors/warnings

    # --- Summary ---
    # Display the overall summary of operations.
    Show-InstallationSummary
}
catch {
    # Catch any script-terminating errors that were not handled within specific phases.
    Write-Log "A fatal error occurred in the main script: $($_.Exception.ToString())" "ERROR" # Log full exception
    # Attempt to show whatever summary information was gathered before the fatal error.
    Show-InstallationSummary
    Write-Log "Script execution halted due to fatal error." "ERROR"
    exit 1 # Exit with an error code.
}

# Explicitly exit with success code if no fatal error occurred.
Write-Log "Windows Post-Installation Script finished successfully." "SUCCESS"
exit 0
