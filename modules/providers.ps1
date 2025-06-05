<#!
.SYNOPSIS
    Handles detection and installation of package providers like winget, choco, scoop.
#>

function Test-PackageProvider {
    param(
        [string]$Provider
    )

    switch ($Provider.ToLower()) {
        'winget'       { return (Get-Command winget -ErrorAction SilentlyContinue) -ne $null }
        'chocolatey'   { return (Get-Command choco -ErrorAction SilentlyContinue) -ne $null }
        'scoop'        { return (Get-Command scoop -ErrorAction SilentlyContinue) -ne $null }
        'msstore'      { return $true }  # built-in
        default        {
            Write-Log "Unknown provider: $Provider" "WARNING"
            return $false
        }
    }
}

function Install-PackageProvider {
    param(
        [string]$Provider
    )

    Write-Log "Installing provider: $Provider" "INFO"

    switch ($Provider.ToLower()) {
        'chocolatey' {
            try {
                Set-ExecutionPolicy Bypass -Scope Process -Force
                [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
                Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
                Write-Log "Chocolatey installed successfully" "SUCCESS"
            } catch {
                Write-Log "Failed to install Chocolatey: $_" "ERROR"
                throw
            }
        }
        'scoop' {
            try {
                Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
                iwr -useb get.scoop.sh | iex
                Write-Log "Scoop installed successfully" "SUCCESS"
            } catch {
                Write-Log "Failed to install Scoop: $_" "ERROR"
                throw
            }
        }
        'winget' {
            Write-Log "WinGet should be installed via App Installer or Windows Update." "WARNING"
        }
        default {
            Write-Log "Cannot install unknown provider: $Provider" "ERROR"
            throw "Unsupported provider"
        }
    }
}

Export-ModuleMember -Function *
