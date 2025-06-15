# Write-Host "DEBUG: logging.ps1 - Start of script execution." # Removed for cleaner module loading
# Module for logging utilities.
# importer.ps1 should not be sourced here. It's sourced by the main post_install.ps1 script.
# 'settings' module import was removed to prevent circular dependencies.
# The param() block was removed; $global:LogPath is set by post_install.ps1 directly.

<#
.SYNOPSIS
    Master module for all logging functionalities within the post-installation script.
.DESCRIPTION
    This module provides a comprehensive suite of logging tools, including:
    - Timestamped logging to both console and file with configurable severity levels.
    - Fallback logging to a temporary file if the primary log file is inaccessible.
    - Global counters for errors, warnings, and successes.
    - A DEBUG log level with console output controlled by a global flag.
    - Per-phase summary statistics collection and reporting.
.NOTES
    Key global variables used or managed by this module:
    - $global:LogPath: Path to the primary log file. Must be set by the calling script via Initialize-Logging.
    - $global:LogFallbackPath: Path for the fallback log file.
    - $global:StartTime: Timestamp of script initiation, used for calculating total duration.
    - $global:ErrorCount, $global:WarningCount, $global:SuccessCount: Global counters for log severities.
    - $global:DebugLoggingEnabled: Boolean flag to enable/disable console output for DEBUG messages.
    - $global:PhaseSummaries: Hashtable to store detailed statistics for various script phases.
#>

# $global:LogPath is expected to be set by the calling script (post_install.ps1)
# before Initialize-Logging is invoked.
$global:LogFallbackPath = "$env:TEMP\postinstall_fallback.log" # Path for fallback log if primary is locked
$global:StartTime = Get-Date              # Script start time, used for overall duration calculation
$global:ErrorCount = 0                    # Global counter for ERROR level logs
$global:WarningCount = 0                  # Global counter for WARNING level logs
$global:SuccessCount = 0                  # Global counter for SUCCESS level logs
$global:DebugLoggingEnabled = $false      # Controls whether DEBUG messages are written to the console. Set to $true via Enable-DebugLogging.
$global:PhaseSummaries = @{}              # Stores detailed summaries for different script phases (e.g., "Apps", "Fonts")
# Structure: $global:PhaseSummaries.PhaseName = @{ Success=0; Warning=0; Error=0; ItemsAttempted=0; Details=[List[string]] }

# Defines the available logging levels.
enum LogLevel {
    INFO    # General informational messages.
    WARNING # Potential issues or non-critical failures.
    ERROR   # Errors that occurred during an operation.
    SUCCESS # Successful completion of an operation.
    DEBUG   # Detailed messages for troubleshooting.
}

<#
.SYNOPSIS
    Enables detailed debug logging to the console.
.DESCRIPTION
    Sets a global flag ($global:DebugLoggingEnabled) to $true.
    When this flag is true, DEBUG level messages from Write-Log will be displayed on the console.
    DEBUG messages are always written to the log file regardless of this setting.
.EXAMPLE
    PS C:\> Enable-DebugLogging
    This command enables debug message output to the console for the current script session.
    The first DEBUG message logged by this function itself will also appear on the console.
.NOTES
    This setting affects console output only. DEBUG messages are always recorded in the log file.
#>
function Enable-DebugLogging {
    $global:DebugLoggingEnabled = $true
    Write-Log "Debug logging enabled." "DEBUG" # This first DEBUG message will also show on console.
}

<#
.SYNOPSIS
    Initializes a summary structure for a specific operational phase of the script.
.DESCRIPTION
    Creates a new entry in the global phase summary hash table ($global:PhaseSummaries) for the given phase name.
    This structure tracks counts of successes, warnings, errors, the total number of items attempted,
    and a list of detailed messages for that phase.
    It's typically called at the beginning of a major script section (e.g., App Installation, Debloating, Font Setup).
    If called for an existing phase, it will reset the summary for that phase.
.PARAMETER PhaseName
    The name of the phase to initialize the summary for (e.g., "Apps", "Fonts", "Debloat"). This name is case-sensitive
    and will be used as the key in the $global:PhaseSummaries hashtable.
.EXAMPLE
    PS C:\> Initialize-PhaseSummary -PhaseName "Application Installation"
    This initializes (or re-initializes) the summary data for the "Application Installation" phase.
.NOTES
    It's good practice to call this at the start of each distinct phase for clear reporting.
#>
function Initialize-PhaseSummary {
    param(
        [string]$PhaseName
    )
    if (-not $PhaseName) {
        Write-Log "PhaseName cannot be empty for Initialize-PhaseSummary." "ERROR"
        return
    }
    $global:PhaseSummaries[$PhaseName] = @{
        Success        = 0
        Warning        = 0
        Error          = 0
        ItemsAttempted = 0
        Details        = [System.Collections.Generic.List[string]]::new() # Stores detailed messages for the phase
    }
    Write-Log "Initialized summary for phase: $PhaseName" "DEBUG"
}

<#
.SYNOPSIS
    Updates the outcome counters and detail messages for a specified script phase.
.DESCRIPTION
    Increments the success, warning, or error counter for a given phase in $global:PhaseSummaries.
    It also increments the 'ItemsAttempted' counter for 'Success' and 'Error' outcomes, assuming these represent distinct items processed.
    An optional detail message can be provided, which is added to a list for that phase. These details can be displayed
    in the final summary if debug logging is enabled, providing more context for individual successes or failures.
    If the specified phase hasn't been initialized yet (e.g., via Initialize-PhaseSummary), this function will
    initialize it implicitly to prevent errors, along with a warning log.
.PARAMETER PhaseName
    The name of the phase to update (e.g., "Apps", "Fonts"). Must match a name used with Initialize-PhaseSummary for explicit control,
    though implicit initialization is supported.
.PARAMETER OutcomeType
    The type of outcome to record. Must be one of 'Success', 'Warning', or 'Error'. This is validated by ValidateSet.
.PARAMETER Increment
    The value to increment the specified outcome counter by. Defaults to 1.
.PARAMETER DetailMessage
    An optional string providing specific details about the outcome (e.g., name of the app that succeeded/failed, or a specific error encountered).
    This message will be stored and can be shown in the final summary if debug logging is enabled. The OutcomeType is automatically prepended to this message.
.EXAMPLE
    PS C:\> Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Success" -DetailMessage "Installed Visual Studio Code."
    This records a success for the "Apps" phase, increments ItemsAttempted, and adds a detail message.

.EXAMPLE
    PS C:\> Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Error" -DetailMessage "Failed to install Fira Code: Download error."
    This records an error for the "Fonts" phase, increments ItemsAttempted, and adds a specific failure message.

.EXAMPLE
    PS C:\> Update-PhaseOutcome -PhaseName "System Checks" -OutcomeType "Warning" -DetailMessage "Disk space low."
    This records a warning for the "System Checks" phase. ItemsAttempted is not incremented for warnings.
.NOTES
    Warnings typically do not increment 'ItemsAttempted' as they might refer to general conditions or issues with items already counted.
#>
function Update-PhaseOutcome {
    param(
        [string]$PhaseName,
        [ValidateSet('Success', 'Warning', 'Error')][string]$OutcomeType,
        [int]$Increment = 1,
        [string]$DetailMessage = $null
    )
    if (-not ($global:PhaseSummaries.ContainsKey($PhaseName))) {
        # Implicitly initialize if called before explicit initialization for robustness
        Initialize-PhaseSummary -PhaseName $PhaseName
        Write-Log "Implicitly initialized summary for phase '$PhaseName' due to Update-PhaseOutcome call." "WARNING"
    }
    $global:PhaseSummaries[$PhaseName][$OutcomeType] += $Increment

    # ItemsAttempted is incremented for Success and Error, as these usually represent processed items.
    # Warnings might be general or apply to an already counted item, so they don't increment ItemsAttempted here.
    if ($OutcomeType -ne 'Warning') {
        $global:PhaseSummaries[$PhaseName].ItemsAttempted += $Increment
    }

    if ($DetailMessage) {
        # Prepend the outcome type to the detail message for clarity in the log.
        $global:PhaseSummaries[$PhaseName].Details.Add("[$OutcomeType] $DetailMessage")
    }
    Write-Log "Updated phase '$PhaseName': $OutcomeType +$Increment. Items Attempted: $($global:PhaseSummaries[$PhaseName].ItemsAttempted)" "DEBUG"
}

<#
.SYNOPSIS
    Writes a timestamped message to the console and to the log file.
.DESCRIPTION
    This function is the primary method for logging script activity. It prefixes messages with a timestamp
    and log level. Messages are displayed on the console with colors corresponding to their severity
    (e.g., Red for ERROR, Yellow for WARNING, Green for SUCCESS). All messages, regardless of level,
    are written to the configured log file.

    DEBUG level messages provide detailed information useful for troubleshooting. They are always written
    to the log file but only appear on the console if debug logging has been explicitly enabled via
    the `Enable-DebugLogging` function. This prevents verbose console output during normal operation.

    The function also maintains global counters ($global:ErrorCount, $global:WarningCount, $global:SuccessCount)
    for ERROR, WARNING, and SUCCESS messages respectively. These counters are used in the final script summary.
.PARAMETER Message
    The message string to be logged. Mandatory.
.PARAMETER Level
    The severity level of the message. This must be one of the values defined in the `LogLevel` enum
    (INFO, WARNING, ERROR, SUCCESS, DEBUG). Defaults to INFO if not specified.
.EXAMPLE
    PS C:\> Write-Log -Message "Application installation started." -Level INFO
    This logs an informational message to the console (White) and the log file.

.EXAMPLE
    PS C:\> Write-Log "Failed to download package: PackageName" -Level ERROR
    This logs an error message to the console (Red) and the log file, and increments the global error counter.

.EXAMPLE
    PS C:\> Write-Log "Configuration value 'X' set to 'Y'." -Level DEBUG
    This logs a debug message. It will always appear in the log file. If `Enable-DebugLogging` has been
    called, it will also appear on the console (Gray). It does not affect global status counters.
.NOTES
    The function includes a fallback mechanism: if the primary log file ($global:LogPath) is inaccessible
    (e.g., locked by another process), it will attempt to write the log entry to a fallback file
    ($global:LogFallbackPath) in the user's temporary directory.
    The global log path ($global:LogPath) must be set by calling `Initialize-Logging` before this function is used.
#>
function Write-Log {
    param(
        [string]$Message,
        [LogLevel]$Level = [LogLevel]::INFO
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"

    # Console output formatting based on level
    switch ($Level) {
        "INFO" { Write-Host $logEntry -ForegroundColor White }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow; $global:WarningCount++ }
        "ERROR" { Write-Host $logEntry -ForegroundColor Red; $global:ErrorCount++ }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green; $global:SuccessCount++ }
        "DEBUG" {
            if ($global:DebugLoggingEnabled) { Write-Host $logEntry -ForegroundColor Gray }
            # DEBUG messages do not increment overall status counters (ErrorCount, WarningCount, SuccessCount)
        }
    }

    try {
        # All messages, including DEBUG, are written to the log file.
        Add-Content -Path $global:LogPath -Value $logEntry -Encoding UTF8
    }
    catch {
        # Fallback mechanism if the primary log file is inaccessible (e.g., locked).
        Add-Content -Path $global:LogFallbackPath -Value $logEntry -Encoding UTF8
    }
}

<#
.SYNOPSIS
    Initializes the logging system by setting up the log file and writing a header.
.DESCRIPTION
    This function should be called once at the very beginning of the main script execution.
    It performs several critical setup tasks:
    1. Sets the global log file path ($global:LogPath) based on the provided parameter.
    2. Creates the log directory if it doesn't already exist.
    3. Writes an initial header to the log file, including the script start time and current PowerShell version.
    This ensures that logging can proceed correctly for the rest of the script.
.PARAMETER LogPath
    The full path to the log file that will be created and used for the script session (e.g., "C:\Logs\MyScriptLog.txt").
    This parameter is mandatory.
.EXAMPLE
    PS C:\> Initialize-Logging -LogPath "C:\Temp\PostInstallLog.txt"
    This command sets up the logging to use "C:\Temp\PostInstallLog.txt", creates the "C:\Temp" directory if needed,
    and writes a standard header to the log file.
.NOTES
    The main script (e.g., post_install.ps1) is responsible for determining and providing a valid `LogPath`.
    This function uses `Write-Host` for its own internal DEBUG messages (before `Write-Log` is fully ready or to avoid recursion)
    to provide visibility into its operations if needed, though these `Write-Host` messages do not go to the log file.
    The success message "Logging initialized successfully." is now used instead of "Logging initialized".
#>
function Initialize-Logging {
    param(
        [string]$LogPath
    )
    $global:LogPath = $LogPath # Set the global log path variable
    # Using Write-Host for initial debug output as Write-Log might not be fully available or could recurse.
    Write-Host "DEBUG: Initialize-Logging - Started. Received LogPath: '$LogPath'"
    Write-Host "DEBUG: Initialize-Logging - Global LogPath now set to: '$global:LogPath'"
    try {
        # Determine and create the log directory if it doesn't exist
        Write-Host "DEBUG: Initialize-Logging - Preparing to determine target log directory from: '$global:LogPath'"
        $dir = Split-Path -Parent $global:LogPath
        Write-Host "DEBUG: Initialize-Logging - Target log directory determined as: '$dir'"
        if (-not (Test-Path $dir)) {
            Write-Host "DEBUG: Initialize-Logging - Directory '$dir' does not exist. Attempting to create."
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Host "DEBUG: Initialize-Logging - Directory creation attempt complete."
        }

        # Prepare and write the log file header
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
        # Use Write-Log for the first official log entry after header is set
        Write-Log "Logging initialized successfully." "SUCCESS"
    }
    catch {
        # If logging initialization fails (e.g., cannot write to LogPath), write to a fallback log file in the temp directory.
        Write-Host "CRITICAL: Initialize-Logging - ERROR CAUGHT: $($_.Exception.Message). Fallback log will be used." -ForegroundColor Red
        # Attempt to write essential failure information to the fallback log.
        Add-Content -Path $global:LogFallbackPath -Value "[CRITICAL FALLBACK LOG] Logging initialization failed for '$global:LogPath': $($_.Exception.Message)" -Encoding UTF8
        Add-Content -Path $global:LogFallbackPath -Value $header -Encoding UTF8 # Also write header to fallback, if possible
    }
}

<#
.SYNOPSIS
    Displays a comprehensive summary of the script execution, including per-phase and overall statistics.
.DESCRIPTION
    This function should be called at the very end of the main script.
    It calculates and displays the total script duration.
    It then iterates through any phase-specific summaries that were recorded using `Initialize-PhaseSummary`
    and `Update-PhaseOutcome`. For each phase, it prints the number of items attempted, successes, warnings, and errors.
    If debug logging (`$global:DebugLoggingEnabled`) is active and a phase has detailed messages, these details are also printed.

    After the phase summaries, it presents an overall summary of successes, warnings, and errors based on the
    global counters that `Write-Log` maintains. Finally, it reminds the user of the primary log file location
    and mentions if the fallback log was used at any point.
.EXAMPLE
    PS C:\> Show-InstallationSummary
    This command displays both per-phase and overall summaries of all operations performed during the script run,
    writing the output to both the console and the log file via Write-Log.
.NOTES
    This function relies on several global variables being set and updated throughout the script:
    `$global:StartTime` (set at script start),
    `$global:ErrorCount`, `$global:WarningCount`, `$global:SuccessCount` (updated by `Write-Log`),
    `$global:PhaseSummaries` (managed by `Initialize-PhaseSummary` and `Update-PhaseOutcome`),
    `$global:LogPath`, and `$global:LogFallbackPath`.
    Variable casing for $PascalCase is preferred for global variables for consistency, though existing $camelCase are retained.
#>
function Show-InstallationSummary {
    $endTime = Get-Date
    $duration = $endTime - $global:StartTime

    # --- Per-Phase Summaries ---
    if ($global:PhaseSummaries.Count -gt 0) {
        Write-Log "--------------------------------------------------------------------------------" "INFO"
        Write-Log "                         >>> Phase Summaries <<<" "INFO"
        Write-Log "--------------------------------------------------------------------------------" "INFO"
        # Iterate through phase summaries, sorted by name for consistent output
        foreach ($phaseEntry in $global:PhaseSummaries.GetEnumerator() | Sort-Object Name) {
            $phaseName = $phaseEntry.Name
            $stats = $phaseEntry.Value
            Write-Log "" "INFO" # Blank line for spacing
            Write-Log "--- Phase Summary: $phaseName ---" "INFO"
            Write-Log "Items Attempted: $($stats.ItemsAttempted)" "INFO"
            Write-Log "  Success: $($stats.Success)" "SUCCESS"
            Write-Log "  Warning: $($stats.Warning)" "WARNING"
            Write-Log "  Error:   $($stats.Error)" "ERROR"

            # Display detailed messages for the phase if debug logging is enabled and details exist
            if ($stats.Details.Count -gt 0 -and $global:DebugLoggingEnabled) {
                Write-Log "  Details for ${phaseName}:" "DEBUG"
                foreach ($detail in $stats.Details) {
                    Write-Log "    $detail" "DEBUG" # Detail message already includes its original outcome type
                }
            }
            Write-Log "--- End of Phase: ${phaseName} ---" "INFO"
        }
        Write-Log "--------------------------------------------------------------------------------" "INFO"
    }


    # --- Overall Summary ---
    Write-Log "" "INFO" # Blank line for spacing
    Write-Log "=== OVERALL SUMMARY ===" "INFO"
    Write-Log "Total Duration: $($duration.ToString('hh\:mm\:ss'))" "INFO"
    Write-Log "Overall Success Count (from Write-Log): $global:SuccessCount" "SUCCESS"
    Write-Log "Overall Warning Count (from Write-Log): $global:WarningCount" "WARNING"
    Write-Log "Overall Error Count (from Write-Log):   $global:ErrorCount" "ERROR"
    Write-Log "Log File Location: $global:LogPath" "INFO"
    if (Test-Path $global:LogFallbackPath) {
        # Inform user if the fallback log was used at any point
        Write-Log "Fallback Log: $global:LogFallbackPath (used due to file access errors for primary log)" "WARNING"
    }
    Write-Log "=== END OF SCRIPT SUMMARY ===" "INFO"
}

# Write-Host "DEBUG: logging.ps1 - End of script execution. All logging functions should be defined now." # Removed for cleaner module loading
# Export all public functions for use by other modules/scripts
Export-ModuleMember -Function Write-Log, Initialize-Logging, Show-InstallationSummary, Enable-DebugLogging, Initialize-PhaseSummary, Update-PhaseOutcome
