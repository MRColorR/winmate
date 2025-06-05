<#!
.SYNOPSIS
    Cleanup operations after all tasks are complete
#>

function Invoke-Cleanup {
    Write-Log "Performing cleanup tasks..." "INFO"

    try {
        $tempPaths = @(
            "$env:TEMP\*",
            "$env:LOCALAPPDATA\Temp\*"
        )

        foreach ($path in $tempPaths) {
            Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-1) } |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }

        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        Write-Log "Temporary files and paths refreshed." "SUCCESS"
    } catch {
        Write-Log "Cleanup encountered an error: $_" "WARNING"
    }
}

Export-ModuleMember -Function *
