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
        $json = Get-Content -Raw -Path $Path | ConvertFrom-Json -AsHashtable
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
        [hashtable]$Config
    )

    Write-Log "Validating configuration structure..." "INFO"
    $required = @('debloat', 'fonts', 'apps', 'settings')
    $missing = $false

    foreach ($section in $required) {
        if (-not $Config.ContainsKey($section)) {
            Write-Log "Missing section: $section" "ERROR"
            $missing = $true
        }
    }

    if ($missing) {
        throw "Configuration validation failed."
    } else {
        Write-Log "Configuration validated successfully." "SUCCESS"
    }
}

Export-ModuleMember -Function *
