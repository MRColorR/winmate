<#!
.SYNOPSIS
    Handles configuration loading and validation.
#>

function Get-Configuration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Write-Log "Loading configuration from: $Path" "INFO"

    if (-not (Test-Path $Path)) {
        Write-Log "Configuration file not found: $Path" "ERROR"
        throw "Missing configuration file."
    }

    try {
        $json = Get-Content -Raw -Path $Path | ConvertFrom-Json
        Write-Log "Configuration successfully loaded" "SUCCESS"
        return $json
    } catch {
        Write-Log "Failed to parse configuration: $_" "ERROR"
        throw "Invalid configuration format."
    }
}

function Test-Configuration {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Config
    )

    Write-Log "Validating configuration structure..." "INFO"
    $validationErrors = [System.Collections.Generic.List[string]]::new()

    # 1. Check for required top-level sections
    $requiredTopLevelSections = @('debloat', 'fonts', 'apps', 'metadata')
    foreach ($sectionName in $requiredTopLevelSections) {
        if (-not ($Config.PSObject.Properties.Name -contains $sectionName)) {
            $validationErrors.Add("CRITICAL: Configuration missing top-level section: '$sectionName'.")
        }
    }

    # If fundamental sections are missing, stop further validation that might depend on them.
    if ($validationErrors.Count -gt 0) {
        foreach ($err in $validationErrors) { Write-Log $err "ERROR" }
        throw "Configuration validation failed due to missing top-level sections."
    }

    # 2. Validate structure of 'debloat', 'fonts', 'apps'
    $phaseSections = @('debloat', 'fonts', 'apps') # Removed 'settings'
    foreach ($sectionName in $phaseSections) {
        $section = $Config.$sectionName # Direct property access
        if ($null -eq $section) {
            $validationErrors.Add("CRITICAL: Section '$sectionName' is unexpectedly null after initial check (should have been caught by top-level check).")
            continue
        }

        # Check for 'enabled' key (boolean)
        if (-not ($section.PSObject.Properties.Name -contains 'enabled')) {
            $validationErrors.Add("CRITICAL: Section '$sectionName' is missing 'enabled' key.")
        } elseif ($section.enabled -isnot [bool]) {
            $validationErrors.Add("CRITICAL: Section '$sectionName.enabled' must be a boolean (true/false). Found: '$($section.enabled)'")
        }

        # Check for 'description' key (string)
        if (-not ($section.PSObject.Properties.Name -contains 'description')) {
            $validationErrors.Add("CRITICAL: Section '$sectionName' is missing 'description' key.")
        } elseif ($section.description -isnot [string]) {
            $validationErrors.Add("CRITICAL: Section '$sectionName.description' must be a string. Found: '$($section.description)'")
        }

        # 3. Specific checks for 'fonts' section
        if ($sectionName -eq 'fonts' -and ($section.PSObject.Properties.Name -contains 'enabled' -and $section.enabled -eq $true)) {
            if (-not ($section.PSObject.Properties.Name -contains 'fonts-list' -and $null -ne $section.'fonts-list' -and $section.'fonts-list' -is [System.Management.Automation.PSCustomObject])) {
                $validationErrors.Add("CRITICAL: Section 'fonts' is enabled but 'fonts-list' is missing or not an object.")
            } else {
                $fontsList = $section.'fonts-list'

                # Validate 'nerdfonts' structure
                if (-not ($fontsList.PSObject.Properties.Name -contains 'nerdfonts' -and $null -ne $fontsList.nerdfonts -and $fontsList.nerdfonts -is [System.Management.Automation.PSCustomObject])) {
                    $validationErrors.Add("CRITICAL: 'fonts.fonts-list.nerdfonts' is missing or not an object.")
                } else {
                    if (-not ($fontsList.nerdfonts.PSObject.Properties.Name -contains 'enabled' -and $fontsList.nerdfonts.enabled -is [bool])) {
                        $validationErrors.Add("CRITICAL: 'fonts.fonts-list.nerdfonts' is missing 'enabled' (boolean) key.")
                    }
                    if (-not ($fontsList.nerdfonts.PSObject.Properties.Name -contains 'fonts' -and $fontsList.nerdfonts.fonts -is [array])) {
                        $validationErrors.Add("CRITICAL: 'fonts.fonts-list.nerdfonts' is missing 'fonts' (array) key.")
                    }
                }

                # Validate 'custom' structure
                if (-not ($fontsList.PSObject.Properties.Name -contains 'custom' -and $null -ne $fontsList.custom -and $fontsList.custom -is [array])) {
                    $validationErrors.Add("CRITICAL: 'fonts.fonts-list.custom' is missing or not an array.")
                } else {
                    foreach ($customFontItem in $fontsList.custom) {
                        if ($null -eq $customFontItem -or $customFontItem -isnot [System.Management.Automation.PSCustomObject]) {
                            $validationErrors.Add("CRITICAL: An item in 'fonts.fonts-list.custom' is not a valid object.")
                            continue # Skip further checks for this item
                        }
                        if (-not ($customFontItem.PSObject.Properties.Name -contains 'name' -and $customFontItem.name -is [string] -and -not([string]::IsNullOrWhiteSpace($customFontItem.name)))) {
                            $validationErrors.Add("CRITICAL: Item in 'fonts.fonts-list.custom' is missing 'name' (non-empty string) key. Item: $($customFontItem | ConvertTo-Json -Depth 1 -Compress)")
                        }
                        if (-not ($customFontItem.PSObject.Properties.Name -contains 'url' -and $customFontItem.url -is [string] -and -not([string]::IsNullOrWhiteSpace($customFontItem.url)))) {
                            $validationErrors.Add("CRITICAL: Item in 'fonts.fonts-list.custom' (name: '$($customFontItem.name)') is missing 'url' (non-empty string) key.")
                        }
                        if (-not ($customFontItem.PSObject.Properties.Name -contains 'enabled' -and $customFontItem.enabled -is [bool])) {
                            $validationErrors.Add("CRITICAL: Item in 'fonts.fonts-list.custom' (name: '$($customFontItem.name)') is missing 'enabled' (boolean) key.")
                        }
                    }
                }
            }
        }

        # 4. Specific checks for 'apps' section
        if ($sectionName -eq 'apps' -and ($section.PSObject.Properties.Name -contains 'enabled' -and $section.enabled -eq $true)) {
            if (-not ($section.PSObject.Properties.Name -contains 'apps-list' -and $null -ne $section.'apps-list' -and $section.'apps-list' -is [System.Management.Automation.PSCustomObject])) {
                $validationErrors.Add("CRITICAL: Section 'apps' is enabled but 'apps-list' is missing or not an object.")
            } else {
                $appsList = $section.'apps-list'
                # Iterate over each application defined in apps-list
                foreach ($appName in $appsList.PSObject.Properties.Name) {
                    $appEntry = $appsList.$appName
                    if ($null -eq $appEntry -or $appEntry -isnot [System.Management.Automation.PSCustomObject]) {
                        $validationErrors.Add("CRITICAL: Entry '$appName' in 'apps.apps-list' is not a valid object.")
                        continue # Skip further checks for this app entry
                    }

                    # Check for 'remove' key (boolean)
                    if (-not ($appEntry.PSObject.Properties.Name -contains 'remove' -and $appEntry.remove -is [bool])) {
                        $validationErrors.Add("CRITICAL: App '$appName' in 'apps.apps-list' is missing 'remove' (boolean) key.")
                    }
                    # Check for 'install' key (boolean)
                    if (-not ($appEntry.PSObject.Properties.Name -contains 'install' -and $appEntry.install -is [bool])) {
                        $validationErrors.Add("CRITICAL: App '$appName' in 'apps.apps-list' is missing 'install' (boolean) key.")
                    }
                    # Check for 'provider' key (string, non-empty)
                    if (-not ($appEntry.PSObject.Properties.Name -contains 'provider' -and $appEntry.provider -is [string] -and -not([string]::IsNullOrWhiteSpace($appEntry.provider)))) {
                        $validationErrors.Add("CRITICAL: App '$appName' in 'apps.apps-list' is missing 'provider' (non-empty string) key.")
                    }
                    # Check for 'package_id' key (string, non-empty)
                    if (-not ($appEntry.PSObject.Properties.Name -contains 'package_id' -and $appEntry.package_id -is [string] -and -not([string]::IsNullOrWhiteSpace($appEntry.package_id)))) {
                        $validationErrors.Add("CRITICAL: App '$appName' in 'apps.apps-list' is missing 'package_id' (non-empty string) key.")
                    }
                    # Check for 'description' key (string)
                    if (-not ($appEntry.PSObject.Properties.Name -contains 'description' -and $appEntry.description -is [string])) {
                        $validationErrors.Add("CRITICAL: App '$appName' in 'apps.apps-list' is missing 'description' (string) key.")
                    }
                }
            }
        }

        # 'settings' section validation removed
    }

    if ($validationErrors.Count -gt 0) {
        foreach ($err in $validationErrors) { Write-Log $err "ERROR" }
        throw "Configuration validation failed. Please check errors above."
    } else {
        Write-Log "Configuration structure validated successfully." "SUCCESS"
    }
}

Export-ModuleMember -Function *
