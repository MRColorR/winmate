<#!
.SYNOPSIS
    Handles application installations via winget, choco, scoop, or manual methods
#>

function Install-Applications {
    param(
        [PSObject]$Config,
        [string]$GitHubToken = $null
    )
    if (-not ($Config.PSObject.Properties.Name -contains 'apps_provisioner' -and $Config.apps_provisioner.enabled -eq $true)) {
        Write-Log "Apps provisioner is disabled or missing in configuration." "WARNING"
        return
    }
    if (-not ($Config.PSObject.Properties.Name -contains 'apps_list' -and $null -ne $Config.apps_list)) {
        Write-Log "Apps data ('apps_list') missing or invalid in configuration." "WARNING"
        return
    }
    $appsCollection = $Config.apps_list
    $grouped = @{}

    foreach ($app in $appsCollection.PSObject.Properties) {
        $name = $app.Name
        $data = $app.Value

        if ($data.install -eq $true) {
            $provider = $data.provider
            if (-not $grouped.ContainsKey($provider)) {
                $grouped[$provider] = @()
            }
            $grouped[$provider] += @{ Name = $name; Config = $data }
        }
    }
    Write-Host "DEBUG: Grouped applications by provider: $($grouped.Keys -join ', ')"
    Initialize-PhaseSummary "Apps" # Initialize Apps phase summary

    foreach ($provider in $grouped.Keys) {
        # Use Ensure-ProviderInstalled from providers.psm1
        if (-not (Ensure-ProviderInstalled -ProviderName $provider)) {
            Write-Log "Failed to ensure provider '$provider' is installed. Skipping apps for this provider." "ERROR"
            continue
        }

        foreach ($app in $grouped[$provider]) {
            Write-Log "Installing application: $($app.Name) using provider: $provider" "INFO"
            Install-SingleApp -AppName $app.Name -AppConfig $app.Config -Provider $provider -GitHubToken $GitHubToken
        }
    }
    Write-Log "Application installation complete." "SUCCESS"
}

function Test-WingetCreate {
    # Ensure wingetcreate is installed for managing manifests
    Write-Log "Checking if wingetcreate is installed as is required for manifest management." "INFO"
    if (-not (Get-Command wingetcreate.exe -ErrorAction SilentlyContinue)) {
        Write-Log "wingetcreate is not installed. Installing..." "INFO"
        winget install --id Microsoft.WingetCreate --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
    }
}

function Get-ManifestDefaultPath {
    param(
        [string]$PackageId,
        [string]$GitHubToken = $null
    )
    Test-WingetCreate
    if (-not $PackageId) {
        Write-Log "PackageId is required to get the default install location." "ERROR"
        return $null
    }
    $maxRetries = 5
    $retryDelay = 60 # seconds
    Write-Log "Fetching default install location for package: $PackageId" "INFO"
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            $tokenArg = $null
            if ($GitHubToken) { $tokenArg = "--token $GitHubToken" }
            $output = wingetcreate show $PackageId --installer-manifest --format yaml $tokenArg 2>$null
            if ($output) {
                # Check for GitHub rate limit message
                if ($output -match '(?i)github' -and $output -match '(?i)limit' -and $output -match '(?i)token') {
                    Write-Log "GitHub rate limit hit. Waiting $retryDelay seconds before retrying (attempt $attempt/$maxRetries)... If you have a GitHub token, pass it as a parameter to mitigate rate limiting." "WARNING"
                    Start-Sleep -Seconds $retryDelay
                    continue
                }
                $lines = $output -split "`n"
                foreach ($line in $lines) {
                    if ($line -match 'DefaultInstallLocation:\s*(.+)') {
                        Write-Host "DEBUG: Found default install location in manifest: $($Matches[1].Trim())"
                        return $Matches[1].Trim()
                    }
                }
            }
        }
        catch { }
        break
    }
    return $null
}

function Get-DefaultInstallLocation {
    param(
        [string]$PackageId = $null,
        [string]$GitHubToken = $null,
        [string]$AppName = $null
    )
    # If a PackageId is provided, use it for getting the default install location declared in the package manifest
    if ($PackageId) {
        $manifestPath = Get-ManifestDefaultPath -PackageId $PackageId -GitHubToken $GitHubToken
        if ($manifestPath) {
            # Expand environment variables if present in the manifest path
            $expandedPath = [Environment]::ExpandEnvironmentVariables($manifestPath)
            return $expandedPath
        }
    }
    # Get a generic default install location based on the system
    Write-Log "No PackageId provided or Install path not found in manifest. Using system default install location." "WARNING"
    $programFiles = [Environment]::GetFolderPath('ProgramFiles')
    $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $basePath = $null
    if (Test-Path $programFiles) { $basePath = $programFiles }
    elseif (Test-Path $programFilesX86) { $basePath = $programFilesX86 }
    else {
        $drive = (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match ':' })[0].Root
        $basePath = Join-Path $drive 'Apps'
        if (-not (Test-Path $basePath)) { New-Item -Path $basePath -ItemType Directory | Out-Null }
    }
    if ($AppName) {
        $finalPath = Join-Path $basePath $AppName
        return $finalPath
    }
    else {
        return $basePath
    }
}

function Test-AppInstalled {
    param(
        [string]$AppName,
        [PSObject]$AppConfig,
        [string]$Provider
    )
    Write-Log "Testing if '$AppName' is already installed via $Provider" "INFO"
    $isInstalled = $false

    switch ($Provider.ToLower()) {
        'winget' {
            $id = if ($AppConfig.package_id) { $AppConfig.package_id } else { $AppName }
            $result = winget list --id $id --accept-source-agreements 2>$null | Select-String -Pattern $id -Quiet
            if ($result) { $isInstalled = $true } # Select-String -Quiet returns boolean
        }
        'chocolatey' {
            # Use package_id for consistency
            $id = if ($AppConfig.package_id) { $AppConfig.package_id } else { $AppName }
            # Ensure choco list output is properly checked, it can return 0 even if not found.
            $chocoResult = choco list --local-only --exact $id --limitoutput --quiet 2>$null
            if ($LASTEXITCODE -eq 0 -and $chocoResult -match $id) { $isInstalled = $true }
        }
        'scoop' {
            # Use package_id for consistency
            $id = if ($AppConfig.package_id) { $AppConfig.package_id } else { $AppName }
            $scoopResult = scoop status $id 2>$null
            # Scoop status output can be varied, check if it indicates installed.
            # A simple check: if no error and some output that doesn't say "not installed" or "error".
            # This might need refinement based on actual scoop status output for installed apps.
            if ($LASTEXITCODE -eq 0 -and $scoopResult -notmatch "(?i)error|not installed|missing") {
                 # More specific check: scoop status for an installed app usually shows info.
                 # For a non-installed app, it might say "WARN App '...' isn't installed." or similar.
                 if ($scoopResult -match "Name:\s*$id") { $isInstalled = $true }
            }
        }
        'manual' {
            if ($AppConfig.install_location) {
                $installPath = [Environment]::ExpandEnvironmentVariables($AppConfig.install_location)
                if (Test-Path $installPath) {
                    # For executables, check if the main executable file exists.
                    # For general directories, just Test-Path might be enough.
                    # This could be enhanced if AppConfig specifies an 'executable_name' inside install_location.
                    Write-Log "App '$AppName' (provider $Provider) presumed installed. Found at '$installPath'." "INFO"
                    $isInstalled = $true
                } else {
                    Write-Log "App '$AppName' (provider $Provider) install_location '$installPath' not found." "DEBUG"
                }
            } else {
                Write-Log "Cannot check if app '$AppName' (provider $Provider) is installed without 'install_location' in config." "WARNING"
            }
        }
        'msstore' {
            # Delegate to winget for checking msstore apps
            $isInstalled = Test-AppInstalled -AppName $AppName -AppConfig $AppConfig -Provider 'winget'
        }
        default {
            Write-Log "Provider '$Provider' not supported by Test-AppInstalled." "DEBUG"
            $isInstalled = $false
        }
    }

    return $isInstalled
}

function Install-SingleApp {
    param(
        [string]$AppName,
        [PSObject]$AppConfig,
        [string]$Provider,
        [string]$GitHubToken = $null
    )

    if (Test-AppInstalled -AppName $AppName -AppConfig $AppConfig -Provider $Provider) {
        Write-Log "Skipping '$AppName' (already installed via $Provider)" "INFO"
        Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Success" -DetailMessage "App '$AppName' already installed (Provider: $Provider)."
        return
    }

    $install_mesg = "Installing '$AppName'"
    if ($Provider) { $install_mesg += " via $Provider" }
    $install_path = $null

    try {
        switch ($Provider.ToLower()) {
            'winget' {
                if ($null -ne $AppConfig.package_id) { $id = $AppConfig.package_id } else { $id = $AppName }
                $locationArg = ''
                # If install_location is AUTO or empty, get the default install location from the manifest or system
                if ($AppConfig.install_location -eq 'AUTO' -or $AppConfig.install_location -eq '') {
                    $install_path = Get-DefaultInstallLocation -PackageId $id -GitHubToken $GitHubToken -AppName $AppName
                    $locationArg = "--location `"$install_path`""
                }
                elseif ($AppConfig.install_location -eq 'false') {
                    $locationArg = ''
                }
                elseif ($AppConfig.install_location -and $AppConfig.install_location -ne 'false') {
                    $install_path = $AppConfig.install_location
                    $locationArg = "--location `"$install_path`""
                }
                if ($install_path) { $install_mesg += " to '$install_path'" }
                $cmd = "winget install --id $id --silent --accept-package-agreements --accept-source-agreements --disable-interactivity $locationArg"
                Write-Log $install_mesg "INFO"
                Invoke-Expression $cmd
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Installed $AppName via $Provider" "SUCCESS"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Success" -DetailMessage "App '$AppName' (ID: $id) installed via $Provider."
                } else {
                    Write-Log "Failed installing $AppName via $Provider (exit code $LASTEXITCODE)" "ERROR"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage "App '$AppName' (ID: $id) failed to install via $Provider. Exit code: $LASTEXITCODE"
                }
            }
            'chocolatey' {
                $id = if ($null -ne $AppConfig.package_id) { $AppConfig.package_id } else { $AppName }
                Write-Log $install_mesg "INFO"
                choco install $id -y --source=community
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Installed $AppName (ID: $id) via $Provider" "SUCCESS"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Success" -DetailMessage "App '$AppName' (ID: $id) installed via $Provider."
                } else {
                    Write-Log "Failed installing $AppName (ID: $id) via $Provider (exit code $LASTEXITCODE)" "ERROR"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage "App '$AppName' (ID: $id) failed to install via $Provider. Exit code: $LASTEXITCODE"
                }
            }
            'scoop' {
                if ($AppConfig.bucket) {
                    Write-Log "Ensuring Scoop bucket '$($AppConfig.bucket)' is added." "DEBUG"
                    scoop bucket add $AppConfig.bucket -ErrorAction SilentlyContinue
                }
                $id = if ($null -ne $AppConfig.package_id) { $AppConfig.package_id } else { $AppName }
                Write-Log $install_mesg "INFO"
                scoop install $id
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Installed $AppName (ID: $id) via $Provider" "SUCCESS"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Success" -DetailMessage "App '$AppName' (ID: $id) installed via $Provider."
                } else {
                    Write-Log "Failed installing $AppName (ID: $id) via $Provider (exit code $LASTEXITCODE)" "ERROR"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage "App '$AppName' (ID: $id) failed to install via $Provider. Exit code: $LASTEXITCODE"
                }
            }
            'manual' {
                if ($AppConfig.install_location) {
                    $install_mesg += " to '$($AppConfig.install_location)'"
                }
                Write-Log $install_mesg "INFO"
                # Pass $AppConfig to Install-ManualApp
                Install-ManualApp -AppName $AppName -InstallerPath $null -AppConfig $AppConfig # InstallerPath will be derived from download_url in Install-ManualApp
                # Manual install logs its own result
            }
            'msstore' {
                Write-Log "$install_mesg (Attempting via Winget for MSStore app)" "INFO"
                $id = if ($null -ne $AppConfig.package_id) { $AppConfig.package_id } else { $AppName }
                $locationArg = ''
                if ($AppConfig.install_location -eq 'AUTO' -or [string]::IsNullOrEmpty($AppConfig.install_location)) {
                    Write-Log "Using Winget's default location for MSStore app $id." "DEBUG"
                }
                elseif ($AppConfig.install_location -and $AppConfig.install_location -ne 'false') {
                    $install_path = [Environment]::ExpandEnvironmentVariables($AppConfig.install_location)
                    $locationArg = "--location `"$install_path`""
                    if ($install_path) { $install_mesg += " to '$install_path'" } # Append to original message for clarity
                }

                $cmd = "winget install --id $id --source msstore --silent --accept-package-agreements --accept-source-agreements --disable-interactivity $locationArg"
                Write-Log "Executing: $cmd" "DEBUG"
                Invoke-Expression $cmd
                if ($LASTEXITCODE -eq 0) {
                    Write-Log "Installed $AppName (MSStore ID: $id via Winget) successfully." "SUCCESS"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Success" -DetailMessage "App '$AppName' (MSStore ID: $id) installed via Winget (--source msstore)."
                } else {
                    $errorDetail = "App '$AppName' (MSStore ID: $id) failed via Winget with --source msstore. Exit: $LASTEXITCODE."
                    Write-Log "$errorDetail Attempting winget default source as fallback." "ERROR"

                    $cmd = "winget install --id $id --silent --accept-package-agreements --accept-source-agreements --disable-interactivity $locationArg" # Fallback
                    Write-Log "Executing fallback: $cmd" "DEBUG"
                    Invoke-Expression $cmd
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "Installed $AppName (MSStore ID: $id via Winget fallback) successfully." "SUCCESS"
                        Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Success" -DetailMessage "App '$AppName' (MSStore ID: $id) installed via Winget fallback."
                    } else {
                        Write-Log "Failed installing $AppName (MSStore ID: $id via Winget fallback). Exit code: $LASTEXITCODE" "ERROR"
                        Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage "$errorDetail Also failed with Winget fallback. Exit: $LASTEXITCODE."
                    }
                }
            }
            'github_release' {
                Write-Log "$install_mesg (via GitHub Release from repo $($AppConfig.repo))" "INFO"
                if (-not $AppConfig.repo -or -not $AppConfig.asset_name) {
                    $errorMsg = "Missing 'repo' or 'asset_name' in AppConfig for $AppName. Cannot proceed with github_release."
                    Write-Log $errorMsg "ERROR"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
                    return
                }

                $latestReleaseUrl = "https://api.github.com/repos/$($AppConfig.repo)/releases/latest"
                $headers = @{}
                if (-not [string]::IsNullOrEmpty($GitHubToken)) {
                    $headers["Authorization"] = "token $GitHubToken"
                } else {
                    Write-Log "No GitHub token provided. Public API rate limits may apply for $($AppConfig.repo)." "WARNING"
                }

                try {
                    $releaseInfo = Invoke-RestMethod -Uri $latestReleaseUrl -Headers $headers -ErrorAction Stop -TimeoutSec 30
                } catch {
                    $errorMsg = "App '$AppName': Failed to fetch release info from $($AppConfig.repo): $($_.Exception.Message)"
                    Write-Log $errorMsg "ERROR"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
                    return
                }

                if (-not $releaseInfo) {
                    $errorMsg = "App '$AppName': No release information found for $($AppConfig.repo)."
                    Write-Log $errorMsg "ERROR"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
                    return
                }

                $asset = $null
                $assetNamePattern = $AppConfig.asset_name
                if ($assetNamePattern -eq 'latest_installer_exe') {
                    $asset = $releaseInfo.assets | Where-Object { $_.name -like '*.exe' } | Sort-Object -Property created_at -Descending | Select-Object -First 1
                } elseif ($assetNamePattern -eq 'latest_installer_msi') {
                    $asset = $releaseInfo.assets | Where-Object { $_.name -like '*.msi' } | Sort-Object -Property created_at -Descending | Select-Object -First 1
                } else {
                    $asset = $releaseInfo.assets | Where-Object { $_.name -like $assetNamePattern } | Sort-Object -Property created_at -Descending | Select-Object -First 1
                }

                if ($asset) {
                    Write-Log "Found asset: $($asset.name) with URL $($asset.browser_download_url)" "INFO"
                    $tempFile = Join-Path $env:TEMP $asset.name
                    try {
                        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tempFile -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop
                        Write-Log "Downloaded '$($asset.name)' to '$tempFile'." "INFO"
                        Install-ManualApp -AppName $AppName -InstallerPath $tempFile -InstallArgs $AppConfig.install_args -AppConfig $AppConfig
                    } catch {
                        $errorMsg = "App '$AppName': Error downloading or initiating install for asset '$($asset.name)': $($_.Exception.Message)"
                        Write-Log $errorMsg "ERROR"
                        Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
                    } finally {
                        if (Test-Path $tempFile) {
                            Write-Log "Cleaning up downloaded asset for $AppName: $tempFile" "DEBUG"
                            Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                        }
                    }
                } else {
                    $errorMsg = "App '$AppName': Asset '$($AppConfig.asset_name)' not found in latest release of $($AppConfig.repo)."
                    Write-Log $errorMsg "ERROR"
                    Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
                }
            }
            default {
                $errorMsg = "Unknown provider: $Provider for app $AppName"
                Write-Log $errorMsg "ERROR"
                Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
            }
        }
    }
    catch {
        # This is the main catch for Install-SingleApp
        $errorMsg = "Overall failure installing app '$AppName' (Provider: $Provider): $($_.Exception.Message)"
        Write-Log $errorMsg "ERROR"
        Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
    }
}

function Install-ManualApp {
    param(
        [string]$AppName,
        [string]$InstallerPath, # Can be null if AppConfig.download_url is used
        [string]$InstallArgs = "/S", # Default silent args
        [PSObject]$AppConfig = $null
    )

    $localInstallerPath = $InstallerPath
    $tempFileCreated = $false
    $extractDir = $null

    try {
        # If InstallerPath is not provided, assume download_url is in AppConfig
        if (-not $localInstallerPath -and $AppConfig -and $AppConfig.download_url) {
            $url = $AppConfig.download_url
            if ([string]::IsNullOrEmpty($url)) {
                $errorMsg = "App '$AppName' (Manual/GitHub): No InstallerPath provided and no download_url in AppConfig."
                Write-Log $errorMsg "ERROR"
                Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
                return
            }
            $localInstallerPath = Join-Path $env:TEMP ($url | Split-Path -Leaf)
            $tempFileCreated = $true
            Write-Log "Downloading manual app $AppName from $url to $localInstallerPath" "INFO"
            Invoke-WebRequest $url -OutFile $localInstallerPath -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop
            # If Invoke-WebRequest fails with -ErrorAction Stop, it will be caught by the main catch block.
            Write-Log "Successfully downloaded $AppName from $url" "INFO"
        } elseif (-not (Test-Path $localInstallerPath)) {
            $errorMsg = "App '$AppName' (Manual/GitHub): InstallerPath '$localInstallerPath' does not exist."
            Write-Log $errorMsg "ERROR"
            Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
            return
        }

        $ext = [IO.Path]::GetExtension($localInstallerPath).ToLower()

        if ($ext -eq '.zip') {
            $extractDir = Join-Path $env:TEMP ("$AppName" + "_extracted_release_" + (Get-Random))
            Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Path $extractDir -Force | Out-Null
            Write-Log "Extracting '$localInstallerPath' to '$extractDir'..." "INFO"
            Expand-Archive -Path $localInstallerPath -DestinationPath $extractDir -Force

            $potentialInstaller = $null
            if ($AppConfig -and $AppConfig.executable_in_zip) {
                 $specificInstallerPath = Join-Path $extractDir $AppConfig.executable_in_zip
                 if (Test-Path $specificInstallerPath) {
                    $potentialInstaller = Get-Item $specificInstallerPath
                 } else {
                    Write-Log "Specified executable_in_zip '$($AppConfig.executable_in_zip)' not found in $extractDir." "WARNING"
                 }
            }

            if (-not $potentialInstaller) {
                $potentialInstallers = Get-ChildItem -Path $extractDir -Recurse -File |
                                       Where-Object { $_.Name -match '^(setup|install|update).*\.exe$' -or $_.Extension -eq '.msi' } |
                                       Sort-Object Length | Select-Object -First 1
                $potentialInstaller = $potentialInstallers # Assign to the same variable
            }

            if ($potentialInstaller) {
                Write-Log "Found potential installer in ZIP: $($potentialInstaller.FullName)" "INFO"
                $localInstallerPath = $potentialInstaller.FullName # This path is now the one to be installed
                $ext = $potentialInstaller.Extension.ToLower()
                # Note: InstallArgs from AppConfig will be used. If different args are needed for the inner installer, this needs more logic.
            } else {
                $errorMsg = "App '$AppName' (Manual/GitHub): No common installer (.exe, .msi) or specified executable_in_zip found in extracted ZIP."
                Write-Log $errorMsg "ERROR" # Changed from WARNING to ERROR as it stops processing for this app
                Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
                return
            }
        }

        $installSuccess = $false
        Write-Log "Attempting to install $AppName using $localInstallerPath (args: $InstallArgs)" "INFO"
        switch ($ext) {
            '.exe' {
                Start-Process -FilePath $localInstallerPath -ArgumentList $InstallArgs -Wait -ErrorAction Stop
                if ($LASTEXITCODE -eq 0) { $installSuccess = $true }
            }
            '.msi' {
                # MSI already includes /qn for silent, so InstallArgs should be for other options if any
                $msiArgs = "/i `"$localInstallerPath`" /qn"
                if (-not [string]::IsNullOrEmpty($InstallArgs) -and $InstallArgs -ne "/S") { $msiArgs += " $InstallArgs" } # Append if not default /S
                Start-Process msiexec.exe -ArgumentList $msiArgs -Wait -ErrorAction Stop
                if ($LASTEXITCODE -eq 0) { $installSuccess = $true }
            }
            default {
                Write-Log "Unsupported installer type: '$ext' for $AppName from path '$localInstallerPath'." "WARNING"
                Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Warning" -DetailMessage "App '$AppName' (Manual/GitHub): Unsupported installer type '$ext'."
            }
        }

        if ($installSuccess) {
            Write-Log "Manual app $AppName installed successfully." "SUCCESS"
            Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Success" -DetailMessage "App '$AppName' (Manual/GitHub): Successfully installed."
        } else {
            # Only log error if not already handled by an unsupported type warning that didn't set $installSuccess
            if ($ext -in '.exe', '.msi') { # Only consider it an error if it was an attempted exe/msi
                Write-Log "Manual install for $AppName failed or reported non-zero exit code: $LASTEXITCODE." "ERROR"
                Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage "App '$AppName' (Manual/GitHub): Installation command failed or reported non-zero exit code: $LASTEXITCODE."
            }
        }
    }
    catch {
        $errorMsg = "App '$AppName' (Manual/GitHub): Failed during installation process: $($_.Exception.Message). Last exit code: $LASTEXITCODE"
        Write-Log $errorMsg "ERROR"
        Update-PhaseOutcome -PhaseName "Apps" -OutcomeType "Error" -DetailMessage $errorMsg
    }
    finally {
        if ($tempFileCreated -and (Test-Path $localInstallerPath) -and ($ext -ne '.zip')) { # Only remove if it was downloaded AND not a ZIP (zip path is original download)
             Write-Log "Cleaning up downloaded installer: $localInstallerPath" "DEBUG"
             Remove-Item $localInstallerPath -Force -ErrorAction SilentlyContinue
        }
        # If it was a ZIP that got extracted, $localInstallerPath might now point inside $extractDir.
        # The original ZIP (if downloaded) should be cleaned up if $tempFileCreated is true and $InstallerPath (original) points to it.
        if ($tempFileCreated -and $InstallerPath -and (Test-Path $InstallerPath) -and ($InstallerPath.ToLower().EndsWith(".zip")) ) {
             Write-Log "Cleaning up downloaded ZIP: $InstallerPath" "DEBUG"
             Remove-Item $InstallerPath -Force -ErrorAction SilentlyContinue
        }
        if ($extractDir -and (Test-Path $extractDir)) {
            Write-Log "Cleaning up extraction directory: $extractDir" "DEBUG"
            Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function *
    }
}

Export-ModuleMember -Function *
