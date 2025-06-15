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
$global:DebugLoggingEnabled = $false
$global:PhaseSummaries = @{}

enum LogLevel {
    INFO
    WARNING
    ERROR
    SUCCESS
    DEBUG # Added DEBUG level
}

function Enable-DebugLogging {
    $global:DebugLoggingEnabled = $true
    Write-Log "Debug logging enabled." "DEBUG"
}

function Initialize-PhaseSummary {
    param(
        [string]$PhaseName
    )
    if (-not $PhaseName) {
        Write-Log "PhaseName cannot be empty for Initialize-PhaseSummary" "ERROR"
        return
    }
    $global:PhaseSummaries[$PhaseName] = @{
        Success         = 0
        Warning         = 0
        Error           = 0
        ItemsAttempted  = 0
        Details         = [System.Collections.Generic.List[string]]::new()
    }
    Write-Log "Initialized summary for phase: $PhaseName" "DEBUG"
}

function Update-PhaseOutcome {
    param(
        [string]$PhaseName,
        [ValidateSet('Success', 'Warning', 'Error')][string]$OutcomeType,
        [int]$Increment = 1,
        [string]$DetailMessage = $null
    )
    if (-not ($global:PhaseSummaries.ContainsKey($PhaseName))) {
        Initialize-PhaseSummary -PhaseName $PhaseName
        Write-Log "Implicitly initialized summary for phase '$PhaseName' due to Update-PhaseOutcome call." "WARNING"
    }
    $global:PhaseSummaries[$PhaseName][$OutcomeType] += $Increment
    # ItemsAttempted is incremented for Success and Error, as these usually represent processed items.
    # Warnings might be general or apply to an already counted item.
    if ($OutcomeType -ne 'Warning') {
        $global:PhaseSummaries[$PhaseName].ItemsAttempted += $Increment
    }
    if ($DetailMessage) {
        $global:PhaseSummaries[$PhaseName].Details.Add("[$OutcomeType] $DetailMessage")
    }
    Write-Log "Updated phase '$PhaseName': $OutcomeType +$Increment. Items Attempted: $($global:PhaseSummaries[$PhaseName].ItemsAttempted)" "DEBUG"
}

function Write-Log {
    param(
        [string]$Message,
        [LogLevel]$Level = [LogLevel]::INFO
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    switch ($Level) {
        "INFO"    { Write-Host $logEntry -ForegroundColor White }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow; $global:WarningCount++ }
        "ERROR"   { Write-Host $logEntry -ForegroundColor Red;   $global:ErrorCount++ }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green; $global:SuccessCount++ }
        "DEBUG"   {
            if ($global:DebugLoggingEnabled) { Write-Host $logEntry -ForegroundColor Gray }
            # DEBUG messages do not increment overall counters
        }
    }

    try {
        # DEBUG messages are always written to the log file
        Add-Content -Path $global:LogPath -Value $logEntry -Encoding UTF8
    }
    catch {
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
    }
    catch {
        Write-Host "DEBUG: Initialize-Logging - ERROR CAUGHT: $($_.Exception.Message)"
        Add-Content -Path $global:LogFallbackPath -Value "[FALLBACK LOG] Logging initialization failed: $_" -Encoding UTF8
    }
}

function Show-InstallationSummary {
    $endTime = Get-Date
    $duration = $endTime - $global:StartTime

    # --- Per-Phase Summaries ---
    if ($global:PhaseSummaries.Count -gt 0) {
        Write-Log "--------------------------------------------------------------------------------" "INFO"
        Write-Log "                         >>> Phase Summaries <<<" "INFO"
        Write-Log "--------------------------------------------------------------------------------" "INFO"
        foreach ($phaseEntry in $global:PhaseSummaries.GetEnumerator() | Sort-Object Name) {
            $phaseName = $phaseEntry.Name
            $stats = $phaseEntry.Value
            Write-Log "" "INFO" # Blank line for spacing
            Write-Log "--- Phase Summary: $phaseName ---" "INFO"
            Write-Log "Items Attempted: $($stats.ItemsAttempted)" "INFO"
            Write-Log "  Success: $($stats.Success)" "SUCCESS"
            Write-Log "  Warning: $($stats.Warning)" "WARNING"
            Write-Log "  Error:   $($stats.Error)" "ERROR"

            if ($stats.Details.Count -gt 0 -and $global:DebugLoggingEnabled) {
                Write-Log "  Details for $phaseName:" "DEBUG"
                foreach ($detail in $stats.Details) {
                    Write-Log "    $detail" "DEBUG" # Detail already includes outcome type
                }
            }
            Write-Log "--- End of Phase: $phaseName ---" "INFO"
        }
        Write-Log "--------------------------------------------------------------------------------" "INFO"
    }


    # --- Overall Summary ---
    Write-Log "" "INFO" # Blank line for spacing
    Write-Log "=== OVERALL INSTALLATION SUMMARY ===" "INFO"
    Write-Log "Total Duration: $($duration.ToString('hh\:mm\:ss'))" "INFO"
    Write-Log "Overall Success Count (from Write-Log): $global:SuccessCount" "SUCCESS"
    Write-Log "Overall Warning Count (from Write-Log): $global:WarningCount" "WARNING"
    Write-Log "Overall Error Count (from Write-Log):   $global:ErrorCount" "ERROR"
    Write-Log "Log File Location: $global:LogPath" "INFO"
    if (Test-Path $global:LogFallbackPath) {
        Write-Log "Fallback Log: $global:LogFallbackPath (used due to file access errors)" "WARNING"
    }
    Write-Log "=== END OF SCRIPT SUMMARY ===" "INFO"
}

Write-Host "DEBUG: logging.ps1 - End of script execution. All logging functions should be defined now."
Export-ModuleMember -Function Write-Log, Initialize-Logging, Show-InstallationSummary, Enable-DebugLogging, Initialize-PhaseSummary, Update-PhaseOutcome
