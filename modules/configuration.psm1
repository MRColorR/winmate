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
    $requiredTopLevelSections = @('debloat', 'fonts', 'apps', 'settings', 'metadata')
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

    # 2. Validate structure of 'debloat', 'fonts', 'apps', 'settings'
    $phaseSections = @('debloat', 'fonts', 'apps', 'settings')
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
            if (-not ($section.PSObject.Properties.Name -contains 'fonts-list' -and $null -ne $section.'fonts-list')) {
                $validationErrors.Add("CRITICAL: Section 'fonts' is enabled but missing 'fonts-list' object.")
            } else {
                $fontsList = $section.'fonts-list'
                if (-not ($fontsList.PSObject.Properties.Name -contains 'nerdfonts' -and $null -ne $fontsList.nerdfonts)) {
                    $validationErrors.Add("CRITICAL: 'fonts.fonts-list' is missing 'nerdfonts' object.")
                } elseif (-not ($fontsList.nerdfonts.PSObject.Properties.Name -contains 'enabled' -and $fontsList.nerdfonts.enabled -is [bool])) {
                    $validationErrors.Add("CRITICAL: 'fonts.fonts-list.nerdfonts' is missing 'enabled' (boolean) key.")
                } elseif (-not ($fontsList.nerdfonts.PSObject.Properties.Name -contains 'fonts' -and $fontsList.nerdfonts.fonts -is [array])) {
                    $validationErrors.Add("CRITICAL: 'fonts.fonts-list.nerdfonts' is missing 'fonts' (array) key.")
                }

                if (-not ($fontsList.PSObject.Properties.Name -contains 'custom' -and $fontsList.custom -is [array])) {
                    $validationErrors.Add("CRITICAL: 'fonts.fonts-list' is missing 'custom' (array) key.")
                }
            }
        }

        # 4. Specific checks for 'apps' section
        if ($sectionName -eq 'apps' -and ($section.PSObject.Properties.Name -contains 'enabled' -and $section.enabled -eq $true)) {
            if (-not ($section.PSObject.Properties.Name -contains 'apps-list' -and $null -ne $section.'apps-list' -and $section.'apps-list' -is [System.Management.Automation.PSCustomObject])) { # apps-list should be an object containing app definitions
                $validationErrors.Add("CRITICAL: Section 'apps' is enabled but missing 'apps-list' object.")
            }
        }

        # 5. Specific checks for 'settings' section (OS system settings)
        # Note: The original config.json structure had settings.privacy, settings.performance, settings.ui
        # The new structure implies these (privacy, performance, ui) are directly under $Config.settings
        if ($sectionName -eq 'settings' -and ($section.PSObject.Properties.Name -contains 'enabled' -and $section.enabled -eq $true)) {
            $requiredSubSettings = @('privacy', 'performance', 'ui')
            foreach ($subSettingName in $requiredSubSettings) {
                if (-not ($section.PSObject.Properties.Name -contains $subSettingName -and $null -ne $section.$subSettingName -and $section.$subSettingName -is [System.Management.Automation.PSCustomObject])) {
                    $validationErrors.Add("CRITICAL: Section 'settings' is enabled but missing or has invalid sub-section '$subSettingName' (must be an object).")
                }
            }
        }
    }

    if ($validationErrors.Count -gt 0) {
        foreach ($err in $validationErrors) { Write-Log $err "ERROR" }
        throw "Configuration validation failed. Please check errors above."
    } else {
        Write-Log "Configuration structure validated successfully." "SUCCESS"
    }
}

Export-ModuleMember -Function *
