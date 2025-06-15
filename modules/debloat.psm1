<#
.SYNOPSIS
    Handles removal of unnecessary or unwanted pre-installed applications (debloating).
.DESCRIPTION
    This module provides functions to identify and remove applications based on the
    'apps_list' section of the configuration file, specifically targeting entries
    marked with 'remove: true'. It supports various removal methods including
    package managers (Winget, Chocolatey) and direct removal of UWP/AppX packages.
#>

<#
.SYNOPSIS
    Orchestrates the Windows debloating process based on configuration.
.DESCRIPTION
    Checks if debloating is enabled in the configuration via the 'apps_debloater.enabled' flag.
    If enabled, it iterates through the 'apps_list' defined in the configuration. For each application
    entry where the 'remove' property is set to true, it calls the 'Remove-WindowsApplication'
    function to attempt the uninstallation.
    This function also initializes the 'Debloat' phase summary for detailed logging and reporting.
.PARAMETER Config
    The main configuration object, which must contain an 'apps_debloater' section (with an 'enabled' boolean property)
    and an 'apps_list' section detailing the applications. This parameter is mandatory.
.EXAMPLE
    PS C:\> Invoke-WindowsDebloat -Config $loadedConfigObject
    This command starts the debloating process using the provided configuration object.
    It will log its actions and the outcomes of removal attempts.
.NOTES
    Relies on the 'Remove-WindowsApplication' function for the actual removal logic of each application.
    Logs the overall start and completion of the debloat phase.
    Phase summary for "Debloat" is initialized here. Individual app removal outcomes are updated by 'Remove-WindowsApplication'.
#>
function Invoke-WindowsDebloat {
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$Config
    )

    # Check if the debloat phase is enabled in the configuration.
    if (-not ($Config.PSObject.Properties.Name -contains 'apps_debloater' -and $Config.apps_debloater.enabled -eq $true)) {
        Write-Log "Debloat step is disabled in configuration." "INFO"
        return
    }

    Write-Log "Starting Windows Debloat phase..." "INFO"
    Initialize-PhaseSummary "Debloat" # Initialize phase summary for debloating operations.

    # Ensure the apps_list exists and is not null before proceeding.
    if (-not ($Config.PSObject.Properties.Name -contains 'apps_list' -and $null -ne $Config.apps_list)) {
        Write-Log "Apps data ('apps_list') for debloating is missing or invalid in configuration." "WARNING"
        Update-PhaseOutcome -PhaseName "Debloat" -OutcomeType "Warning" -DetailMessage "Apps data ('apps_list') missing or invalid."
        return
    }

    $appsCollection = $Config.apps_list
    # Iterate through each application defined in the apps_list.
    foreach ($property in $appsCollection.PSObject.Properties) {
        $appNameKey = $property.Name   # The key of the app in the config (e.g., "MicrosoftTeams")
        $appSettings = $property.Value # The configuration object for this specific app

        if ($appSettings.remove -eq $true) {
            Write-Log "Debloat: Queuing removal for '$appNameKey' (Package ID: $($appSettings.package_id))" "INFO"
            # Call Remove-WindowsApplication to handle the removal of the individual app.
            Remove-WindowsApplication -AppNameKey $appNameKey -AppConfig $appSettings
        }
    }

    Write-Log "Windows Debloat phase complete." "SUCCESS"
}

<#
.SYNOPSIS
    Attempts to remove a single specified Windows application using various methods.
.DESCRIPTION
    This function tries to uninstall an application identified by its 'AppNameKey' and defined by 'AppConfig'.
    The primary removal mechanism uses the 'package_id' from the 'AppConfig'.
    It prioritizes removal via a specified package manager provider ('winget', 'chocolatey') if listed in 'AppConfig.provider'.
    If the application is not removed by a provider (or if no standard provider is specified), the function then
    attempts to remove it as a UWP application (using Get-AppxPackage and Remove-AppxPackage) and subsequently
    as a provisioned package (using Get-AppxProvisionedPackage and Remove-AppxProvisionedPackage).
    Each step's outcome is logged, and the overall result of the removal attempt for the application
    updates the 'Debloat' phase summary (Success or Error).
.PARAMETER AppNameKey
    The application's unique key name from the configuration file (e.g., "Microsoft.YourPhone" or "Teams").
    This is primarily used for logging and identification purposes. Mandatory.
.PARAMETER AppConfig
    The PowerShell object containing the configuration details for the specific application to be removed.
    This object must include at least 'package_id' and optionally 'provider'. Mandatory.
.EXAMPLE
    PS C:\> $appToRemoveDetails = @{ package_id = "Microsoft.YourPhone"; provider = "winget" }
    PS C:\> Remove-WindowsApplication -AppNameKey "YourPhoneApp" -AppConfig $appToRemoveDetails
    This attempts to remove the "YourPhoneApp" using its package_id "Microsoft.YourPhone", prioritizing Winget.
.NOTES
    Uses a consistent logging prefix for all messages related to an app, including its name and package ID.
    Errors during specific removal methods (e.g., UWP removal failing after provider attempt) are logged,
    but the function continues to try other applicable methods.
    The final outcome (successfully removed, not found, or failed) is reported to the 'Debloat' phase summary.
    "Not found" is generally treated as a success for debloating purposes.
#>
function Remove-WindowsApplication {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppNameKey,
        [Parameter(Mandatory = $true)]
        [PSObject]$AppConfig
    )

    $removed = $false
    $packageId = $AppConfig.package_id
    $logPrefix = "Debloat [$AppNameKey ($packageId)]:"

    try {
        # Step 1: Try provider if specified (winget, chocolatey, scoop)
        if ($AppConfig.provider -in @('winget', 'chocolatey', 'scoop')) {
            $provider = $AppConfig.provider.ToLower()
            Write-Log "$logPrefix Attempting removal via $provider..." "INFO"
            $isInstalledViaProvider = $false
            $commandOutput = ""

            if ($provider -eq 'winget') {
                $commandOutput = (winget list --id $packageId --accept-source-agreements 2>&1 | Out-String)
                if ($LASTEXITCODE -eq 0 -and $commandOutput -match $packageId) {
                    $isInstalledViaProvider = $true
                }
            } elseif ($provider -eq 'chocolatey') {
                $commandOutput = (choco list --local-only --id $packageId 2>&1 | Out-String)
                if ($LASTEXITCODE -eq 0 -and $commandOutput -match "1 packages installed.") {
                    $isInstalledViaProvider = $true
                }
            } elseif ($provider -eq 'scoop') {
                $commandOutput = (scoop list $packageId 2>&1 | Out-String)
                if ($LASTEXITCODE -eq 0 -and $commandOutput -match $packageId) {
                    $isInstalledViaProvider = $true
                }
            }

            if ($isInstalledViaProvider) {
                if ($provider -eq 'winget') {
                    & winget uninstall --id $packageId --silent --accept-source-agreements --disable-interactivity
                } elseif ($provider -eq 'chocolatey') {
                    & choco uninstall $packageId -y --remove-dependencies
                } elseif ($provider -eq 'scoop') {
                    & scoop uninstall $packageId -g
                }
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "$logPrefix Successfully removed via $provider." "SUCCESS"
                    Update-PhaseOutcome -PhaseName "Debloat" -OutcomeType "Success" -DetailMessage "$logPrefix Successfully removed via $provider."
                    return
                } else {
                    Write-Log "$logPrefix Removal via $provider failed (exit code: $LASTEXITCODE). Will try fallback methods." "WARNING"
                }
            } else {
                Write-Log "$logPrefix Not found via $provider. Will try fallback methods." "INFO"
            }
        }

        # Step 2: Fallback to UWP removal
        $uwpApp = Get-AppxPackage -Name $packageId -ErrorAction SilentlyContinue
        if ($uwpApp) {
            Write-Log "$logPrefix Attempting UWP removal..." "INFO"
            try {
                Remove-AppxPackage -Package $uwpApp.PackageFullName -ErrorAction Stop
                Write-Log "$logPrefix Successfully removed as UWP package." "SUCCESS"
                Update-PhaseOutcome -PhaseName "Debloat" -OutcomeType "Success" -DetailMessage "$logPrefix Successfully removed as UWP package."
                return
            } catch {
                Write-Log "$logPrefix UWP removal failed: $($_.Exception.Message). Will try provisioned package." "WARNING"
            }
        }

        # Step 3: Fallback to provisioned package removal
        $provPackage = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*$AppNameKey*" -or $_.PackageName -like "*$packageId*" } | Select-Object -First 1
        if ($provPackage) {
            Write-Log "$logPrefix Attempting provisioned package removal..." "INFO"
            try {
                Remove-AppxProvisionedPackage -Online -PackageName $provPackage.PackageName -ErrorAction Stop
                Write-Log "$logPrefix Successfully removed provisioned package." "SUCCESS"
                Update-PhaseOutcome -PhaseName "Debloat" -OutcomeType "Success" -DetailMessage "$logPrefix Successfully removed provisioned package."
                return
            } catch {
                Write-Log "$logPrefix Provisioned package removal failed: $($_.Exception.Message)" "ERROR"
            }
        }

        # Step 4: If nothing worked, log as skipped/not found
        Write-Log "$logPrefix Application not found or could not be removed by any available method. Skipping." "WARNING"
        Update-PhaseOutcome -PhaseName "Debloat" -OutcomeType "Success" -DetailMessage "$logPrefix App not found or already removed."
    } catch {
        Write-Log "$logPrefix CRITICAL error during removal attempt: $($_.Exception.Message)" "ERROR"
        Update-PhaseOutcome -PhaseName "Debloat" -OutcomeType "Error" -DetailMessage "$logPrefix Failed (critical error): $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Invoke-WindowsDebloat, Remove-WindowsApplication
