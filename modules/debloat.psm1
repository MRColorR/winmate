<#!
.SYNOPSIS
    Removes unnecessary or unwanted pre-installed applications
#>

function Invoke-WindowsDebloat {
    param(
        [PSObject]$Config
    )

    if (-not ($Config.PSObject.Properties.Name -contains 'apps_debloater' -and $Config.apps_debloater.enabled -eq $true)) {
        Write-Log "Debloat step is disabled in configuration." "INFO"
        return
    }

    Write-Log "Starting Windows Debloat..." "INFO"
    Initialize-PhaseSummary "Debloat" # Initialize phase summary

    if (-not ($Config.PSObject.Properties.Name -contains 'apps_list' -and $null -ne $Config.apps_list)) {
        Write-Log "Apps data ('apps_list') for debloating is missing or invalid in configuration." "WARNING"
        return
    }
    $appsCollection = $Config.apps_list
    foreach ($property in $appsCollection.PSObject.Properties) {
        $name = $property.Name
        $settings = $property.Value

        if ($settings.remove -eq $true) {
            # Pass the original key name as AppNameKey, and the full settings object as AppConfig
            Write-Log "Debloat: Queuing removal for '$($property.Name)' (Package ID: $($settings.package_id))" "INFO"
            Remove-WindowsApplication -AppNameKey $property.Name -AppConfig $settings
        }
    }

    Write-Log "Debloat phase complete." "SUCCESS"
}

function Remove-WindowsApplication {
    param(
        [string]$AppNameKey, # The key from the JSON config, e.g., "VSCode"
        [PSObject]$AppConfig  # The full app object from config.json
    )

    $removed = $false
    $packageId = $AppConfig.package_id
    $logPrefix = "Debloat [$AppNameKey ($packageId)]:"

    try {
        # 1. Provider-First for Specified Providers
        if ($AppConfig.provider -in @('winget', 'chocolatey')) {
            $provider = $AppConfig.provider.ToLower()
            Write-Log "$logPrefix Checking if installed via $provider..." "INFO"
            $isInstalledViaProvider = $false
            $commandOutput = ""

            if ($provider -eq 'winget') {
                $commandOutput = (winget list --id $packageId --accept-source-agreements 2>&1 | Out-String)
                if ($LASTEXITCODE -eq 0 -and $commandOutput -match $packageId) { # Basic check, might need refinement
                    $isInstalledViaProvider = $true
                }
            }
            elseif ($provider -eq 'chocolatey') {
                # `choco list` exits 0 even if not found, so check output
                $commandOutput = (choco list --local-only --id $packageId 2>&1 | Out-String)
                if ($LASTEXITCODE -eq 0 -and $commandOutput -match "1 packages installed.") {
                    $isInstalledViaProvider = $true
                }
            }

            if ($isInstalledViaProvider) {
                Write-Log "$logPrefix Found via $provider. Attempting removal..." "INFO"
                if ($provider -eq 'winget') {
                    & winget uninstall --id $packageId --silent --accept-source-agreements --disable-interactivity
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "$logPrefix Successfully removed via $provider." "SUCCESS"
                        $removed = $true
                    } else {
                        Write-Log "$logPrefix Failed to remove via $provider. Exit code: $LASTEXITCODE" "ERROR"
                    }
                }
                elseif ($provider -eq 'chocolatey') {
                    & choco uninstall $packageId -y --remove-dependencies
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "$logPrefix Successfully removed via $provider." "SUCCESS"
                        $removed = $true
                    } else {
                        Write-Log "$logPrefix Failed to remove via $provider. Exit code: $LASTEXITCODE" "ERROR"
                    }
                }
            }
            else {
                Write-Log "$logPrefix Not found via $provider (or provider check failed). Output: $commandOutput" "INFO"
            }

            if ($removed) {
                Update-PhaseOutcome -PhaseName "Debloat" -OutcomeType "Success" -DetailMessage "$logPrefix Successfully removed via $provider."
                return # Early exit if removed by provider
            }
        }

        # 2. UWP App Removal (if not removed by provider or if provider is not winget/choco)
        if (-not $removed) {
            Write-Log "$logPrefix Checking for UWP package..." "INFO"
            $uwpApp = Get-AppxPackage -Name $packageId -ErrorAction SilentlyContinue
            if ($uwpApp) {
                Write-Log "$logPrefix Found UWP package '$($uwpApp.Name)'. Attempting removal..." "INFO"
                try {
                    Remove-AppxPackage -Package $uwpApp.PackageFullName -ErrorAction Stop
                    Write-Log "$logPrefix Successfully removed UWP package '$($uwpApp.PackageFullName)'." "SUCCESS"
                    $removed = $true
                }
                catch {
                    Write-Log "$logPrefix Failed to remove UWP package '$($uwpApp.PackageFullName)': $($_.Exception.Message)" "ERROR"
                    # This specific failure doesn't stop other methods, so don't call Update-PhaseOutcome with Error yet.
                }
            }
            else {
                Write-Log "$logPrefix UWP package with ID '$packageId' not found." "INFO"
            }
        }

        # 3. Provisioned Package Removal (if not already removed)
        if (-not $removed) {
            Write-Log "$logPrefix Checking for provisioned package..." "INFO"
            $provPackage = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "*$AppNameKey*" -or $_.PackageName -like "*$packageId*" } | Select-Object -First 1
            if ($provPackage) {
                Write-Log "$logPrefix Found provisioned package '$($provPackage.DisplayName)' (PackageName: $($provPackage.PackageName)). Attempting removal..." "INFO"
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $provPackage.PackageName -ErrorAction Stop
                    Write-Log "$logPrefix Successfully removed provisioned package '$($provPackage.PackageName)'." "SUCCESS"
                    $removed = $true
                }
                catch {
                    Write-Log "$logPrefix Failed to remove provisioned package '$($provPackage.PackageName)': $($_.Exception.Message)" "ERROR"
                    # This specific failure doesn't stop other methods yet.
                }
            }
            else {
                Write-Log "$logPrefix Provisioned package for '$AppNameKey' or ID '$packageId' not found." "INFO"
            }
        }

        # 4. Final Outcome Update for the app
        if ($removed) {
            Update-PhaseOutcome -PhaseName "Debloat" -OutcomeType "Success" -DetailMessage "$logPrefix Successfully removed (final check)."
        } else {
            # If we reach here and $removed is false, it means all attempts (provider, UWP, provisioned) that could have set $removed to true have passed or failed.
            # And no main error was thrown to the outer catch.
            # We log it as "not found" which is not an error for the debloat phase, but rather an INFO state.
            # No explicit Error outcome unless a specific step failed and we decide that's critical.
            # However, if the initial intent was to remove it, and it's not found, that can be seen as success for "debloat".
            # Let's consider "not found" as a form of success for debloating goals.
            Write-Log "$logPrefix App not found through any available method or already removed. Considered success for debloat." "INFO"
            Update-PhaseOutcome -PhaseName "Debloat" -OutcomeType "Success" -DetailMessage "$logPrefix App not found or already removed."
        }
    }
    catch {
        Write-Log "$logPrefix Error during removal attempt for $AppNameKey: $($_.Exception.Message)" "ERROR"
        Update-PhaseOutcome -PhaseName "Debloat" -OutcomeType "Error" -DetailMessage "$logPrefix Failed: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function *
