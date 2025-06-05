# Import standard modules
. "$PSScriptRoot\importer.ps1"
Import-ModuleFromFolder -name "settings"

<#!
.SYNOPSIS
    Logging utilities for post-installation script
.DESCRIPTION
    Provides timestamped logging with severity levels and fallback to temp file if log file is locked.
#>

param(
    [string]$LogPath
)

$global:LogPath = $LogPath
$global:LogFallbackPath = "$env:TEMP\postinstall_fallback.log"
$global:StartTime = Get-Date
$global:ErrorCount = 0
$global:WarningCount = 0
$global:SuccessCount = 0

enum LogLevel {
    INFO
    WARNING
    ERROR
    SUCCESS
}

function Write-Log {
    param(
        [string]$Message,
        [LogLevel]$Level = [LogLevel]::INFO
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        "INFO"     { Write-Host $logEntry -ForegroundColor White  }
        "WARNING"  { Write-Host $logEntry -ForegroundColor Yellow; $global:WarningCount++ }
        "ERROR"    { Write-Host $logEntry -ForegroundColor Red; $global:ErrorCount++ }
        "SUCCESS"  { Write-Host $logEntry -ForegroundColor Green; $global:SuccessCount++ }
    }

    try {
        Add-Content -Path $global:LogPath -Value $logEntry -Encoding UTF8
    } catch {
        Add-Content -Path $global:LogFallbackPath -Value $logEntry -Encoding UTF8
    }
}

function Initialize-Logging {
    try {
        $dir = Split-Path -Parent $global:LogPath
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $header = @"
================================================================================
Windows Post-Installation Automation Script Log
Started: $($global:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))
PowerShell Version: $($PSVersionTable.PSVersion)
================================================================================
"@
        Set-Content -Path $global:LogPath -Value $header -Encoding UTF8
        Write-Log "Logging initialized" "SUCCESS"
    } catch {
        Add-Content -Path $global:LogFallbackPath -Value "[FALLBACK LOG] Logging initialization failed: $_" -Encoding UTF8
    }
}

function Show-InstallationSummary {
    $endTime = Get-Date
    $duration = $endTime - $global:StartTime
    Write-Log "=== INSTALLATION SUMMARY ===" "INFO"
    Write-Log "Duration: $($duration.ToString('hh\:mm\:ss'))" "INFO"
    Write-Log "Successes: $global:SuccessCount" "SUCCESS"
    Write-Log "Warnings: $global:WarningCount" "WARNING"
    Write-Log "Errors: $global:ErrorCount" "ERROR"
    Write-Log "Log: $global:LogPath" "INFO"
    if (Test-Path $global:LogFallbackPath) {
        Write-Log "Fallback Log: $global:LogFallbackPath (used due to file access errors)" "WARNING"
    }
    Write-Log "=== END SUMMARY ===" "INFO"
}
