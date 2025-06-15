<#!
<#
.SYNOPSIS
    Handles detection, installation, and initialization of package management providers
    such as Winget, Chocolatey, and Scoop.
.DESCRIPTION
    This module provides functions to test if common PowerShell package managers (Winget, Chocolatey, Scoop)
    are installed and their commands are available. It also includes functions to attempt installation
    of Chocolatey and Scoop if they are not found. A central function, Initialize-ProviderPackage,
    orchestrates these checks and installations to ensure a provider is ready for use.
.NOTES
    This module relies on external commands (winget, choco, scoop) and internet access for installations.
    Execution policies might need adjustment for installation scripts to run, which these functions attempt to handle.
#>

<#
.SYNOPSIS
    Checks if the Winget command-line tool (winget.exe) is available in the current session's PATH.
.DESCRIPTION
    Tests for the presence of 'winget.exe' using Get-Command. This indicates whether Winget
    is installed and accessible.
.EXAMPLE
    PS C:\> if (Test-WingetCommand) { Write-Host "Winget is available." }
.NOTES
    Returns $true if winget command is found, $false otherwise.
#>
function Test-WingetCommand {
    return $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
}

<#
.SYNOPSIS
    Checks if the Chocolatey command-line tool (choco.exe) is available.
.DESCRIPTION
    Tests for the presence of 'choco.exe' using Get-Command.
.EXAMPLE
    PS C:\> if (Test-ChocolateyCommand) { Write-Host "Chocolatey is available." }
.NOTES
    Returns $true if choco command is found, $false otherwise.
#>
function Test-ChocolateyCommand {
    return $null -ne (Get-Command choco -ErrorAction SilentlyContinue)
}

<#
.SYNOPSIS
    Checks if the Scoop command-line tool (scoop.exe) is available.
.DESCRIPTION
    Tests for the presence of 'scoop.exe' using Get-Command.
.EXAMPLE
    PS C:\> if (Test-ScoopCommand) { Write-Host "Scoop is available." }
.NOTES
    Returns $true if scoop command is found, $false otherwise.
#>
function Test-ScoopCommand {
    return $null -ne (Get-Command scoop -ErrorAction SilentlyContinue)
}

<#
.SYNOPSIS
    Checks the availability of MSStore as a software source (conceptual check).
.DESCRIPTION
    For MSStore, actual provider installation isn't applicable like with Chocolatey/Scoop.
    This function serves as a placeholder, assuming that if Winget is available, it can act as a
    handler for MSStore sources if configured. It logs a debug message and returns $true.
.EXAMPLE
    PS C:\> Test-MsStoreAvailability
.NOTES
    Always returns $true. The actual ability to install from MSStore via Winget depends on Winget's configuration and Windows version.
#>
function Test-MsStoreAvailability {
    Write-Log "MSStore provider check: Assuming Winget will handle these if applicable." "DEBUG"
    return $true # MSStore itself doesn't need 'installation' as a provider, availability is assumed.
}

<#
.SYNOPSIS
    Ensures Winget (via App Installer) is available.
.DESCRIPTION
    Checks if the Winget command is available. If not, it verifies if the Microsoft.DesktopAppInstaller AppX package
    is present, which is the modern way Winget is distributed. It does not attempt to install Winget itself,
    but rather guides the user or logs if manual action is needed.
.EXAMPLE
    PS C:\> Install-Winget
.NOTES
    Returns $true if Winget command is found or if App Installer is present (implying Winget should be available, possibly after a session restart).
    Returns $false if neither is found, with a warning message.
#>
function Install-Winget {
    Write-Log "Attempting to ensure Winget (App Installer) is available." "INFO"
    if (Test-WingetCommand) {
        Write-Log "Winget command is already available." "SUCCESS"
        return $true
    }
    Write-Log "Checking for App Installer package (Microsoft.DesktopAppInstaller)..." "INFO"
    $appInstaller = Get-AppxPackage Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue
    if ($appInstaller) {
        Write-Log "App Installer (Microsoft.DesktopAppInstaller) is present. Winget command should be available." "SUCCESS"
        # Re-test after confirming App Installer, as the command might not have been in PATH initially for the current session.
        if (-not(Test-WingetCommand)) {
            Write-Log "App Installer found, but 'winget' command still not available in PATH. A system restart or new PowerShell session might be required." "WARNING"
            return $false # Winget command itself is not usable yet.
        }
        return $true
    }
    else {
        Write-Log "App Installer (Microsoft.DesktopAppInstaller) not found. Winget may not be available. Please install it from the Microsoft Store or ensure Windows is up to date." "WARNING"
        return $false
    }
}

<#
.SYNOPSIS
    Installs Chocolatey package manager if it's not already available.
.DESCRIPTION
    Checks if the Chocolatey command ('choco') is available. If not, it attempts to download and execute
    the official Chocolatey installation script from community.chocolatey.org.
    It temporarily adjusts execution policy for the process to allow the script to run.
.EXAMPLE
    PS C:\> Install-Chocolatey
.NOTES
    Requires internet access to download the installation script.
    Returns $true on successful installation or if already installed.
    Returns $false if installation fails or if 'choco' command is still not found after script execution.
    A new PowerShell session or manual environment refresh might be needed in some cases for 'choco' to become available.
#>
function Install-Chocolatey {
    Write-Log "Attempting to install Chocolatey..." "INFO"
    if (Test-ChocolateyCommand) {
        Write-Log "Chocolatey command already available." "INFO" # Changed from SUCCESS to INFO as it's a pre-check
        return $true
    }
    try {
        Write-Log "Executing Chocolatey installation script from community.chocolatey.org." "DEBUG"
        Set-ExecutionPolicy Bypass -Scope Process -Force
        # Ensure TLS 1.2 or higher is used for the web request, as required by Chocolatey.
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072 # TLS 1.2
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Start-Sleep -Seconds 5 # Give time for environment changes to propagate, like PATH updates.

        if (Test-ChocolateyCommand) {
            # Re-test after installation attempt
            Write-Log "Chocolatey installed successfully." "SUCCESS"
            return $true
        }
        else {
            Write-Log "Chocolatey installation script ran, but 'choco' command still not found. A new PowerShell session or manual environment refresh might be needed." "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Failed to install Chocolatey: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

<#
.SYNOPSIS
    Installs Scoop package manager if it's not already available.
.DESCRIPTION
    Checks if the Scoop command ('scoop') is available. If not, it attempts to download and execute
    the official Scoop installation script from get.scoop.sh.
    It sets the execution policy for the current user to RemoteSigned to allow the script to run, as per Scoop's recommendation.
    After installation, it attempts to update the environment for the current session.
.EXAMPLE
    PS C:\> Install-Scoop
.NOTES
    Requires internet access.
    Returns $true on successful installation or if already installed.
    Returns $false if installation fails or if 'scoop' command is not found after script execution.
    Scoop heavily relies on environment variables; a new PowerShell session is often the most reliable way
    to ensure Scoop works correctly after initial install, though this function attempts to update the current session.
#>
function Install-Scoop {
    Write-Log "Attempting to install Scoop..." "INFO"
    if (Test-ScoopCommand) {
        Write-Log "Scoop command already available." "INFO" # Changed from SUCCESS to INFO
        return $true
    }
    try {
        Write-Log "Executing Scoop installation script from get.scoop.sh." "DEBUG"
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force # Scoop's recommended policy
        Invoke-Expression (Invoke-WebRequest -UseBasicParsing -Uri "https://get.scoop.sh").Content
        Start-Sleep -Seconds 5 # Give time for environment changes, especially PATH.

        if (Test-ScoopCommand) {
            Write-Log "Scoop installed successfully. Attempting to update environment for current session..." "SUCCESS"
            # Try to update environment for current session by finding and sourcing Scoop's own scripts.
            # This is best-effort as Scoop's paths might change or this might not be fully effective.
            try {
                $scoopExePath = (Get-Command scoop).Source
                $scoopBasePath = Split-Path $scoopExePath | Split-Path # Expected to be ~\scoop (e.g., C:\Users\User\scoop)
                $scoopShimsPath = Join-Path $scoopBasePath "shims"

                # Add Scoop shims to PATH for the current process if not already there.
                if ($env:PATH -notlike "*$scoopShimsPath*") {
                    Write-Log "Adding Scoop shims path to process PATH: $scoopShimsPath" "DEBUG"
                    $env:PATH = "$scoopShimsPath;$env:PATH"
                }

                # Attempt to invoke scoop.ps1 (or similar) if it exists in a known location relative to scoop.exe
                $scoopPs1Path = Join-Path $scoopBasePath "libexec\scoop.ps1" # A common historical location
                if (-not (Test-Path $scoopPs1Path)) {
                    # Check another potential location if the above isn't found (e.g. if scoop's structure changes)
                    $scoopPs1Path = Join-Path (Split-Path (Get-Command scoop).Source -Parent) "scoop.ps1"
                }
                if (-not (Test-Path $scoopPs1Path)) {
                    # Check for psm1 as well
                    $scoopPs1Path = Join-Path (Split-Path (Get-Command scoop).Source -Parent) "scoop.psm1"
                }


                if (Test-Path $scoopPs1Path) {
                    Write-Log "Attempting to source Scoop's environment script: $scoopPs1Path" "DEBUG"
                    . $scoopPs1Path # Sourcing the script to apply env changes
                    Write-Log "Scoop environment script sourced." "DEBUG"
                }
                else {
                    Write-Log "Scoop environment script (scoop.ps1/scoop.psm1) not found at expected paths. A new shell session might be needed for full integration." "WARNING"
                }
            }
            catch {
                Write-Log "Error trying to update Scoop environment for current session: $($_.Exception.Message). A new shell session might be needed." "WARNING"
            }
            return $true # Installation of scoop itself was successful.
        }
        else {
            Write-Log "Scoop installation script ran, but 'scoop' command still not found. A new PowerShell session or manual environment refresh might be needed." "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Failed to install Scoop: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

<#
.SYNOPSIS
    Ensures a specific package provider (like Chocolatey or Scoop) is installed and ready for use.
.DESCRIPTION
    This function acts as a central point to check for and install various package providers.
    It takes a provider name (e.g., "winget", "chocolatey", "scoop"), checks if its command is available,
    and if not, attempts to install it using the respective Install-* function.
    For providers like 'manual', 'msstore', or 'github_release', it performs a conceptual check or logs
    that no specific installation is required at this stage.
.PARAMETER ProviderName
    The name of the package provider to ensure is installed.
    Supported values typically include 'winget', 'chocolatey', 'scoop', 'msstore', 'manual', 'github_release'.
    The function is case-insensitive with this name.
.EXAMPLE
    PS C:\> Initialize-ProviderPackage -ProviderName "chocolatey"
    This will check if Chocolatey is installed. If not, it will attempt to install it.
    Returns $true if Chocolatey is available or successfully installed, $false otherwise.

.EXAMPLE
    PS C:\> if (Initialize-ProviderPackage -ProviderName "scoop") { # Proceed with scoop operations }
.NOTES
    Returns $true if the provider is available/ready or successfully installed/initialized.
    Returns $false if the provider is not available and could not be installed, or if the provider name is not recognized.
    Logs the outcome of its operations.
#>
function Initialize-ProviderPackage {
    param(
        [string]$ProviderName
    )
    Write-Log "Initializing provider package: '$ProviderName'" "INFO"
    $providerLower = $ProviderName.ToLower()
    $result = $false
    switch ($providerLower) {
        'winget' {
            if (Test-WingetCommand) { $result = $true } else { $result = Install-Winget }
        }
        'chocolatey' {
            if (Test-ChocolateyCommand) { $result = $true } else { $result = Install-Chocolatey }
        }
        'scoop' {
            if (Test-ScoopCommand) { $result = $true } else { $result = Install-Scoop }
        }
        'msstore' {
            $result = Test-MsStoreAvailability
        }
        'manual' {
            Write-Log "Manual provider does not require specific package initialization." "DEBUG"
            $result = $true
        }
        'github_release' {
            Write-Log "GitHub Release provider does not require specific package initialization." "DEBUG"
            $result = $true
        }
        default {
            Write-Log "Provider '$ProviderName' is not recognized by Initialize-ProviderPackage." "WARNING"
            $result = $false # Explicitly false for unknown provider
        }
    }

    if ($result) {
        Write-Log "Provider package '$ProviderName' successfully initialized/verified." "INFO"
    }
    else {
        Write-Log "Failed to initialize/verify provider package '$ProviderName'." "ERROR"
    }
    return $result
}

# Updated Export-ModuleMember with new function names
Export-ModuleMember -Function Initialize-ProviderPackage, Test-WingetCommand, Test-ChocolateyCommand, Test-ScoopCommand, Test-MsStoreAvailability, Install-Winget, Install-Chocolatey, Install-Scoop
