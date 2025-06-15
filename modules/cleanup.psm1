<#
.SYNOPSIS
    Performs post-script cleanup tasks, including removing old temporary files and refreshing the system PATH.
.DESCRIPTION
    This module contains the Invoke-Cleanup function, which is designed to be run at the end of the main
    post-installation script. Its primary purposes are:
    1. To clean up general temporary files from common locations (`$env:TEMP` and `$env:LOCALAPPDATA\Temp`).
       It specifically targets files older than one day to avoid removing files actively in use by
       concurrent processes or very recent script operations.
    2. To refresh the current PowerShell session's `$env:Path` variable by re-reading it from the system
       (Machine and User environment variables). This can be useful if package managers installed by the script
       (like Chocolatey or Scoop) have modified the persistent PATH but the current session doesn't yet reflect those changes.

    The function logs its actions and handles errors gracefully, typically logging them as warnings.
#>

<#
.SYNOPSIS
    Performs post-script cleanup tasks, focusing on old temporary files and refreshing the PATH environment variable.
.DESCRIPTION
    The function executes two main cleanup actions:
    1.  **Temporary File Cleanup:** It iterates through common temporary file locations
        (`$env:TEMP` and `$env:LOCALAPPDATA\Temp`). In these locations, it recursively finds and removes
        files and folders that were created more than one day ago. This is a general cleanup and aims
        to free up disk space from old temp files, not specifically targeting files created only by this script suite.
        Specific temporary files/folders created by other modules (e.g., for app downloads or font extraction)
        are typically self-cleaned by those modules in their `finally` blocks.
    2.  **PATH Environment Variable Refresh:** It rebuilds the current session's `$env:Path` by concatenating
        the Machine and User PATH environment variables. This can help ensure that any PATH modifications made by
        installers during the script's execution (e.g., by Chocolatey or Scoop) are reflected in the current session
        if it were to continue or if subsequent commands rely on it.

    Errors during file removal are silently continued for individual items to ensure the function completes as much as possible.
    A general warning is logged if any part of the cleanup process encounters an issue.
.EXAMPLE
    PS C:\> Invoke-Cleanup
    This command will attempt to remove temporary files older than one day from standard temp locations
    and then refresh the session's PATH variable.
.NOTES
    This function is typically intended to be run at the very end of the main post-installation script.
    The file removal uses `Remove-Item -Recurse -Force` and includes `-ErrorAction SilentlyContinue` for
    individual item errors, so failure to remove one file won't stop others.
    The PATH refresh affects only the current PowerShell session. For system-wide persistence of PATH changes
    made by installers, a system restart or new session is usually required.
#>
function Invoke-Cleanup {
    Write-Log "Performing post-script cleanup tasks..." "INFO"

    try {
        # Define paths for general temporary file cleanup.
        $tempFileLocations = @(
            Join-Path $env:TEMP "*", # All files and folders directly under TEMP
            Join-Path $env:LOCALAPPDATA "Temp\*" # All files and folders directly under Local AppData Temp
        )

        Write-Log "Attempting to clean up temporary files older than 1 day from common locations..." "INFO"
        foreach ($locationPattern in $tempFileLocations) {
            Write-Log "Checking location: $locationPattern" "DEBUG"
            # Get items, filter by age, then remove.
            # Silently continue on errors for Get-ChildItem and Remove-Item to avoid halting on locked files.
            Get-ChildItem -Path $locationPattern -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-1) } |
                ForEach-Object {
                    Write-Log "Removing old temp item: $($_.FullName)" "DEBUG"
                    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
        }
        Write-Log "General temporary file cleanup attempt complete." "INFO"

        # Refresh $env:Path for the current session.
        # This ensures that if any installers (like Chocolatey or Scoop) updated the system/user PATH,
        # the current session reflects these changes for any immediate post-script interactive use or further scripting.
        Write-Log "Refreshing session PATH environment variable..." "INFO"
        $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
        $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
        $newPath = "$machinePath;$userPath"
        # Normalize the path by splitting and rejoining to remove potential duplicates or empty entries, though this simple concatenation is common.
        $env:Path = $newPath
        Write-Log "Session PATH environment variable refreshed." "SUCCESS" # Changed from "Temporary files and paths refreshed"
    }
    catch {
        # Catch any unexpected error during the cleanup process itself.
        Write-Log "Cleanup process encountered an error: $($_.Exception.Message)" "WARNING"
    }
}

Export-ModuleMember -Function Invoke-Cleanup
