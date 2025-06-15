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
    $tokenPath = Join-Path (Split-Path $Path) 'token.json'
    if (-not (Test-Path $tokenPath)) {
        Write-Log "INFO: No token.json found in config directory. GitHub API requests will be unauthenticated unless a token is provided elsewhere." "INFO"
    }

    try {
        $json = Get-Content -Raw -Path $Path | ConvertFrom-Json
        Write-Log "Configuration successfully loaded" "SUCCESS"
        return $json
    }
    catch {
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
    $supportedProviders = @('winget', 'chocolatey', 'scoop', 'manual', 'msstore', 'github_release')

    # 1. Check for required top-level sections
    # Updated 'fonts_provisioner' to 'fonts_list' to match planned structure, assuming 'fonts_provisioner' was a typo or older name
    $requiredTopLevelSections = @('apps_debloater', 'apps_provisioner', 'apps_list', 'fonts_list', 'metadata')
    foreach ($sectionName in $requiredTopLevelSections) {
        if (-not ($Config.PSObject.Properties.Name -contains $sectionName)) {
            $validationErrors.Add("CRITICAL: Configuration missing top-level section: '$sectionName'.")
        }
    }

    if ($validationErrors.Count -gt 0) {
        foreach ($err in $validationErrors) { Write-Log $err "ERROR" }
        throw "Configuration validation failed due to missing top-level sections."
    }

    # 2. Validate structure of 'apps_debloater', 'fonts', 'apps_provisioner'
    $phaseSections = @('apps_debloater', 'fonts_provisioner', 'apps_provisioner')
    foreach ($sectionName in $phaseSections) {
        $section = $Config.$sectionName
        if ($null -eq $section) {
            $validationErrors.Add("CRITICAL: Section '$sectionName' is unexpectedly null after initial check (should have been caught by top-level check).")
            continue
        }
        if (-not ($section.PSObject.Properties.Name -contains 'enabled')) {
            $validationErrors.Add("CRITICAL: Section '$sectionName' is missing 'enabled' key.")
        }
        elseif ($section.enabled -isnot [bool]) {
            $validationErrors.Add("CRITICAL: Section '$sectionName.enabled' must be a boolean (true/false). Found: '$($section.enabled)'")
        }
        if (-not ($section.PSObject.Properties.Name -contains 'description')) {
            $validationErrors.Add("CRITICAL: Section '$sectionName' is missing 'description' key.")
        }
        elseif ($section.description -isnot [string]) {
            $validationErrors.Add("CRITICAL: Section '$sectionName.description' must be a string. Found: '$($section.description)'")
        }
    }

    # 3. Validate 'apps_list' structure
    if (-not ($Config.PSObject.Properties.Name -contains 'apps_list' -and $null -ne $Config.apps_list -and $Config.apps_list -is [System.Management.Automation.PSCustomObject])) {
        $validationErrors.Add("CRITICAL: Top-level 'apps_list' is missing or not an object.")
    }
    else {
        $appsList = $Config.apps_list
        foreach ($appName in $appsList.PSObject.Properties.Name) {
            $appEntry = $appsList.$appName
            if ($null -eq $appEntry -or $appEntry -isnot [System.Management.Automation.PSCustomObject]) {
                $validationErrors.Add("CRITICAL: Entry '$appName' in 'apps_list' is not a valid object.")
                continue
            }
            # Existing checks for remove, install, package_id, description
            if (-not ($appEntry.PSObject.Properties.Name -contains 'remove' -and $appEntry.remove -is [bool])) {
                $validationErrors.Add("CRITICAL: App '$appName' in 'apps_list' is missing 'remove' (boolean) key.")
            }
            if (-not ($appEntry.PSObject.Properties.Name -contains 'install' -and $appEntry.install -is [bool])) {
                $validationErrors.Add("CRITICAL: App '$appName' in 'apps_list' is missing 'install' (boolean) key.")
            }
            if (-not ($appEntry.PSObject.Properties.Name -contains 'provider' -and $appEntry.provider -is [string] -and -not([string]::IsNullOrWhiteSpace($appEntry.provider)))) {
                $validationErrors.Add("CRITICAL: App '$appName' in 'apps_list' is missing 'provider' (non-empty string) key.")
            }
            elseif ($appEntry.PSObject.Properties.Name -contains 'provider' -and -not ($supportedProviders -contains $appEntry.provider)) {
                $validationErrors.Add("WARNING: App '$appName' uses an unrecognized provider: '$($appEntry.provider)'. Supported are: $($supportedProviders -join ', ')")
            }
            if (-not ($appEntry.PSObject.Properties.Name -contains 'package_id' -and $appEntry.package_id -is [string] -and -not([string]::IsNullOrWhiteSpace($appEntry.package_id)))) {
                $validationErrors.Add("CRITICAL: App '$appName' in 'apps_list' is missing 'package_id' (non-empty string) key.")
            }
            if (-not ($appEntry.PSObject.Properties.Name -contains 'description' -and $appEntry.description -is [string])) {
                $validationErrors.Add("CRITICAL: App '$appName' in 'apps_list' is missing 'description' (string) key.")
            }
        }
    }

    # 4. Validate 'fonts_list' structure
    if (-not ($Config.PSObject.Properties.Name -contains 'fonts_list')) {
        $validationErrors.Add("CRITICAL: Configuration missing 'fonts_list' section.")
    }
    elseif ($null -eq $Config.fonts_list -or $Config.fonts_list -isnot [System.Management.Automation.PSCustomObject]) {
        $validationErrors.Add("CRITICAL: Top-level 'fonts_list' is missing or not an object.")
    }
    else {
        $fontsList = $Config.fonts_list
        # Validate nerdfonts
        if (-not ($fontsList.PSObject.Properties.Name -contains 'nerdfonts')) {
            $validationErrors.Add("CRITICAL: 'fonts_list' is missing 'nerdfonts' section.")
        }
        elseif ($null -eq $fontsList.nerdfonts -or $fontsList.nerdfonts -isnot [System.Management.Automation.PSCustomObject]) {
            $validationErrors.Add("CRITICAL: 'fonts_list.nerdfonts' is not a valid object.")
        }
        else {
            if (-not ($fontsList.nerdfonts.PSObject.Properties.Name -contains 'enabled')) {
                $validationErrors.Add("CRITICAL: 'fonts_list.nerdfonts' is missing 'enabled' key.")
            }
            elseif ($fontsList.nerdfonts.enabled -isnot [bool]) {
                $validationErrors.Add("CRITICAL: 'fonts_list.nerdfonts.enabled' must be a boolean. Found: '$($fontsList.nerdfonts.enabled)'")
            }
            if ($fontsList.nerdfonts.PSObject.Properties.Name -contains 'enabled' -and $fontsList.nerdfonts.enabled -eq $true) {
                if (-not ($fontsList.nerdfonts.PSObject.Properties.Name -contains 'fonts')) {
                    $validationErrors.Add("CRITICAL: 'fonts_list.nerdfonts' is enabled but missing 'fonts' array.")
                }
                elseif ($fontsList.nerdfonts.fonts -isnot [array]) {
                    $validationErrors.Add("CRITICAL: 'fonts_list.nerdfonts.fonts' must be an array. Found: '$($fontsList.nerdfonts.fonts.GetType().Name)'")
                }
                else {
                    foreach ($fontName in $fontsList.nerdfonts.fonts) {
                        if ($fontName -isnot [string] -or [string]::IsNullOrWhiteSpace($fontName)) {
                            $validationErrors.Add("CRITICAL: Each font in 'fonts_list.nerdfonts.fonts' must be a non-empty string.")
                        }
                    }
                }
            }
        }

        # Validate custom fonts
        if (-not ($fontsList.PSObject.Properties.Name -contains 'custom')) {
            $validationErrors.Add("WARNING: 'fonts_list' is missing 'custom' array (optional).")
        }
        elseif ($null -ne $fontsList.custom -and $fontsList.custom -isnot [array]) {
            $validationErrors.Add("WARNING: 'fonts_list.custom' should be an array if present. Found: '$($fontsList.custom.GetType().Name)'")
        }
        elseif ($null -ne $fontsList.custom) { # custom exists and is an array
            foreach ($customFontEntry in $fontsList.custom) {
                if ($null -eq $customFontEntry -or $customFontEntry -isnot [System.Management.Automation.PSCustomObject]) {
                    $validationErrors.Add("CRITICAL: Entry in 'fonts_list.custom' is not a valid object.")
                    continue
                }
                if (-not ($customFontEntry.PSObject.Properties.Name -contains 'name' -and $customFontEntry.name -is [string] -and -not([string]::IsNullOrWhiteSpace($customFontEntry.name)))) {
                    $validationErrors.Add("CRITICAL: Custom font entry is missing 'name' (non-empty string).")
                }
                if (-not ($customFontEntry.PSObject.Properties.Name -contains 'url' -and $customFontEntry.url -is [string] -and -not([string]::IsNullOrWhiteSpace($customFontEntry.url)))) {
                    $validationErrors.Add("CRITICAL: Custom font entry '$($customFontEntry.name)' is missing 'url' (non-empty string).")
                }
                if (-not ($customFontEntry.PSObject.Properties.Name -contains 'enabled')) {
                    $validationErrors.Add("CRITICAL: Custom font entry '$($customFontEntry.name)' is missing 'enabled' key.")
                }
                elseif ($customFontEntry.enabled -isnot [bool]) {
                    $validationErrors.Add("CRITICAL: Custom font entry '$($customFontEntry.name).enabled' must be a boolean. Found: '$($customFontEntry.enabled)'")
                }
            }
        }
    }

    # 5. Validate 'metadata' structure
    if (-not ($Config.PSObject.Properties.Name -contains 'metadata')) {
        $validationErrors.Add("CRITICAL: Configuration missing 'metadata' section.")
    }
    elseif ($null -eq $Config.metadata -or $Config.metadata -isnot [System.Management.Automation.PSCustomObject]) {
        $validationErrors.Add("CRITICAL: Top-level 'metadata' is missing or not an object.")
    }
    else {
        $metadata = $Config.metadata
        if (-not ($metadata.PSObject.Properties.Name -contains 'repo' -and $metadata.repo -is [string] -and -not([string]::IsNullOrWhiteSpace($metadata.repo)))) {
            $validationErrors.Add("CRITICAL: 'metadata' is missing 'repo' (non-empty string).")
        }
        if (-not ($metadata.PSObject.Properties.Name -contains 'version' -and $metadata.version -is [string] -and -not([string]::IsNullOrWhiteSpace($metadata.version)))) {
            $validationErrors.Add("CRITICAL: 'metadata' is missing 'version' (non-empty string).")
        }
        if (-not ($metadata.PSObject.Properties.Name -contains 'author' -and $metadata.author -is [string])) { # Author can be empty, so no whitespace check
            $validationErrors.Add("CRITICAL: 'metadata' is missing 'author' (string).")
        }
        if (-not ($metadata.PSObject.Properties.Name -contains 'description' -and $metadata.description -is [string])) { # Description can be empty
            $validationErrors.Add("CRITICAL: 'metadata' is missing 'description' (string).")
        }
        if (-not ($metadata.PSObject.Properties.Name -contains 'compatibility')) {
            $validationErrors.Add("CRITICAL: 'metadata' is missing 'compatibility' object.")
        }
        elseif ($null -eq $metadata.compatibility -or $metadata.compatibility -isnot [System.Management.Automation.PSCustomObject]) {
            $validationErrors.Add("CRITICAL: 'metadata.compatibility' is not a valid object.")
        }
        else {
            if (-not ($metadata.compatibility.PSObject.Properties.Name -contains 'windows_versions' -and $metadata.compatibility.windows_versions -is [array])) {
                $validationErrors.Add("CRITICAL: 'metadata.compatibility' is missing 'windows_versions' (array).")
            }
            else { # Check if all elements in windows_versions are strings
                foreach ($versionEntry in $metadata.compatibility.windows_versions) {
                    if ($versionEntry -isnot [string]) {
                        $validationErrors.Add("CRITICAL: 'metadata.compatibility.windows_versions' must be an array of strings.")
                        break
                    }
                }
            }
            if (-not ($metadata.compatibility.PSObject.Properties.Name -contains 'powershell_version' -and $metadata.compatibility.powershell_version -is [string])) {
                $validationErrors.Add("CRITICAL: 'metadata.compatibility' is missing 'powershell_version' (string).")
            }
        }
    }

    # Final error handling
    $criticalErrorsFound = $false
    if ($validationErrors.Count -gt 0) {
        foreach ($err in $validationErrors) {
            if ($err.StartsWith("CRITICAL:")) {
                Write-Log $err "ERROR"
                $criticalErrorsFound = $true
            }
            elseif ($err.StartsWith("WARNING:")) {
                Write-Log $err "WARNING"
            }
            else { # Should not happen if messages are prefixed correctly
                Write-Log "UNPREFIXED ERROR: $err" "ERROR"
                $criticalErrorsFound = $true
            }
        }
        if ($criticalErrorsFound) {
            throw "Configuration validation failed due to critical errors. Please check logs."
        }
    }

    if (-not $criticalErrorsFound) {
        Write-Log "Configuration structure validated successfully." "SUCCESS"
    }
}

Export-ModuleMember -Function *
