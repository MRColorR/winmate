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

    # 1. Check for required top-level sections
    $requiredTopLevelSections = @('apps_debloater', 'fonts_provisioner', 'apps_provisioner', 'apps_list', 'metadata')
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
            if (-not ($appEntry.PSObject.Properties.Name -contains 'remove' -and $appEntry.remove -is [bool])) {
                $validationErrors.Add("CRITICAL: App '$appName' in 'apps_list' is missing 'remove' (boolean) key.")
            }
            if (-not ($appEntry.PSObject.Properties.Name -contains 'install' -and $appEntry.install -is [bool])) {
                $validationErrors.Add("CRITICAL: App '$appName' in 'apps_list' is missing 'install' (boolean) key.")
            }
            if (-not ($appEntry.PSObject.Properties.Name -contains 'provider' -and $appEntry.provider -is [string] -and -not([string]::IsNullOrWhiteSpace($appEntry.provider)))) {
                $validationErrors.Add("CRITICAL: App '$appName' in 'apps_list' is missing 'provider' (non-empty string) key.")
            }
            if (-not ($appEntry.PSObject.Properties.Name -contains 'package_id' -and $appEntry.package_id -is [string] -and -not([string]::IsNullOrWhiteSpace($appEntry.package_id)))) {
                $validationErrors.Add("CRITICAL: App '$appName' in 'apps_list' is missing 'package_id' (non-empty string) key.")
            }
            if (-not ($appEntry.PSObject.Properties.Name -contains 'description' -and $appEntry.description -is [string])) {
                $validationErrors.Add("CRITICAL: App '$appName' in 'apps_list' is missing 'description' (string) key.")
            }
        }
    }

    if ($validationErrors.Count -gt 0) {
        foreach ($err in $validationErrors) { Write-Log $err "ERROR" }
        throw "Configuration validation failed. Please check errors above."
    }
    else {
        Write-Log "Configuration structure validated successfully." "SUCCESS"
    }
}

Export-ModuleMember -Function *
