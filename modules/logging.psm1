Write-Host "DEBUG: logging.ps1 - Start of script execution."
# Module for logging utilities.
# importer.ps1 should not be sourced here. It's sourced by the main post_install.ps1 script.
# 'settings' module import was removed to prevent circular dependencies.
# The param() block was removed; $global:LogPath is set by post_install.ps1 directly.

<#!
.SYNOPSIS
    Logging utilities for post-installation script
.DESCRIPTION
    Provides timestamped logging with severity levels and fallback to temp file if log file is locked.
#>

# $global:LogPath is expected to be set by the calling script (post_install.ps1)
# before Initialize-Logging is invoked.
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
    param([string]$LogPath)
    $global:LogPath = $LogPath
    Write-Host "DEBUG: Initialize-Logging - Started. Received LogPath: '$LogPath'"
    Write-Host "DEBUG: Initialize-Logging - Global LogPath now set to: '$global:LogPath'"
    try {
        # Note: $dir will be calculated on the next line. This message is for context before its calculation.
        Write-Host "DEBUG: Initialize-Logging - Preparing to determine target log directory from: '$global:LogPath'"
        $dir = Split-Path -Parent $global:LogPath
        Write-Host "DEBUG: Initialize-Logging - Target log directory determined as: '$dir'"
        if (-not (Test-Path $dir)) {
            Write-Host "DEBUG: Initialize-Logging - Directory '$dir' does not exist. Attempting to create."
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Host "DEBUG: Initialize-Logging - Directory creation attempt complete."
        }

        $header = @"
================================================================================
Windows Post-Installation Automation Script Log
Started: $($global:StartTime.ToString('yyyy-MM-dd HH:mm:ss'))
PowerShell Version: $($PSVersionTable.PSVersion)
================================================================================
"@
        Write-Host "DEBUG: Initialize-Logging - Attempting to write log header to: '$global:LogPath'"
        Set-Content -Path $global:LogPath -Value $header -Encoding UTF8
        Write-Host "DEBUG: Initialize-Logging - Log header written."
        Write-Log "Logging initialized" "SUCCESS"
    } catch {
        Write-Host "DEBUG: Initialize-Logging - ERROR CAUGHT: $($_.Exception.Message)"
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

Write-Host "DEBUG: logging.ps1 - End of script execution. Functions (Write-Log, Initialize-Logging, Show-InstallationSummary) should be defined now."
Export-ModuleMember -Function *
