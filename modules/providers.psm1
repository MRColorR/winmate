<#!
.SYNOPSIS
    Handles detection and installation of package providers like winget, choco, scoop.
#>

function Test-WingetInstalled {
    return $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
}

function Test-ChocolateyInstalled {
    return $null -ne (Get-Command choco -ErrorAction SilentlyContinue)
}

function Test-ScoopInstalled {
    return $null -ne (Get-Command scoop -ErrorAction SilentlyContinue)
}

function Test-MsStorePseudoProvider {
    Write-Log "MSStore provider check: Assuming Winget will handle these if applicable." "DEBUG"
    return $true
}

function Install-Winget {
    Write-Log "Attempting to ensure Winget (App Installer) is available." "INFO"
    if (Test-WingetInstalled) {
        Write-Log "Winget already installed." "SUCCESS"
        return $true
    }
    Write-Log "Checking for App Installer package..." "INFO"
    $appInstaller = Get-AppxPackage Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue
    if ($appInstaller) {
        Write-Log "App Installer (Microsoft.DesktopAppInstaller) is present. Winget should be available." "SUCCESS"
        if (-not(Test-WingetInstalled)) {
            Write-Log "App Installer found, but winget command not available. Manual check might be needed or a system restart." "WARNING"
            return $false
        }
        return $true
    } else {
        Write-Log "App Installer (Microsoft.DesktopAppInstaller) not found. Winget may not be available. Please install it from the Microsoft Store or ensure Windows is up to date." "WARNING"
        return $false
    }
}

function Install-Chocolatey {
    Write-Log "Attempting to install Chocolatey..." "INFO"
    if (Test-ChocolateyInstalled) {
        Write-Log "Chocolatey already installed." "INFO"
        return $true
    }
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        Start-Sleep -Seconds 5 # Give time for environment changes to propagate
        if (Test-ChocolateyInstalled) {
            Write-Log "Chocolatey installed successfully." "SUCCESS"
            return $true
        } else {
            Write-Log "Chocolatey installation command ran, but choco command still not found. A reboot or manual environment refresh might be needed." "ERROR"
            return $false
        }
    } catch {
        Write-Log "Failed to install Chocolatey: $_" "ERROR"
        return $false
    }
}

function Install-Scoop {
    Write-Log "Attempting to install Scoop..." "INFO"
    if (Test-ScoopInstalled) {
        Write-Log "Scoop already installed." "INFO"
        return $true
    }
    try {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Invoke-Expression (Invoke-WebRequest -UseBasicParsing -Uri "https://get.scoop.sh").Content
        Start-Sleep -Seconds 5 # Give time for environment changes
        if (Test-ScoopInstalled) {
            Write-Log "Scoop installed successfully." "SUCCESS"
            Write-Log "Attempting to import Scoop module for path updates..." "DEBUG"
            try {
                # Attempt to find and import scoop's own module to update paths for current session
                $scoopModulePath = Join-Path (Split-Path (Get-Command scoop).Source).Parent 'modules\scoop.psm1'
                if (Test-Path $scoopModulePath) {
                    Import-Module $scoopModulePath -ErrorAction Stop
                    Write-Log "Scoop module imported. Paths should be updated for current session." "DEBUG"
                } else {
                     Write-Log "Scoop main module (scoop.psm1) not found at expected path: $scoopModulePath" "DEBUG"
                }
            } catch {
                Write-Log "Scoop main module not found at expected path or failed to import. Scoop might require a new shell session for full path integration: $_" "WARNING"
            }
            return $true
        } else {
            Write-Log "Scoop installation command ran, but scoop command still not found. A new PowerShell session or manual environment refresh might be needed." "ERROR"
            return $false
        }
    } catch {
        Write-Log "Failed to install Scoop: $_" "ERROR"
        return $false
    }
}

function Ensure-ProviderInstalled {
    param(
        [string]$ProviderName
    )
    Write-Log "Ensuring provider '$ProviderName' is installed." "INFO"
    $providerLower = $ProviderName.ToLower()
    $result = $false
    switch ($providerLower) {
        'winget' {
            if (Test-WingetInstalled) { $result = $true } else { $result = Install-Winget }
        }
        'chocolatey' {
            if (Test-ChocolateyInstalled) { $result = $true } else { $result = Install-Chocolatey }
        }
        'scoop' {
            if (Test-ScoopInstalled) { $result = $true } else { $result = Install-Scoop }
        }
        'msstore' {
            $result = Test-MsStorePseudoProvider
        }
        'manual' {
            Write-Log "Manual provider does not require installation." "DEBUG"
            $result = $true
        }
        'github_release' {
            Write-Log "GitHub Release provider does not require separate installation. Handled by app installer." "DEBUG"
            $result = $true
        }
        default {
            Write-Log "Provider '$ProviderName' is not recognized by Ensure-ProviderInstalled." "WARNING"
            $result = $false
        }
    }
    if ($result) {
        Write-Log "Provider '$ProviderName' successfully ensured." "INFO"
    } else {
        Write-Log "Failed to ensure provider '$ProviderName'." "ERROR" # This log might be redundant if Install-* functions log specific errors
    }
    return $result
}

Export-ModuleMember -Function Ensure-ProviderInstalled, Test-WingetInstalled, Test-ChocolateyInstalled, Test-ScoopInstalled, Test-MsStorePseudoProvider, Install-Winget, Install-Chocolatey, Install-Scoop
