<#
.SYNOPSIS
    Handles application installations via Winget, Chocolatey, Scoop, MSStore, GitHub releases, or manual download links.
.DESCRIPTION
    This module is responsible for the application provisioning phase. It reads application configurations
    from the 'apps_list' section of the main configuration object. It supports installing applications
    using various providers, determining default installation locations, checking if applications are
    already installed, and handling different installer types including direct executables, MSIs, and ZIP archives.
    It integrates with the 'providers.psm1' module to ensure necessary package managers are available.
#>

<#
.SYNOPSIS
    Orchestrates the application installation process based on the configuration.
.DESCRIPTION
    This is the main entry point for installing applications. It first checks if the 'apps_provisioner.enabled'
    flag in the configuration is true. If not, it skips application installation.
    It groups applications by their specified provider (e.g., 'winget', 'chocolatey', 'manual').
    For each provider group, it ensures the provider is initialized using 'Initialize-ProviderPackage'.
    Then, for each application marked with 'install: true' in the 'apps_list', it calls 'Install-SingleApp'
    to handle the installation.
    Initializes and updates the 'Apps' phase summary.
.PARAMETER Config
    The main configuration object, which must contain an 'apps_provisioner' section (with an 'enabled'
    boolean property) and an 'apps_list' section detailing the applications to be installed. Mandatory.
.PARAMETER GitHubToken
    An optional GitHub Personal Access Token (PAT) string. This token is used for authenticated requests
    to the GitHub API, primarily for fetching release information for 'github_release' provider type
    and potentially by 'wingetcreate' for manifest operations. Using a token helps avoid rate limits.
.EXAMPLE
    PS C:\> Install-Applications -Config $loadedConfigObject -GitHubToken "ghp_YourTokenHere"
    This command initiates the application installation process using the provided configuration and GitHub token.
.NOTES
    Relies on 'Initialize-ProviderPackage' from 'providers.psm1' to ensure package managers are ready.
    Relies on 'Install-SingleApp' for the installation logic of each application.
    Logs the overall start and completion of the application installation phase.
#>
function Install-Applications {
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$Config,
        [string]$GitHubToken = $null
    )
    if (-not ($Config.PSObject.Properties.Name -contains 'apps_provisioner' -and $Config.apps_provisioner.enabled -eq $true)) {
        Write-Log "Apps provisioner is disabled or missing in configuration." "WARNING"
        return
    }
    if (-not ($Config.PSObject.Properties.Name -contains 'apps_list' -and $null -ne $Config.apps_list)) {
        Write-Log "Apps data ('apps_list') missing or invalid in configuration." "WARNING"
        Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Warning" -DetailMessage "Apps data ('apps_list') missing or invalid."
        return
    }

    $appsCollection = $Config.apps_list
    $groupedAppsByProvider = @{} # Using a more descriptive name

    # Group applications by their specified provider.
    foreach ($appProperty in $appsCollection.PSObject.Properties) {
        $appName = $appProperty.Name
        $appData = $appProperty.Value

        if ($appData.install -eq $true) {
            $providerName = $appData.provider
            if (-not $groupedAppsByProvider.ContainsKey($providerName)) {
                $groupedAppsByProvider[$providerName] = [System.Collections.Generic.List[object]]::new()
            }
            $groupedAppsByProvider[$providerName].Add(@{ Name = $appName; Config = $appData })
        }
    }

    Write-Log "Applications grouped by provider: $($groupedAppsByProvider.Keys -join ', ')" "DEBUG"
    Initialize-PhaseSummary "Apps" # Initialize Apps phase summary

    # Process applications for each provider group.
    foreach ($providerNameKey in $groupedAppsByProvider.Keys) {
        Write-Log "Processing applications for provider: '$providerNameKey'" "INFO"
        # Ensure the necessary package manager/provider is installed and ready.
        if (-not (Initialize-ProviderPackage -ProviderName $providerNameKey)) {
            Write-Log "Failed to initialize provider '$providerNameKey'. Skipping all apps for this provider." "ERROR"
            # Update phase summary for all apps under this failed provider
            foreach ($appToSkip in $groupedAppsByProvider[$providerNameKey]) {
                 Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage "Skipped app '$($appToSkip.Name)' because provider '$providerNameKey' failed to initialize."
            }
            continue # Move to the next provider.
        }

        # Install each application within the current provider group.
        foreach ($appToInstall in $groupedAppsByProvider[$providerNameKey]) {
            Write-Log "Attempting to install application: '$($appToInstall.Name)' using provider: '$providerNameKey'" "INFO"
            Install-SingleApp -AppName $appToInstall.Name -AppConfig $appToInstall.Config -Provider $providerNameKey -GitHubToken $GitHubToken
        }
    }
    Write-Log "Application installation phase complete." "SUCCESS"
}

<#
.SYNOPSIS
    Ensures 'wingetcreate.exe' tool is installed, used for Winget manifest operations.
.DESCRIPTION
    Checks if 'wingetcreate.exe' is available in the PATH. If not found, it attempts to install it
    using 'winget install Microsoft.WingetCreate'. This tool is primarily used by
    'Get-ManifestDefaultPath' to retrieve default installation locations from Winget package manifests.
.EXAMPLE
    PS C:\> Test-WingetCreate
    This ensures wingetcreate.exe is available, installing it if necessary.
.NOTES
    This function is a helper, typically called before operations requiring 'wingetcreate'.
    Requires Winget to be installed to function correctly if 'wingetcreate' needs to be installed.
#>
function Test-WingetCreate {
    # Ensure wingetcreate is installed for managing manifests
    Write-Log "Checking if wingetcreate.exe is installed (used for manifest operations)..." "INFO"
    if (-not (Get-Command wingetcreate.exe -ErrorAction SilentlyContinue)) {
        Write-Log "'wingetcreate.exe' not found. Attempting to install via Winget..." "INFO"
        # Attempt to install wingetcreate using winget.
        winget install --id Microsoft.WingetCreate --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0) {
            Write-Log "Failed to install 'wingetcreate.exe' via Winget. Exit code: $LASTEXITCODE. Manifest-based operations might fail." "WARNING"
        } else {
            Write-Log "'wingetcreate.exe' installed successfully." "SUCCESS"
        }
    } else {
        Write-Log "'wingetcreate.exe' is already available." "INFO"
    }
}

<#
.SYNOPSIS
    Retrieves the 'DefaultInstallLocation' from a Winget package manifest.
.DESCRIPTION
    Uses 'wingetcreate.exe show <PackageId> --installer-manifest' to fetch the installer manifest
    for a given Winget PackageId. It then parses the YAML output to find the 'DefaultInstallLocation' field.
    This is useful for determining where an application might be installed if 'install_location: AUTO' is specified.
    Includes retry logic for GitHub rate limiting if a GitHub token is not provided or is insufficient.
.PARAMETER PackageId
    The Winget Package ID of the application (e.g., "Microsoft.PowerToys"). Mandatory.
.PARAMETER GitHubToken
    An optional GitHub Personal Access Token (PAT) to use with 'wingetcreate' for authenticated requests,
    which can help mitigate GitHub API rate limits when fetching manifest data.
.EXAMPLE
    PS C:\> $path = Get-ManifestDefaultPath -PackageId "Microsoft.VisualStudioCode" -GitHubToken $myToken
    If successful, $path will contain the default install location string from the VSCode manifest.
.NOTES
    Calls 'Test-WingetCreate' to ensure 'wingetcreate.exe' is available.
    Returns the DefaultInstallLocation string if found, otherwise $null.
    Handles potential GitHub rate limit messages by waiting and retrying.
#>
function Get-ManifestDefaultPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageId,
        [string]$GitHubToken = $null
    )
    Test-WingetCreate # Ensure wingetcreate tool is available.
    if (-not $PackageId) {
        Write-Log "PackageId is required by Get-ManifestDefaultPath." "ERROR" # Should not happen due to Mandatory param
        return $null
    }

    $maxRetries = 3 # Reduced maxRetries to avoid excessive waiting for this version.
    $retryDelay = 30 # seconds, reduced retry delay.
    Write-Log "Fetching DefaultInstallLocation for package '$PackageId' using wingetcreate..." "INFO"

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            $tokenArg = if ($GitHubToken) { "--token $GitHubToken" } else { "" }
            # Execute wingetcreate to show the installer manifest content.
            $output = wingetcreate show $PackageId --installer-manifest --format yaml $tokenArg 2>$null

            if ($output) {
                # Check for GitHub rate limit message in output.
                if ($output -match '(?i)github' -and $output -match '(?i)limit' -and $output -match '(?i)token') {
                    Write-Log "GitHub API rate limit likely hit while fetching manifest for '$PackageId'. Waiting $retryDelay seconds before retrying (attempt $attempt/$maxRetries)..." "WARNING"
                    Start-Sleep -Seconds $retryDelay
                    continue # Next attempt in the loop.
                }
                # Parse the output lines to find DefaultInstallLocation.
                $lines = $output -split "`r`n|`n|`r" # Handles different newline characters
                foreach ($line in $lines) {
                    if ($line -match '^\s*DefaultInstallLocation:\s*(.+)') {
                        $foundPath = $Matches[1].Trim()
                        Write-Log "Found DefaultInstallLocation in manifest for '$PackageId': '$foundPath'" "DEBUG"
                        return $foundPath
                    }
                }
                # If loop completes and DefaultInstallLocation wasn't found in a valid output.
                Write-Log "DefaultInstallLocation not found in the manifest output for '$PackageId'." "DEBUG"
                return $null # Explicitly return null if not found after parsing.
            } else {
                 Write-Log "No output from 'wingetcreate show' for '$PackageId' (Attempt $attempt/$maxRetries). Might be an invalid PackageId or no manifest available." "DEBUG"
                 # No need to retry if there's no output, likely not a rate limit issue.
                 return $null
            }
        }
        catch {
            # Catch errors from wingetcreate execution itself.
            Write-Log "Error executing 'wingetcreate show' for '$PackageId' (Attempt $attempt/$maxRetries): $($_.Exception.Message)" "WARNING"
            # Depending on the error, a retry might be useful, but for now, we break.
            # If it was a critical failure of wingetcreate, retrying might not help.
            break # Exit loop on error.
        }
    }
    Write-Log "Failed to retrieve DefaultInstallLocation for '$PackageId' after $maxRetries attempts." "INFO"
    return $null
}

<#
.SYNOPSIS
    Determines the default installation location for an application.
.DESCRIPTION
    This function attempts to find an appropriate default installation location for an application.
    If a 'PackageId' is provided (typically for Winget packages), it first calls 'Get-ManifestDefaultPath'
    to try and retrieve the 'DefaultInstallLocation' specified in the package's manifest.
    If that's not found, or if no 'PackageId' was given, it falls back to system default locations:
    It prefers the standard 'Program Files' directory. If that's not suitable (e.g., on some systems or if it doesn't exist),
    it tries 'Program Files (x86)'. As a last resort, it uses a generic 'Apps' folder in the root of the primary system drive.
    If an 'AppName' is also provided, it appends this name as a subdirectory to the chosen base path.
.PARAMETER PackageId
    Optional. The Winget Package ID of the application. If provided, the function will attempt to get the
    default location from the package manifest first.
.PARAMETER GitHubToken
    Optional. A GitHub Personal Access Token (PAT) passed to 'Get-ManifestDefaultPath' if 'PackageId' is specified.
.PARAMETER AppName
    Optional. The name of the application. If provided, this will be appended as a subdirectory to the determined base path.
.EXAMPLE
    PS C:\> Get-DefaultInstallLocation -PackageId "Microsoft.PowerToys" -AppName "PowerToys"
    Attempts to find PowerToys manifest default location, otherwise falls back to system defaults and appends "PowerToys".

.EXAMPLE
    PS C:\> Get-DefaultInstallLocation -AppName "MyCustomApp"
    Determines a system default path and appends "MyCustomApp".
.NOTES
    Returns a string representing the determined default installation path.
    Environment variables in paths retrieved from manifests (like %PROGRAMFILES%) are expanded.
#>
function Get-DefaultInstallLocation {
    param(
        [string]$PackageId = $null,
        [string]$GitHubToken = $null,
        [string]$AppName = $null
    )
    # Attempt to get install location from package manifest if PackageId is provided.
    if ($PackageId) {
        $manifestPath = Get-ManifestDefaultPath -PackageId $PackageId -GitHubToken $GitHubToken
        if ($manifestPath) {
            # Expand common environment variables that might be in manifest paths.
            $expandedPath = [Environment]::ExpandEnvironmentVariables($manifestPath)
            Write-Log "Using manifest-defined default install location for '$PackageId': '$expandedPath'" "INFO"
            return $expandedPath
        } else {
            Write-Log "Could not retrieve DefaultInstallLocation from manifest for '$PackageId'." "INFO"
        }
    }

    # Fallback to system default install locations if manifest path isn't found or PackageId isn't provided.
    Write-Log "No PackageId provided or install path not found in manifest for '$AppName' (or '$PackageId'). Using system default install location logic." "INFO"
    $programFilesPath = [Environment]::GetFolderPath('ProgramFiles')
    $programFilesX86Path = [Environment]::GetFolderPath('ProgramFilesX86')
    $chosenBasePath = $null

    if (Test-Path $programFilesPath) {
        $chosenBasePath = $programFilesPath
    } elseif (Test-Path $programFilesX86Path) {
        $chosenBasePath = $programFilesX86Path
    } else {
        # Last resort: Use a generic 'Apps' folder on the system drive.
        $systemDrive = ($psdrive | Where-Object { $_.Provider.Name -eq 'FileSystem' -and $_.Root -match '^[A-Za-z]:\\$' } | Select-Object -First 1).Root
        if (-not $systemDrive) { $systemDrive = $env:SystemDrive + "\" } # Fallback if PSDrive method fails
        $chosenBasePath = Join-Path $systemDrive 'Apps'
        # Ensure this fallback directory exists.
        if (-not (Test-Path $chosenBasePath)) {
            try {
                New-Item -Path $chosenBasePath -ItemType Directory -Force -ErrorAction Stop | Out-Null
            } catch {
                 Write-Log "Failed to create fallback directory '$chosenBasePath'. Error: $($_.Exception.Message)" "WARNING"
                 # If directory creation fails, might have to default to something like $env:TEMP
                 $chosenBasePath = $env:TEMP
            }
        }
    }
    Write-Log "Determined base path for installation: '$chosenBasePath'" "DEBUG"

    if ($AppName) {
        # Append the application name as a subdirectory if provided.
        $finalAppPath = Join-Path $chosenBasePath $AppName
        Write-Log "Final default install location for '$AppName': '$finalAppPath'" "DEBUG"
        return $finalAppPath
    }
    else {
        return $chosenBasePath
    }
}

<#
.SYNOPSIS
    Tests if a specific application is already installed, using a provider-specific method.
.DESCRIPTION
    Checks if an application, identified by its 'AppName' and 'AppConfig' (which contains 'package_id'),
    is already installed. The method of checking depends on the specified 'Provider'.
    - For 'winget', 'chocolatey', 'scoop': Uses their respective list/status commands with the 'package_id'.
    - For 'manual' and 'github_release': Checks if the path specified in 'AppConfig.install_location' exists.
    - For 'msstore': Delegates the check to the 'winget' provider logic.
.PARAMETER AppName
    The display name or key of the application (used for logging).
.PARAMETER AppConfig
    The application's configuration object, containing at least 'package_id' and optionally 'install_location'. Mandatory.
.PARAMETER Provider
    The installation provider for the application (e.g., "winget", "chocolatey", "manual"). Mandatory.
.EXAMPLE
    PS C:\> $appCfg = @{ package_id = "Microsoft.PowerShell"; install_location = "C:\Program Files\PowerShell\7" }
    PS C:\> Test-AppInstalled -AppName "PowerShell 7" -AppConfig $appCfg -Provider "winget"
    Returns $true if PowerShell 7 is found by Winget, otherwise $false.

.EXAMPLE
    PS C:\> $appCfgManual = @{ install_location = "C:\MyCustomApp\run.exe" }
    PS C:\> Test-AppInstalled -AppName "MyCustomApp" -AppConfig $appCfgManual -Provider "manual"
    Returns $true if "C:\MyCustomApp\run.exe" exists.
.NOTES
    Returns $true if the application is detected as installed, $false otherwise.
    Logs its actions and findings. For 'manual'/'github_release', the accuracy depends on 'install_location' being correctly specified and reflecting the actual installation state.
#>
function Test-AppInstalled {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [Parameter(Mandatory = $true)]
        [PSObject]$AppConfig,
        [Parameter(Mandatory = $true)]
        [string]$Provider
    )
    Write-Log "Testing if app '$AppName' is already installed (Provider: $Provider)..." "INFO"
    $isInstalled = $false
    $appIdToCheck = if ($AppConfig.package_id) { $AppConfig.package_id } else { $AppName } # Default to AppName if no package_id

    switch ($Provider.ToLower()) {
        'winget' {
            # Winget list --id <id> is reliable for checking.
            $wingetOutput = winget list --id $appIdToCheck --accept-source-agreements 2>$null
            if ($LASTEXITCODE -eq 0 -and $wingetOutput -match $appIdToCheck) { # Check exit code and if ID is in output
                $isInstalled = $true
            }
        }
        'chocolatey' {
            # choco list --local-only --exact <id> --limit-output --quiet
            # Exit code 0 means command ran; output needs to be checked for actual presence.
            $chocoListOutput = choco list --local-only --exact $appIdToCheck --limitoutput --quiet 2>$null
            if ($LASTEXITCODE -eq 0 -and $chocoListOutput -match $appIdToCheck) {
                $isInstalled = $true
            }
        }
        'scoop' {
            # scoop status <app> shows information if installed, or an error/warning if not.
            $scoopStatusOutput = scoop status $appIdToCheck 2>$null
            if ($LASTEXITCODE -eq 0 -and $scoopStatusOutput -notmatch "(?i)error|not installed|missing|Couldn't find") {
                 # Further check if the output actually confirms the app by name.
                 if ($scoopStatusOutput -match "Name:\s*$appIdToCheck" -or $scoopStatusOutput -match "^\s*$appIdToCheck\s+\S+") {
                     $isInstalled = $true
                 }
            }
        }
        'manual', 'github_release' { # github_release apps are installed manually, so check is similar.
            if ($AppConfig.install_location) {
                $installPath = [Environment]::ExpandEnvironmentVariables($AppConfig.install_location)
                if (Test-Path $installPath) {
                    Write-Log "App '$AppName' (Provider: $Provider) presumed installed based on presence of install_location: '$installPath'." "INFO"
                    $isInstalled = $true
                } else {
                    Write-Log "App '$AppName' (Provider: $Provider) install_location '$installPath' not found during check." "DEBUG"
                }
            } else {
                Write-Log "Cannot accurately check if app '$AppName' (Provider: $Provider) is installed without 'install_location' defined in its configuration." "WARNING"
            }
        }
        'msstore' {
            # MSStore apps are often managed via Winget; delegate the check.
            Write-Log "For MSStore app '$AppName', delegating installation check to Winget provider logic." "DEBUG"
            $isInstalled = Test-AppInstalled -AppName $AppName -AppConfig $AppConfig -Provider 'winget'
        }
        default {
            Write-Log "Installation check for provider '$Provider' (app '$AppName') is not supported by Test-AppInstalled." "DEBUG"
            $isInstalled = $false # Default to not installed if provider logic is missing.
        }
    }

    if ($isInstalled) {
        Write-Log "App '$AppName' (Provider: $Provider, ID: $appIdToCheck) found installed." "INFO"
    } else {
        Write-Log "App '$AppName' (Provider: $Provider, ID: $appIdToCheck) not found or not confirmed installed." "INFO"
    }
    return $isInstalled
}

<#
.SYNOPSIS
    Installs a single application using the specified provider and configuration.
.DESCRIPTION
    This function is responsible for installing one application. It first calls 'Test-AppInstalled'
    to check if the application is already present. If so, it skips installation and reports success to the phase summary.
    Otherwise, it proceeds with installation based on the 'Provider' specified in 'AppConfig'.
    It handles different logic for 'winget', 'chocolatey', 'scoop', 'msstore' (via winget),
    'github_release' (downloads asset and uses manual install logic), and 'manual' (downloads or uses local installer).
    Installation progress, success, or failure are logged and reported to the 'Apps' phase summary.
.PARAMETER AppName
    The display name or key of the application from the configuration. Used for logging and as a fallback for ID. Mandatory.
.PARAMETER AppConfig
    The PowerShell object containing the configuration for this specific application (e.g., 'package_id',
    'provider', 'install_location', 'install_args', 'repo', 'asset_name'). Mandatory.
.PARAMETER Provider
    The installation provider name (e.g., "winget", "chocolatey", "manual"). This dictates the installation logic used. Mandatory.
.PARAMETER GitHubToken
    Optional. A GitHub Personal Access Token (PAT) for 'github_release' provider type to avoid API rate limits,
    and potentially for 'winget' if 'install_location: AUTO' requires manifest lookup via 'wingetcreate'.
.EXAMPLE
    PS C:\> $appSettings = $config.apps_list.MyApplication
    PS C:\> Install-SingleApp -AppName "MyApplication" -AppConfig $appSettings -Provider $appSettings.provider
    This command attempts to install "MyApplication" based on its configuration.
.NOTES
    This is a central function in the application installation process. It contains the main switch logic
    for different providers. Errors during the installation of one app are caught and reported,
    allowing the main script to continue with other applications.
    Calls 'Get-DefaultInstallLocation' for Winget AUTO location and 'Install-ManualApp' for manual/github_release types.
#>
function Install-SingleApp {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [Parameter(Mandatory = $true)]
        [PSObject]$AppConfig,
        [Parameter(Mandatory = $true)]
        [string]$Provider,
        [string]$GitHubToken = $null
    )

    # Check if already installed. If so, log, update phase summary, and return.
    if (Test-AppInstalled -AppName $AppName -AppConfig $AppConfig -Provider $Provider) {
        Write-Log "Skipping app '$AppName' as it is already installed (Provider: $Provider)." "INFO"
        Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Success" -DetailMessage "App '$AppName' already installed (Provider: $Provider)."
        return
    }

    $installMessageBase = "Installing '$AppName'" # Using a more descriptive variable name
    if ($Provider) { $installMessageBase += " via $Provider" }
    $currentInstallPath = $null # To store determined install path if applicable

    try {
        $appIdToUse = if (-not [string]::IsNullOrEmpty($AppConfig.package_id)) { $AppConfig.package_id } else { $AppName }

        switch ($Provider.ToLower()) {
            'winget' {
                $locationArg = ''
                # Determine installation path for Winget if specified.
                if ($AppConfig.install_location -eq 'AUTO' -or [string]::IsNullOrEmpty($AppConfig.install_location)) {
                    $currentInstallPath = Get-DefaultInstallLocation -PackageId $appIdToUse -GitHubToken $GitHubToken -AppName $AppName
                    if ($currentInstallPath) { $locationArg = "--location `"$currentInstallPath`"" }
                }
                elseif ($AppConfig.install_location -and $AppConfig.install_location -ne 'false') { # Explicit path
                    $currentInstallPath = [Environment]::ExpandEnvironmentVariables($AppConfig.install_location)
                    $locationArg = "--location `"$currentInstallPath`""
                }
                # else: $AppConfig.install_location is 'false' or not set, so no --location arg.

                $finalInstallMessage = $installMessageBase
                if ($currentInstallPath) { $finalInstallMessage += " to '$currentInstallPath'" }

                $wingetCmd = "winget install --id $appIdToUse --silent --accept-package-agreements --accept-source-agreements --disable-interactivity $locationArg"
                Write-Log $finalInstallMessage "INFO"
                Write-Log "Executing Winget command: $wingetCmd" "DEBUG"
                Invoke-Expression $wingetCmd
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "App '$AppName' (ID: $appIdToUse) installed successfully via Winget." "SUCCESS"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Success" -DetailMessage "App '$AppName' (ID: $appIdToUse) installed via Winget."
                } else {
                    Write-Log "Failed installing app '$AppName' (ID: $appIdToUse) via Winget. Exit code: $LASTEXITCODE" "ERROR"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage "App '$AppName' (ID: $appIdToUse) failed to install via Winget. Exit code: $LASTEXITCODE"
                }
            }
            'chocolatey' {
                Write-Log "$installMessageBase (ID: $appIdToUse)" "INFO"
                # Assuming community feed for most packages.
                choco install $appIdToUse -y --source=community
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "App '$AppName' (ID: $appIdToUse) installed successfully via Chocolatey." "SUCCESS"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Success" -DetailMessage "App '$AppName' (ID: $appIdToUse) installed via Chocolatey."
                } else {
                    Write-Log "Failed installing app '$AppName' (ID: $appIdToUse) via Chocolatey. Exit code: $LASTEXITCODE" "ERROR"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage "App '$AppName' (ID: $appIdToUse) failed to install via Chocolatey. Exit code: $LASTEXITCODE"
                }
            }
            'scoop' {
                if ($AppConfig.bucket) {
                    Write-Log "Ensuring Scoop bucket '$($AppConfig.bucket)' is added for app '$AppName'..." "DEBUG"
                    scoop bucket add $AppConfig.bucket -ErrorAction SilentlyContinue # Errors here are not fatal for the app install itself.
                }
                Write-Log "$installMessageBase (ID: $appIdToUse)" "INFO"
                scoop install $appIdToUse
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "App '$AppName' (ID: $appIdToUse) installed successfully via Scoop." "SUCCESS"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Success" -DetailMessage "App '$AppName' (ID: $appIdToUse) installed via Scoop."
                } else {
                    Write-Log "Failed installing app '$AppName' (ID: $appIdToUse) via Scoop. Exit code: $LASTEXITCODE" "ERROR"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage "App '$AppName' (ID: $appIdToUse) failed to install via Scoop. Exit code: $LASTEXITCODE"
                }
            }
            'manual' {
                $finalInstallMessage = $installMessageBase
                if ($AppConfig.install_location) { # For manual, install_location is where it *will* be, not a request.
                    $finalInstallMessage += " (expected at '$($AppConfig.install_location)')"
                }
                Write-Log $finalInstallMessage "INFO"
                # Install-ManualApp handles its own phase outcome reporting.
                Install-ManualApp -AppName $AppName -InstallerPath $null -AppConfig $AppConfig
            }
            'msstore' {
                Write-Log "$installMessageBase (MSStore ID: $appIdToUse, attempting via Winget)" "INFO"
                $locationArg = ''
                # For MSStore apps via Winget, explicit location is less common unless specifically needed.
                if ($AppConfig.install_location -and $AppConfig.install_location -ne 'false' -and $AppConfig.install_location -ne 'AUTO') {
                    $currentInstallPath = [Environment]::ExpandEnvironmentVariables($AppConfig.install_location)
                    $locationArg = "--location `"$currentInstallPath`""
                    Write-Log "Using specified install_location for MSStore app '$AppName': $currentInstallPath" "DEBUG"
                } else {
                     Write-Log "Using Winget's default location for MSStore app '$AppName' (ID: $appIdToUse)." "DEBUG"
                }

                $msStoreCmd = "winget install --id $appIdToUse --source msstore --silent --accept-package-agreements --accept-source-agreements --disable-interactivity $locationArg"
                Write-Log "Executing Winget (MSStore source) command: $msStoreCmd" "DEBUG"
                Invoke-Expression $msStoreCmd
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "App '$AppName' (MSStore ID: $appIdToUse) installed successfully via Winget from MSStore source." "SUCCESS"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Success" -DetailMessage "App '$AppName' (MSStore ID: $appIdToUse) installed via Winget (--source msstore)."
                } else {
                    $errorDetailMsg = "App '$AppName' (MSStore ID: $appIdToUse) failed via Winget with --source msstore. Exit: $LASTEXITCODE."
                    Write-Log "$errorDetailMsg Attempting Winget default source as fallback..." "ERROR"

                    # Fallback to default Winget sources if --source msstore fails.
                    $wingetFallbackCmd = "winget install --id $appIdToUse --silent --accept-package-agreements --accept-source-agreements --disable-interactivity $locationArg"
                    Write-Log "Executing Winget fallback command: $wingetFallbackCmd" "DEBUG"
                    Invoke-Expression $wingetFallbackCmd
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "App '$AppName' (MSStore ID: $appIdToUse) installed successfully via Winget fallback." "SUCCESS"
                        Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Success" -DetailMessage "App '$AppName' (MSStore ID: $appIdToUse) installed via Winget fallback."
                    } else {
                        Write-Log "Failed installing app '$AppName' (MSStore ID: $appIdToUse) via Winget fallback as well. Exit code: $LASTEXITCODE" "ERROR"
                        Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage "$errorDetailMsg Also failed with Winget fallback. Exit: $LASTEXITCODE."
                    }
                }
            }
            'github_release' {
                # This provider type downloads an asset from a GitHub release and then installs it manually.
                $repo = $AppConfig.repo
                $assetNamePattern = $AppConfig.asset_name
                Write-Log "$installMessageBase from GitHub repo '$repo' (asset: '$assetNamePattern')" "INFO"

                if (-not $repo -or -not $assetNamePattern) {
                    $errorMsg = "App '$AppName' (github_release): Missing 'repo' or 'asset_name' in AppConfig. Cannot proceed."
                    Write-Log $errorMsg "ERROR"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
                    return # Stop processing this app.
                }

                $latestReleaseUrl = "https://api.github.com/repos/$repo/releases/latest"
                $apiHeaders = @{}
                if (-not [string]::IsNullOrEmpty($GitHubToken)) {
                    $apiHeaders["Authorization"] = "token $GitHubToken"
                } else {
                    Write-Log "No GitHub token provided for '$AppName' (repo '$repo'). Public API rate limits may apply." "WARNING"
                }

                $releaseInfo = $null
                try {
                    Write-Log "Fetching latest release info for '$repo'..." "DEBUG"
                    $releaseInfo = Invoke-RestMethod -Uri $latestReleaseUrl -Headers $apiHeaders -ErrorAction Stop -TimeoutSec 30
                } catch {
                    $errorMsg = "App '$AppName': Failed to fetch release info from '$repo'. Error: $($_.Exception.Message)"
                    Write-Log $errorMsg "ERROR"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
                    return
                }

                if (-not $releaseInfo) {
                    $errorMsg = "App '$AppName': No release information found for repository '$repo'."
                    Write-Log $errorMsg "ERROR"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
                    return
                }

                # Find the asset based on asset_name pattern or keywords.
                $targetAsset = $null
                if ($assetNamePattern -eq 'latest_installer_exe') {
                    $targetAsset = $releaseInfo.assets | Where-Object { $_.name -like '*.exe' } | Sort-Object -Property created_at -Descending | Select-Object -First 1
                } elseif ($assetNamePattern -eq 'latest_installer_msi') {
                    $targetAsset = $releaseInfo.assets | Where-Object { $_.name -like '*.msi' } | Sort-Object -Property created_at -Descending | Select-Object -First 1
                } else { # Match using -like for wildcard support
                    $targetAsset = $releaseInfo.assets | Where-Object { $_.name -like $assetNamePattern } | Sort-Object -Property created_at -Descending | Select-Object -First 1
                }

                if ($targetAsset) {
                    Write-Log "Found asset '$($targetAsset.name)' for app '$AppName'. Download URL: $($targetAsset.browser_download_url)" "INFO"
                    $tempDownloadedFile = Join-Path $env:TEMP $targetAsset.name
                    try {
                        Write-Log "Downloading asset for '$AppName' to '$tempDownloadedFile'..." "DEBUG"
                        Invoke-WebRequest -Uri $targetAsset.browser_download_url -OutFile $tempDownloadedFile -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop
                        Write-Log "Asset '$($targetAsset.name)' for app '$AppName' downloaded successfully." "INFO"
                        # Call Install-ManualApp to handle the installation of the downloaded file.
                        # Install-ManualApp will manage its own phase outcome reporting.
                        Install-ManualApp -AppName $AppName -InstallerPath $tempDownloadedFile -InstallArgs $AppConfig.install_args -AppConfig $AppConfig
                    } catch {
                        $errorMsg = "App '$AppName': Error downloading or initiating local installation for asset '$($targetAsset.name)'. Error: $($_.Exception.Message)"
                        Write-Log $errorMsg "ERROR"
                        Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
                    } finally {
                        # Clean up the downloaded asset file.
                        if (Test-Path $tempDownloadedFile) {
                            Write-Log "Cleaning up downloaded asset for '$AppName': '$tempDownloadedFile'" "DEBUG"
                            Remove-Item $tempDownloadedFile -Force -ErrorAction SilentlyContinue
                        }
                    }
                } else {
                    $errorMsg = "App '$AppName': Asset matching pattern '$assetNamePattern' not found in the latest release of '$repo'."
                    Write-Log $errorMsg "ERROR"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
                }
            }
            default {
                $errorMsg = "Unknown provider: '$Provider' for app '$AppName'. Cannot install."
                Write-Log $errorMsg "ERROR"
                Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
            }
        }
    }
    catch {
        # This is the main catch for Install-SingleApp, for unexpected errors not caught by provider-specific logic.
        $errorMsg = "Overall failure during installation attempt for app '$AppName' (Provider: $Provider): $($_.Exception.Message)"
        Write-Log $errorMsg "ERROR"
        Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
    }
}

<#
.SYNOPSIS
    Installs an application from a downloaded installer file or a direct URL.
.DESCRIPTION
    This function handles the installation of an application when the installer is either already downloaded
    (path provided via 'InstallerPath') or needs to be downloaded from a URL ('AppConfig.download_url').
    It supports different installer types:
    - .exe: Executes with provided arguments (defaults to /S for silent).
    - .msi: Executes with msiexec /i /qn and appends provided arguments.
    - .zip: Extracts the archive to a temporary location. It then searches for a common installer
      (setup.exe, install.exe, *.msi) or a specifically named executable ('AppConfig.executable_in_zip')
      within the archive and attempts to run that.
    Installation success or failure is logged and reported to the 'Apps' phase summary.
    Temporary files and directories are cleaned up.
.PARAMETER AppName
    The display name of the application, used for logging. Mandatory.
.PARAMETER InstallerPath
    Optional. The local file system path to the installer. If not provided, 'AppConfig.download_url' must be set.
.PARAMETER InstallArgs
    Optional. Arguments to pass to the installer (for .exe or .msi). Defaults to "/S" for silent .exe installation.
    For .msi, these are appended after "/qn".
.PARAMETER AppConfig
    The application's configuration object. Required if 'InstallerPath' is not provided (must contain 'download_url').
    Can also provide 'executable_in_zip' if the download is a ZIP archive.
.EXAMPLE
    PS C:\> Install-ManualApp -AppName "MyUtility" -InstallerPath "C:\Downloads\utility.exe" -InstallArgs "/silent /norestart"
    Installs MyUtility from a local .exe file with custom arguments.

.EXAMPLE
    PS C:\> $appCfg = @{ download_url = "http://example.com/app.zip"; executable_in_zip = "setup.exe" }
    PS C:\> Install-ManualApp -AppName "ZippedApp" -AppConfig $appCfg
    Downloads app.zip, extracts it, finds setup.exe, and runs it with default silent arguments.
.NOTES
    This function is called by 'Install-SingleApp' for 'manual' and 'github_release' providers.
    It makes extensive use of Write-Log and Update-PhaseOutcome for reporting.
    Uses -ErrorAction Stop for critical operations like Invoke-WebRequest, Expand-Archive, Start-Process to ensure they are caught by the try-catch block.
#>
function Install-ManualApp {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppName,
        [string]$InstallerPath, # Can be $null if AppConfig.download_url is specified.
        [string]$InstallArgs = "/S",
        [PSObject]$AppConfig = $null
    )

    $localInstallerPathToUse = $InstallerPath # Use a mutable variable for the path.
    $wasFileDownloadedByThisFunction = $false # Flag to track if this function downloaded the installer.
    $tempExtractionDir = $null # To store path of any extracted ZIP archive.

    try {
        # If InstallerPath isn't directly provided, try to download it using AppConfig.download_url.
        if (-not $localInstallerPathToUse -and $AppConfig -and $AppConfig.download_url) {
            $downloadUrl = $AppConfig.download_url
            if ([string]::IsNullOrEmpty($downloadUrl)) {
                $errorMsg = "App '$AppName' (Manual/GitHub): No InstallerPath provided and 'download_url' is missing or empty in AppConfig."
                Write-Log $errorMsg "ERROR"
                Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
                return # Cannot proceed.
            }
            # Determine temporary path for the downloaded file.
            $tempFileName = $downloadUrl | Split-Path -Leaf
            $localInstallerPathToUse = Join-Path $env:TEMP $tempFileName
            $wasFileDownloadedByThisFunction = $true

            Write-Log "Downloading manual/github_release app '$AppName' from '$downloadUrl' to '$localInstallerPathToUse'..." "INFO"
            Invoke-WebRequest $downloadUrl -OutFile $localInstallerPathToUse -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop
            Write-Log "Successfully downloaded '$AppName' from '$downloadUrl'." "INFO"
        }
        # If InstallerPath was provided, ensure it exists.
        elseif (-not (Test-Path $localInstallerPathToUse)) {
            $errorMsg = "App '$AppName' (Manual/GitHub): Provided InstallerPath '$localInstallerPathToUse' does not exist."
            Write-Log $errorMsg "ERROR"
            Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
            return # Cannot proceed.
        }

        $currentFileExtension = [IO.Path]::GetExtension($localInstallerPathToUse).ToLower()

        # Handle ZIP file extraction if needed.
        if ($currentFileExtension -eq '.zip') {
            $tempExtractionDir = Join-Path $env:TEMP ("$AppName" + "_extracted_$(Get-Random)")
            # Ensure the directory is clean if it somehow exists.
            if(Test-Path $tempExtractionDir) { Remove-Item $tempExtractionDir -Recurse -Force -ErrorAction SilentlyContinue }
            New-Item -ItemType Directory -Path $tempExtractionDir -Force | Out-Null

            Write-Log "Extracting archive '$localInstallerPathToUse' for app '$AppName' to '$tempExtractionDir'..." "INFO"
            Expand-Archive -Path $localInstallerPathToUse -DestinationPath $tempExtractionDir -Force -ErrorAction Stop

            $foundInstallerInZip = $null
            # Check for a specific installer name in AppConfig first.
            if ($AppConfig -and $AppConfig.executable_in_zip) {
                 $specificInstallerPathInZip = Join-Path $tempExtractionDir $AppConfig.executable_in_zip
                 if (Test-Path $specificInstallerPathInZip) {
                    $foundInstallerInZip = Get-Item $specificInstallerPathInZip
                    Write-Log "Found specified 'executable_in_zip': '$($foundInstallerInZip.FullName)' for app '$AppName'." "DEBUG"
                 } else {
                    Write-Log "Specified 'executable_in_zip' ('$($AppConfig.executable_in_zip)') not found in extracted archive for '$AppName' at '$tempExtractionDir'." "WARNING"
                 }
            }

            # If not found by specific name, search for common installer patterns.
            if (-not $foundInstallerInZip) {
                $commonInstallers = Get-ChildItem -Path $tempExtractionDir -Recurse -File |
                                       Where-Object { $_.Name -match '^(setup|install|update).*\.exe$' -or $_.Extension -eq '.msi' } |
                                       Sort-Object Length | Select-Object -First 1 # Heuristic: smallest is often not the main one, but this is simple.
                $foundInstallerInZip = $commonInstallers
                if ($foundInstallerInZip) {
                    Write-Log "Found common installer pattern in ZIP: '$($foundInstallerInZip.FullName)' for app '$AppName'." "DEBUG"
                }
            }

            if ($foundInstallerInZip) {
                $localInstallerPathToUse = $foundInstallerInZip.FullName # Update path to the actual installer.
                $currentFileExtension = $foundInstallerInZip.Extension.ToLower() # Update extension.
            } else {
                $errorMsg = "App '$AppName' (Manual/GitHub): No common installer (.exe, .msi) or specified 'executable_in_zip' found in extracted ZIP '$($localInstallerPathToUse | Split-Path -Leaf)'."
                Write-Log $errorMsg "ERROR"
                Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
                return # Stop processing this app.
            }
        }

        # Now attempt to install using the determined $localInstallerPathToUse and $currentFileExtension.
        $isInstallSuccessful = $false
        Write-Log "Attempting to execute installer for '$AppName' using '$localInstallerPathToUse' (Args: '$InstallArgs'). Extension: '$currentFileExtension'" "INFO"

        switch ($currentFileExtension) {
            '.exe' {
                Start-Process -FilePath $localInstallerPathToUse -ArgumentList $InstallArgs -Wait -ErrorAction Stop
                if ($LASTEXITCODE -eq 0) { $isInstallSuccessful = $true }
            }
            '.msi' {
                $msiEffectiveArgs = "/i `"$localInstallerPathToUse`" /qn" # Basic silent install for MSI.
                # Append custom args if they are not the default /S (which isn't standard for msiexec /qn).
                if (-not [string]::IsNullOrEmpty($InstallArgs) -and $InstallArgs.ToUpper() -ne "/S") {
                    $msiEffectiveArgs += " $InstallArgs"
                }
                Start-Process msiexec.exe -ArgumentList $msiEffectiveArgs -Wait -ErrorAction Stop
                if ($LASTEXITCODE -eq 0) { $isInstallSuccessful = $true }
            }
            default {
                Write-Log "Unsupported installer type: '$currentFileExtension' for app '$AppName' from path '$localInstallerPathToUse'." "WARNING"
                Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Warning" -DetailMessage "App '$AppName' (Manual/GitHub): Unsupported installer type '$currentFileExtension'."
                # $isInstallSuccessful remains false.
            }
        }

        if ($isInstallSuccessful) {
            Write-Log "App '$AppName' (Manual/GitHub type) installed successfully using '$localInstallerPathToUse'." "SUCCESS"
            Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Success" -DetailMessage "App '$AppName' (Manual/GitHub): Successfully installed."
        } else {
            # Log error only if it was an attempted .exe or .msi, and not already an "unsupported type" warning.
            if ($currentFileExtension -in '.exe', '.msi') {
                Write-Log "Installation of '$AppName' (using '$localInstallerPathToUse') failed or reported non-zero exit code: $LASTEXITCODE." "ERROR"
                Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage "App '$AppName' (Manual/GitHub): Installation command for '$localInstallerPathToUse' failed or reported non-zero exit code: $LASTEXITCODE."
            }
        }
    }
    catch {
        # Catch any error from Invoke-WebRequest, Expand-Archive, Start-Process with -ErrorAction Stop.
        $errorMsg = "App '$AppName' (Manual/GitHub): Critical failure during installation process. Error: $($_.Exception.Message). Last exit code (if applicable): $LASTEXITCODE"
        Write-Log $errorMsg "ERROR"
        Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
    }
    finally {
        # Cleanup logic:
        # 1. If this function downloaded the original file (which might be a ZIP or direct installer).
        if ($wasFileDownloadedByThisFunction -and $InstallerPath -and (Test-Path $InstallerPath)) {
             Write-Log "Cleaning up downloaded file: '$InstallerPath' for app '$AppName'." "DEBUG"
             Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue
        }
        # 2. If a ZIP was extracted, $localInstallerPathToUse might now point inside $tempExtractionDir.
        # The original $InstallerPath (if it was a downloaded ZIP) is handled above.
        # If $InstallerPath was provided and was a ZIP, it's not removed by this function.
        # Always remove the extraction directory if it was created.
        if ($tempExtractionDir -and (Test-Path $tempExtractionDir)) {
            Write-Log "Cleaning up extraction directory: '$tempExtractionDir' for app '$AppName'." "DEBUG"
            Remove-Item $tempExtractionDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        # If the file processed ($localInstallerPathToUse) was downloaded by this function AND it was NOT a zip
        # (meaning it was a direct exe/msi that wasn't the original $InstallerPath if $InstallerPath was a zip)
        # This case is a bit complex. The primary downloaded file (if any) is $InstallerPath when $wasFileDownloadedByThisFunction is true.
        # If $localInstallerPathToUse points to an item *not* in $tempExtractionDir and $wasFileDownloadedByThisFunction is true, it means it was the direct download.
        if ($wasFileDownloadedByThisFunction -and (Test-Path $localInstallerPathToUse) -and `
            ($tempExtractionDir -eq $null -or -not $localInstallerPathToUse.StartsWith($tempExtractionDir)) ) {
             Write-Log "Cleaning up downloaded installer (direct, non-zip): '$localInstallerPathToUse' for app '$AppName'." "DEBUG"
             Remove-Item $localInstallerPathToUse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Exporting main orchestrator and potentially useful test function.
# Helper functions like Install-SingleApp, Install-ManualApp, Get-DefaultInstallLocation, etc., are kept internal.
Export-ModuleMember -Function Install-Applications, Test-AppInstalled
