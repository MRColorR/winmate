<#
.SYNOPSIS
    Handles loading and validation of the JSON configuration file.
.DESCRIPTION
    This module contains functions to read the main JSON configuration file for the script
    and to validate its structure and content against predefined rules.
#>

<#
.SYNOPSIS
    Loads and parses the JSON configuration file.
.DESCRIPTION
    Reads the specified JSON configuration file (e.g., config.json), converts it from JSON format
    into a PowerShell custom object, and returns this object.
    It also checks for an optional 'token.json' file in the same directory as the configuration file.
    If 'token.json' is not found, an informational message is logged, suggesting that GitHub API
    requests might be unauthenticated unless a token is provided through other means.
.PARAMETER Path
    The file path to the JSON configuration file. This parameter is mandatory.
    Example: "C:\Path\To\Your\config.json"
.EXAMPLE
    PS C:\> $configData = Get-Configuration -Path "$PSScriptRoot\config\config.json"
    This command loads the configuration from 'config.json' located in a 'config' subdirectory
    relative to the script's root directory and stores the resulting object in $configData.
.NOTES
    The function will throw an error and halt execution if the configuration file specified by Path
    is not found or if the file content is not valid JSON.
    Uses Write-Log for logging its operations and any issues encountered.
#>
function Get-Configuration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Write-Log "Loading configuration from: $Path" "INFO"

    if (-not (Test-Path $Path)) {
        Write-Log "Configuration file not found: $Path" "ERROR"
        throw "Missing configuration file." # Critical error, script cannot proceed
    }

    # Check for an optional GitHub token file in the same directory as the config file
    $tokenPath = Join-Path (Split-Path $Path) 'token.json'
    if (-not (Test-Path $tokenPath)) {
        Write-Log "INFO: No token.json found in config directory. GitHub API requests will be unauthenticated unless a token is provided elsewhere." "INFO"
    }
    # Note: The presence of token.json is informational here; actual loading/use would be elsewhere.

    try {
        $json = Get-Content -Raw -Path $Path | ConvertFrom-Json
        Write-Log "Configuration successfully loaded." "SUCCESS"
        return $json
    }
    catch {
        Write-Log "Failed to parse configuration file '$Path': $($_.Exception.Message)" "ERROR"
        throw "Invalid configuration format. Check JSON syntax and structure." # Critical error
    }
}

<#
.SYNOPSIS
    Validates the structure and essential values of the loaded configuration object.
.DESCRIPTION
    Performs a comprehensive series of checks on the provided configuration PowerShell object
    (typically the output of Get-Configuration) to ensure its integrity.
    This includes verifying the presence of required top-level sections (like 'apps_list', 'fonts_list', 'metadata'),
    checking keys and their data types within these sections (e.g., 'enabled' booleans, 'provider' strings),
    validating application providers against a supported list, and ensuring specific structures for font
    configurations and metadata.

    The function collects all validation issues. If any "CRITICAL" errors are found, it throws an
    exception to halt further script execution. "WARNING" level issues are logged but do not stop the process.
.PARAMETER Config
    The PowerShell configuration object (output from Get-Configuration) that needs to be validated.
    This parameter is mandatory.
.EXAMPLE
    PS C:\> $myConfig = Get-Configuration -Path "config.json"
    PS C:\> Test-Configuration -Config $myConfig
    This example first loads a configuration and then passes the resulting object to Test-Configuration for validation.
    If validation fails with critical errors, an exception will be thrown.
.NOTES
    Uses Write-Log for outputting all validation messages (both CRITICAL and WARNING).
    The list of supported providers is hardcoded within this function.
    The exact structure and requirements for sections like 'apps_debloater', 'apps_provisioner', 'fonts_provisioner'
    (for enabled/description flags) are also checked.
#>
function Test-Configuration {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Config # Expects a PowerShell custom object
    )

    Write-Log "Validating configuration structure..." "INFO"
    $validationErrors = [System.Collections.Generic.List[string]]::new()
    # Define the list of package manager providers supported by the script.
    $supportedProviders = @('winget', 'chocolatey', 'scoop', 'manual', 'msstore', 'github_release')

    # Section 1: Check for required top-level sections in the configuration.
    # These sections are fundamental for the script's operation.
    # Note: 'fonts_provisioner' might be an older name or a separate toggle from 'fonts_list'.
    # The current requirement is for 'fonts_list' for detailed font config, and 'fonts_provisioner' for the phase toggle.
    $requiredTopLevelSections = @('apps_debloater', 'apps_provisioner', 'apps_list', 'fonts_list', 'metadata', 'fonts_provisioner')
    # Added fonts_provisioner back as it's checked in phaseSections
    foreach ($sectionName in $requiredTopLevelSections) {
        if (-not ($Config.PSObject.Properties.Name -contains $sectionName)) {
            $validationErrors.Add("CRITICAL: Configuration missing required top-level section: '$sectionName'.")
        }
    }

    # If fundamental sections are missing, it's not useful to proceed with more detailed checks.
    if ($validationErrors.Count -gt 0 -and ($validationErrors | Where-Object { $_ -like "CRITICAL: Configuration missing required top-level section*" })) {
        foreach ($err in $validationErrors) { Write-Log $err "ERROR" } # Log all collected critical errors
        throw "Configuration validation failed due to missing essential top-level sections. Further validation aborted."
    }

    # Section 2: Validate structure of main phase sections like 'apps_debloater', 'fonts_provisioner', 'apps_provisioner'.
    # These sections control major parts of the script and must have 'enabled' and 'description' keys.
    $phaseSections = @('apps_debloater', 'fonts_provisioner', 'apps_provisioner')
    foreach ($sectionName in $phaseSections) {
        # Check if the section itself exists first (it should, due to earlier top-level check, but good for robustness)
        if (-not ($Config.PSObject.Properties.Name -contains $sectionName) -or $null -eq $Config.$sectionName) {
            # This case should ideally be caught by the top-level check if $sectionName is in $requiredTopLevelSections.
            # If it's not in $requiredTopLevelSections, it's an optional phase, so skip if null.
            if ($requiredTopLevelSections -contains $sectionName) {
                 $validationErrors.Add("CRITICAL: Section '$sectionName' is unexpectedly null or missing (should have been caught by top-level check).")
            } # else, it's an optional section not present, which is fine.
            continue
        }
        $section = $Config.$sectionName
        # Validate 'enabled' key
        if (-not ($section.PSObject.Properties.Name -contains 'enabled')) {
            $validationErrors.Add("CRITICAL: Section '$sectionName' is missing 'enabled' (boolean) key.")
        }
        elseif ($section.enabled -isnot [bool]) {
            $validationErrors.Add("CRITICAL: Section '$sectionName.enabled' must be a boolean (true/false). Found: '$($section.enabled)' of type $($section.enabled.GetType().Name)")
        }
        # Validate 'description' key
        if (-not ($section.PSObject.Properties.Name -contains 'description')) {
            $validationErrors.Add("CRITICAL: Section '$sectionName' is missing 'description' (string) key.")
        }
        elseif ($section.description -isnot [string]) {
            $validationErrors.Add("CRITICAL: Section '$sectionName.description' must be a string. Found: '$($section.description)' of type $($section.description.GetType().Name)")
        }
    }

    # Section 3: Validate 'apps_list' structure for application definitions.
    # This section defines all applications to be managed (installed or removed).
    if (-not ($Config.PSObject.Properties.Name -contains 'apps_list')) {
         $validationErrors.Add("CRITICAL: Top-level 'apps_list' section is missing.") # Already covered by top-level
    }
    elseif ($null -eq $Config.apps_list -or $Config.apps_list -isnot [System.Management.Automation.PSCustomObject]) {
        $validationErrors.Add("CRITICAL: Top-level 'apps_list' is present but not a valid object (PSCustomObject).")
    }
    else {
        $appsList = $Config.apps_list
        foreach ($appNameKey in $appsList.PSObject.Properties.Name) { # $appNameKey is the key like "VisualStudioCode"
            $appEntry = $appsList.$appNameKey
            if ($null -eq $appEntry -or $appEntry -isnot [System.Management.Automation.PSCustomObject]) {
                $validationErrors.Add("CRITICAL: Entry '$appNameKey' in 'apps_list' is not a valid object.")
                continue # Skip further checks for this invalid entry
            }
            # Validate required keys for each app entry
            if (-not ($appEntry.PSObject.Properties.Name -contains 'remove' -and $appEntry.remove -is [bool])) {
                $validationErrors.Add("CRITICAL: App '$appNameKey' in 'apps_list' is missing 'remove' (boolean) key.")
            }
            if (-not ($appEntry.PSObject.Properties.Name -contains 'install' -and $appEntry.install -is [bool])) {
                $validationErrors.Add("CRITICAL: App '$appNameKey' in 'apps_list' is missing 'install' (boolean) key.")
            }
            if (-not ($appEntry.PSObject.Properties.Name -contains 'provider' -and $appEntry.provider -is [string] -and -not([string]::IsNullOrWhiteSpace($appEntry.provider)))) {
                $validationErrors.Add("CRITICAL: App '$appNameKey' in 'apps_list' is missing 'provider' (non-empty string) key.")
            }
            # Validate provider value if present
            elseif ($appEntry.PSObject.Properties.Name -contains 'provider' -and -not ($supportedProviders -contains $appEntry.provider.ToLower())) { # Ensure case-insensitivity for provider check
                $validationErrors.Add("WARNING: App '$appNameKey' uses an unrecognized provider: '$($appEntry.provider)'. Supported are: $($supportedProviders -join ', ')")
            }
            if (-not ($appEntry.PSObject.Properties.Name -contains 'package_id' -and $appEntry.package_id -is [string] -and -not([string]::IsNullOrWhiteSpace($appEntry.package_id)))) {
                $validationErrors.Add("CRITICAL: App '$appNameKey' in 'apps_list' is missing 'package_id' (non-empty string) key.")
            }
            if (-not ($appEntry.PSObject.Properties.Name -contains 'description' -and $appEntry.description -is [string])) {
                $validationErrors.Add("CRITICAL: App '$appNameKey' in 'apps_list' is missing 'description' (string) key.")
            }
            # Other optional keys like 'install_location', 'install_args', 'repo', 'asset_name' are validated contextually by consuming functions.
        }
    }

    # Section 4: Validate 'fonts_list' structure for font definitions.
    if (-not ($Config.PSObject.Properties.Name -contains 'fonts_list')) {
        $validationErrors.Add("CRITICAL: Configuration missing 'fonts_list' section.") # Already covered by top-level
    }
    elseif ($null -eq $Config.fonts_list -or $Config.fonts_list -isnot [System.Management.Automation.PSCustomObject]) {
        $validationErrors.Add("CRITICAL: Top-level 'fonts_list' is present but not a valid object (PSCustomObject).")
    }
    else {
        $fontsList = $Config.fonts_list
        # Validate 'nerdfonts' subsection
        if (-not ($fontsList.PSObject.Properties.Name -contains 'nerdfonts')) {
            $validationErrors.Add("CRITICAL: 'fonts_list' is missing 'nerdfonts' subsection.")
        }
        elseif ($null -eq $fontsList.nerdfonts -or $fontsList.nerdfonts -isnot [System.Management.Automation.PSCustomObject]) {
            $validationErrors.Add("CRITICAL: 'fonts_list.nerdfonts' is not a valid object.")
        }
        else {
            # Validate 'enabled' key for nerdfonts
            if (-not ($fontsList.nerdfonts.PSObject.Properties.Name -contains 'enabled')) {
                $validationErrors.Add("CRITICAL: 'fonts_list.nerdfonts' is missing 'enabled' (boolean) key.")
            }
            elseif ($fontsList.nerdfonts.enabled -isnot [bool]) {
                $validationErrors.Add("CRITICAL: 'fonts_list.nerdfonts.enabled' must be a boolean. Found: '$($fontsList.nerdfonts.enabled)'")
            }
            # If nerdfonts are enabled, validate the 'fonts' array
            if ($fontsList.nerdfonts.PSObject.Properties.Name -contains 'enabled' -and $fontsList.nerdfonts.enabled -eq $true) {
                if (-not ($fontsList.nerdfonts.PSObject.Properties.Name -contains 'fonts')) {
                    $validationErrors.Add("CRITICAL: 'fonts_list.nerdfonts' is enabled but missing 'fonts' (array) key.")
                }
                elseif ($fontsList.nerdfonts.fonts -isnot [array]) {
                    $validationErrors.Add("CRITICAL: 'fonts_list.nerdfonts.fonts' must be an array. Found: '$($fontsList.nerdfonts.fonts.GetType().Name)'")
                }
                else {
                    foreach ($fontName in $fontsList.nerdfonts.fonts) {
                        if ($fontName -isnot [string] -or [string]::IsNullOrWhiteSpace($fontName)) {
                            $validationErrors.Add("CRITICAL: Each font name in 'fonts_list.nerdfonts.fonts' must be a non-empty string.")
                        }
                    }
                }
            }
        }

        # Validate 'custom' fonts subsection
        if (-not ($fontsList.PSObject.Properties.Name -contains 'custom')) {
            # This is optional, so a warning is appropriate if missing.
            $validationErrors.Add("WARNING: 'fonts_list' is missing 'custom' (array) subsection. No custom fonts will be processed.")
        }
        elseif ($null -ne $fontsList.custom -and $fontsList.custom -isnot [array]) {
            # If 'custom' is present but not an array, it's a configuration error.
            $validationErrors.Add("CRITICAL: 'fonts_list.custom' should be an array if present. Found: '$($fontsList.custom.GetType().Name)'")
        }
        elseif ($null -ne $fontsList.custom) { # 'custom' exists and is an array
            foreach ($customFontEntry in $fontsList.custom) {
                if ($null -eq $customFontEntry -or $customFontEntry -isnot [System.Management.Automation.PSCustomObject]) {
                    $validationErrors.Add("CRITICAL: An entry in 'fonts_list.custom' is not a valid object.")
                    continue # Skip further checks for this invalid entry
                }
                # Validate required keys for each custom font entry
                if (-not ($customFontEntry.PSObject.Properties.Name -contains 'name' -and $customFontEntry.name -is [string] -and -not([string]::IsNullOrWhiteSpace($customFontEntry.name)))) {
                    $validationErrors.Add("CRITICAL: Custom font entry is missing 'name' (non-empty string). Index: $($fontsList.custom.IndexOf($customFontEntry))")
                }
                if (-not ($customFontEntry.PSObject.Properties.Name -contains 'url' -and $customFontEntry.url -is [string] -and -not([string]::IsNullOrWhiteSpace($customFontEntry.url)))) {
                    $validationErrors.Add("CRITICAL: Custom font entry '$($customFontEntry.name)' is missing 'url' (non-empty string).")
                }
                if (-not ($customFontEntry.PSObject.Properties.Name -contains 'enabled')) {
                    $validationErrors.Add("CRITICAL: Custom font entry '$($customFontEntry.name)' is missing 'enabled' (boolean) key.")
                }
                elseif ($customFontEntry.enabled -isnot [bool]) {
                    $validationErrors.Add("CRITICAL: Custom font entry '$($customFontEntry.name).enabled' must be a boolean. Found: '$($customFontEntry.enabled)'")
                }
            }
        }
    }

    # Section 5: Validate 'metadata' structure.
    # This section contains information about the configuration file itself.
    if (-not ($Config.PSObject.Properties.Name -contains 'metadata')) {
        $validationErrors.Add("CRITICAL: Configuration missing 'metadata' section.") # Already covered
    }
    elseif ($null -eq $Config.metadata -or $Config.metadata -isnot [System.Management.Automation.PSCustomObject]) {
        $validationErrors.Add("CRITICAL: Top-level 'metadata' is present but not a valid object (PSCustomObject).")
    }
    else {
        $metadata = $Config.metadata
        # Validate required keys in metadata
        if (-not ($metadata.PSObject.Properties.Name -contains 'repo' -and $metadata.repo -is [string] -and -not([string]::IsNullOrWhiteSpace($metadata.repo)))) {
            $validationErrors.Add("CRITICAL: 'metadata' is missing 'repo' (non-empty string) key.")
        }
        if (-not ($metadata.PSObject.Properties.Name -contains 'version' -and $metadata.version -is [string] -and -not([string]::IsNullOrWhiteSpace($metadata.version)))) {
            $validationErrors.Add("CRITICAL: 'metadata' is missing 'version' (non-empty string) key.")
        }
        if (-not ($metadata.PSObject.Properties.Name -contains 'author' -and $metadata.author -is [string])) { # Author can be an empty string
            $validationErrors.Add("CRITICAL: 'metadata' is missing 'author' (string) key.")
        }
        if (-not ($metadata.PSObject.Properties.Name -contains 'description' -and $metadata.description -is [string])) { # Description can be an empty string
            $validationErrors.Add("CRITICAL: 'metadata' is missing 'description' (string) key.")
        }
        # Validate 'compatibility' sub-object
        if (-not ($metadata.PSObject.Properties.Name -contains 'compatibility')) {
            $validationErrors.Add("CRITICAL: 'metadata' is missing 'compatibility' (object) key.")
        }
        elseif ($null -eq $metadata.compatibility -or $metadata.compatibility -isnot [System.Management.Automation.PSCustomObject]) {
            $validationErrors.Add("CRITICAL: 'metadata.compatibility' is not a valid object.")
        }
        else {
            # Validate keys within 'compatibility'
            if (-not ($metadata.compatibility.PSObject.Properties.Name -contains 'windows_versions' -and $metadata.compatibility.windows_versions -is [array])) {
                $validationErrors.Add("CRITICAL: 'metadata.compatibility' is missing 'windows_versions' (array) key.")
            }
            else {
                # Check if all elements in windows_versions are strings
                foreach ($versionEntry in $metadata.compatibility.windows_versions) {
                    if ($versionEntry -isnot [string] -or [string]::IsNullOrWhiteSpace($versionEntry)) {
                        $validationErrors.Add("CRITICAL: 'metadata.compatibility.windows_versions' must be an array of non-empty strings.")
                        break
                    }
                }
            }
            if (-not ($metadata.compatibility.PSObject.Properties.Name -contains 'powershell_version' -and $metadata.compatibility.powershell_version -is [string] -and -not([string]::IsNullOrWhiteSpace($metadata.compatibility.powershell_version)) )) {
                $validationErrors.Add("CRITICAL: 'metadata.compatibility' is missing 'powershell_version' (non-empty string) key.")
            }
        }
    }

    # Final error handling: Log all collected messages and throw if any critical errors were found.
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
                Write-Log "UNPREFIXED VALIDATION MESSAGE (treated as ERROR): $err" "ERROR" # Clarified this case
                $criticalErrorsFound = $true
            }
        }
        if ($criticalErrorsFound) {
            # Throw a general error; specific errors have already been logged.
            throw "Configuration validation failed due to one or more critical errors. Please review the logs."
        }
    }

    if (-not $criticalErrorsFound) {
        Write-Log "Configuration structure validated successfully." "SUCCESS"
    }
}

Export-ModuleMember -Function Get-Configuration, Test-Configuration
