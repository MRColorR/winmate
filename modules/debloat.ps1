# Import standard modules
. "$PSScriptRoot\importer.ps1"
Import-ModuleFromFolder -name "settings"
Import-ModuleFromFolder -name "logging"

<#!
.SYNOPSIS
    Removes unnecessary or unwanted pre-installed applications
#>

function Invoke-WindowsDebloat {
    param(
        [hashtable]$Config
    )

    if (-not $Config.steps.debloat.enabled) {
        Write-Log "Debloat step is disabled in configuration." "INFO"
        return
    }

    Write-Log "Starting Windows Debloat..." "INFO"

    foreach ($app in $Config.apps.GetEnumerator()) {
        $name = $app.Key
        $settings = $app.Value

        if ($settings.remove -eq $true) {
            Write-Log "Attempting to remove: $name" "INFO"
            Remove-WindowsApplication -AppName $name -AppConfig $settings
        }
    }

    Write-Log "Debloat phase complete." "SUCCESS"
}

function Remove-WindowsApplication {
    param(
        [string]$AppName,
        [hashtable]$AppConfig
    )

    $removed = $false

    try {
        # UWP
        $uwp = Get-AppxPackage | Where-Object { $_.Name -like "*$AppName*" }
        if ($uwp) {
            $uwp | Remove-AppxPackage -ErrorAction Stop
            Write-Log "Removed UWP: $AppName" "SUCCESS"
            $removed = $true
        }

        # Provisioned
        $prov = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*$AppName*" }
        if ($prov) {
            $prov | Remove-AppxProvisionedPackage -Online -ErrorAction Stop
            Write-Log "Removed provisioned package: $AppName" "SUCCESS"
            $removed = $true
        }

        # Fallback to package manager if defined
        if (-not $removed -and $AppConfig.provider) {
            switch ($AppConfig.provider.ToLower()) {
                'winget' {
                    & winget uninstall $AppName --silent --accept-source-agreements
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "Removed via WinGet: $AppName" "SUCCESS"
                        $removed = $true
                    }
                }
                'chocolatey' {
                    & choco uninstall $AppName -y
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "Removed via Chocolatey: $AppName" "SUCCESS"
                        $removed = $true
                    }
                }
            }
        }

        if (-not $removed) {
            Write-Log "App not found or already removed: $AppName" "INFO"
        }

    } catch {
        Write-Log "Error removing $AppName: $_" "ERROR"
    }
}
