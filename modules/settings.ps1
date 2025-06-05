# Import standard modules
. "$PSScriptRoot\importer.ps1"
Import-ModuleFromFolder -name "settings"
Import-ModuleFromFolder -name "logging"

<#!
.SYNOPSIS
    Applies system settings based on config
#>

function Set-SystemConfiguration {
    param(
        [hashtable]$Config
    )

    Write-Log "Applying system configuration..." "INFO"

    if ($Config.settings.privacy.enabled) {
        Set-PrivacySettings -Settings $Config.settings.privacy
    }

    if ($Config.settings.performance.enabled) {
        Set-PerformanceSettings -Settings $Config.settings.performance
    }

    if ($Config.settings.ui.enabled) {
        Set-UISettings -Settings $Config.settings.ui
    }

    Write-Log "System configuration applied." "SUCCESS"
}

function Set-PrivacySettings {
    param([hashtable]$Settings)

    if ($Settings.disable_telemetry) {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -Type DWord -Force
        Write-Log "Telemetry disabled" "SUCCESS"
    }
    if ($Settings.disable_location) {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors" -Name "DisableLocation" -Value 1 -Type DWord -Force
        Write-Log "Location services disabled" "SUCCESS"
    }
    if ($Settings.disable_cortana) {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search" -Name "AllowCortana" -Value 0 -Type DWord -Force
        Write-Log "Cortana disabled" "SUCCESS"
    }
}

function Set-PerformanceSettings {
    param([hashtable]$Settings)

    if ($Settings.disable_startup_delay) {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" -Name "StartupDelayInMSec" -Value 0 -Type DWord -Force
        Write-Log "Startup delay disabled" "SUCCESS"
    }
    if ($Settings.optimize_visual_effects) {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2 -Type DWord -Force
        Write-Log "Visual effects optimized" "SUCCESS"
    }
    if ($Settings.disable_search_indexing) {
        Stop-Service WSearch -Force -ErrorAction SilentlyContinue
        Set-Service WSearch -StartupType Disabled -ErrorAction SilentlyContinue
        Write-Log "Search indexing disabled" "SUCCESS"
    }
}

function Set-UISettings {
    param([hashtable]$Settings)

    if ($Settings.dark_mode) {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "AppsUseLightTheme" -Value 0 -Type DWord -Force
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "SystemUsesLightTheme" -Value 0 -Type DWord -Force
        Write-Log "Dark mode enabled" "SUCCESS"
    }
    if ($Settings.show_file_extensions) {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0 -Type DWord -Force
        Write-Log "File extensions shown" "SUCCESS"
    }
    if ($Settings.show_hidden_files) {
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1 -Type DWord -Force
        Write-Log "Hidden files shown" "SUCCESS"
    }
}
