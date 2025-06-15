<#
.SYNOPSIS
    Handles installation of Nerd Fonts and custom fonts based on the configuration.
.DESCRIPTION
    This module is responsible for the font provisioning phase of the script. It reads font configurations
    from the 'fonts_list' section of the main configuration object. It supports installing Nerd Fonts
    (via package managers or direct GitHub download) and custom fonts from specified URLs.
    It uses helper functions to manage different installation methods and checks if fonts are already installed.
    All operations are logged, and outcomes are reported to the 'Fonts' phase summary.
#>

<#
.SYNOPSIS
    Orchestrates the font installation process.
.DESCRIPTION
    This is the main entry point for the font installation phase. It first checks if the
    'fonts_provisioner.enabled' flag in the configuration is true. If not, it skips font installation.
    Otherwise, it initializes the 'Fonts' phase summary.
    It then processes Nerd Fonts if 'fonts_list.nerdfonts' is enabled and configured, by calling 'Install-NerdFonts'.
    Subsequently, it processes any custom fonts listed in 'fonts_list.custom' if they are enabled,
    by calling 'Install-CustomFont' for each.
.PARAMETER Config
    The main configuration object, which should contain 'fonts_provisioner' (for enabling the phase)
    and 'fonts_list' (with 'nerdfonts' and 'custom' subsections) for font details. Mandatory.
.EXAMPLE
    PS C:\> Install-Fonts -Config $loadedConfigObject
    This command initiates the font installation process based on the provided configuration.
.NOTES
    Relies on helper functions like Install-NerdFonts and Install-CustomFont for specific installation tasks.
    Logs the start and completion of the font installation phase.
#>
function Install-Fonts {
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$Config
    )

    # Phase enable/disable check: Still uses 'fonts_provisioner.enabled' for overall phase control.
    if (-not $Config.PSObject.Properties.Name -contains 'fonts_provisioner' -or -not $Config.fonts_provisioner.enabled) {
        Write-Log "Fonts installation phase is disabled in configuration via 'fonts_provisioner.enabled'." "INFO"
        return
    }

    Write-Log "Beginning font installation..." "INFO"
    Initialize-PhaseSummary "Fonts" # Initialize phase summary for font operations.

    # Nerd Fonts Installation from fonts_list.nerdfonts
    # Checks if the nerdfonts section and its 'enabled' flag are present and true.
    if ($Config.PSObject.Properties.Name -contains 'fonts_list' -and `
        $null -ne $Config.fonts_list -and `
        $Config.fonts_list.PSObject.Properties.Name -contains 'nerdfonts' -and `
        $null -ne $Config.fonts_list.nerdfonts -and `
        $Config.fonts_list.nerdfonts.PSObject.Properties.Name -contains 'enabled' -and `
        $Config.fonts_list.nerdfonts.enabled -eq $true) {

        Write-Log "Nerd Fonts installation is enabled via 'fonts_list.nerdfonts.enabled'." "INFO"
        Install-NerdFonts -NerdFontsConfig $Config.fonts_list.nerdfonts
    }
    else {
        Write-Log "Nerd Fonts installation is disabled or 'fonts_list.nerdfonts' section is missing/misconfigured." "INFO"
    }

    # Custom Fonts Installation from fonts_list.custom
    # Checks if the custom fonts section exists. Individual fonts within it have their own 'enabled' flags.
    if ($Config.PSObject.Properties.Name -contains 'fonts_list' -and `
        $null -ne $Config.fonts_list -and `
        $Config.fonts_list.PSObject.Properties.Name -contains 'custom' -and `
        $null -ne $Config.fonts_list.custom) {

        Write-Log "Processing custom fonts defined in 'fonts_list.custom'." "INFO"
        foreach ($customFontEntry in $Config.fonts_list.custom) {
            # Each custom font entry must also be individually enabled.
            if ($customFontEntry.PSObject.Properties.Name -contains 'enabled' -and $customFontEntry.enabled -eq $true) {
                Install-CustomFont -CustomFontConfig $customFontEntry
            }
            else {
                Write-Log "Custom font '$($customFontEntry.name)' is disabled or its 'enabled' key is missing." "INFO"
                 Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Warning" -DetailMessage "Custom font '$($customFontEntry.name)' skipped (disabled or misconfigured)."
            }
        }
    }
    else {
        Write-Log "'fonts_list.custom' section is missing, empty, or not an array. No custom fonts to process." "INFO"
    }

    Write-Log "Font installation phase complete." "SUCCESS"
}

<#
.SYNOPSIS
    Checks if a given font name is already installed on the system.
.DESCRIPTION
    This function attempts to determine if a font matching the provided 'FontName' is installed.
    It performs two main checks:
    1. Filesystem Check: Lists files in the system fonts directory (C:\Windows\Fonts) and checks if any
       font file name (e.g., .ttf, .otf) contains the 'FontName'. This check is case-insensitive
       and ignores spaces within both the file name and the provided 'FontName' for more flexible matching.
    2. Registry Check: Queries font entries under 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts\'.
       It checks both the registry key name (e.g., "Arial (TrueType)") and the font file name often stored as the value
       of these registry entries against the 'FontName'. This check is also space-insensitive and case-insensitive.
.PARAMETER FontName
    The name of the font to check for (e.g., "Fira Code", "Consolas", "My Custom Font"). Mandatory.
.EXAMPLE
    PS C:\> if (Test-FontInstalled -FontName "Fira Code") { Write-Log "Fira Code is installed." "INFO" }
    Checks if "Fira Code" is installed.

.EXAMPLE
    PS C:\> Test-FontInstalled -FontName "NonExistent Font 123"
    Returns $false if the font is not found by any check.
.NOTES
    The function logs its checking process at the DEBUG level.
    It returns $true as soon as a match is found by any method, otherwise returns $false after all checks.
    The matching is designed to be somewhat fuzzy regarding spaces to handle variations in font naming.
#>
function Test-FontInstalled {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FontName
    )
    Write-Log "DEBUG: Test-FontInstalled checking for font matching '$FontName'" "DEBUG"
    # Prepare a version of the font name without spaces for more robust matching against file/registry names.
    $strippedFontName = $FontName -replace '\s',''

    # Check 1: System Fonts Directory (e.g., C:\Windows\Fonts)
    # This looks for font files (.ttf, .otf, etc.) whose names contain the stripped font name.
    try {
        $fontFiles = Get-ChildItem "$env:SystemRoot\Fonts" -File -ErrorAction SilentlyContinue # Avoid error if path is restricted, though unlikely for system fonts.
        foreach ($fontFile in $fontFiles) {
            # Compare stripped file name (without extension) against stripped input font name.
            if (($fontFile.BaseName -replace '\s','') -match [regex]::Escape($strippedFontName)) {
                Write-Log "DEBUG: Found matching font file: $($fontFile.Name) for '$FontName' (Filesystem check)." "DEBUG"
                return $true
            }
        }
    } catch {
        Write-Log "DEBUG: Error accessing system font directory for Test-FontInstalled: $($_.Exception.Message)" "DEBUG"
    }


    # Check 2: Windows Font Registry
    # This checks registry entries which often list installed fonts.
    try {
        # Query all font entries under the specified registry path.
        $registryFonts = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts\*' -ErrorAction SilentlyContinue
        foreach ($regFont in $registryFonts) {
            # The PSChildName is often the display name of the font, e.g., "Arial (TrueType)".
            if (($regFont.PSChildName -replace '\s','') -match [regex]::Escape($strippedFontName)) {
                Write-Log "DEBUG: Found matching registry entry (PSChildName): '$($regFont.PSChildName)' for '$FontName'." "DEBUG"
                return $true
            }
            # The value of the registry entry often contains the actual font file name.
            # Ensure it's a string before trying to match.
            if ($regFont.PSObject.Properties.Name -contains $regFont.PSChildName) { # Check if property exists
                 $fontFileInReg = $regFont.$($regFont.PSChildName)
                 if ($fontFileInReg -is [string] -and (($fontFileInReg -replace '\s','').Split('.')[0] -match [regex]::Escape($strippedFontName))) {
                    Write-Log "DEBUG: Found matching font file in registry data: '$fontFileInReg' for '$FontName'." "DEBUG"
                    return $true
                }
            }
        }
    } catch {
        # Log if registry query fails, but don't let it stop the function.
        Write-Log "DEBUG: Could not query registry for fonts (this might happen on non-Windows or restricted environments): $($_.Exception.Message)" "DEBUG"
    }

    Write-Log "DEBUG: Font '$FontName' not found by file or registry check." "DEBUG"
    return $false
}

<#
.SYNOPSIS
    Orchestrates the installation of Nerd Fonts using various methods.
.DESCRIPTION
    This function attempts to install a list of specified Nerd Fonts. It iterates through a predefined
    set of installation methods (Chocolatey, Scoop, GitHub direct download) in order of preference.
    For each method, it tries to install all fonts listed in '$NerdFontsConfig.fonts'.
    If all fonts are successfully installed (or already present) by one method, it stops and does not try subsequent methods.
    It uses 'Test-FontInstalled' to check if a font is already present before attempting installation with a given method.
    Outcomes (success/failure/already installed) for each font are reported to the 'Fonts' phase summary.
.PARAMETER NerdFontsConfig
    A PowerShell object containing the Nerd Fonts configuration, typically from '$Config.fonts_list.nerdfonts'.
    This object must have a '.fonts' property which is an array of strings (font names like "FiraCode", "Hack").
.EXAMPLE
    PS C:\> $nerdFontSettings = @{ fonts = @("FiraCode", "JetBrainsMono") }
    PS C:\> Install-NerdFonts -NerdFontsConfig $nerdFontSettings
    This attempts to install FiraCode and JetBrainsMono Nerd Fonts using available methods.
.NOTES
    Relies on provider test functions (Test-ChocolateyCommand, Test-ScoopCommand) being available.
    If a package manager method (Chocolatey, Scoop) is chosen, it constructs package names (e.g., 'firacode-nerd-font' for Chocolatey).
    The GitHub method calls 'Install-NerdFontsFromGitHub'.
    Success is tracked per font; the function aims to ensure all requested fonts are present.
#>
function Install-NerdFonts {
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$NerdFontsConfig
    )

    $methods = @('chocolatey', 'scoop', 'github') # Order of preference for installation methods.
    $fontsToInstall = $NerdFontsConfig.fonts
    $anyFontSuccessfullyProcessed = $false # Tracks if any font was successfully installed or confirmed present by any method.

    if (-not $fontsToInstall -or $fontsToInstall.Count -eq 0) {
        Write-Log "No Nerd Fonts listed in configuration to install." "INFO"
        return
    }

    foreach ($method in $methods) {
        Write-Log "Attempting Nerd Font installation for all listed fonts via method: '$method'" "INFO"
        $allFontsHandledByThisMethod = $true # Flag: Did this method handle all fonts (either by installing or confirming existing)?

        try {
            switch ($method) {
                'chocolatey' {
                    if (Get-Command 'Test-ChocolateyCommand' -ErrorAction SilentlyContinue) {
                        if (Test-ChocolateyCommand) { # Check if Chocolatey command is available
                            foreach ($fontName in $fontsToInstall) {
                                $chocoPackageName = "$($fontName.ToLower())-nerd-font" # Common Chocolatey naming convention for Nerd Fonts
                                Write-Log "Attempting Chocolatey install for Nerd Font '$fontName' (as package '$chocoPackageName')..." "INFO"
                                if (Test-FontInstalled -FontName $fontName) {
                                    Write-Log "Nerd Font '$fontName' already installed, skipping Chocolatey attempt." "INFO"
                                    Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Nerd Font '$fontName' already installed (checked for Chocolatey)."
                                    # This font is handled, continue to next font for this method
                                } else {
                                    choco install $chocoPackageName -y --source=community # Attempt installation
                                    if ($LASTEXITCODE -eq 0) {
                                        Write-Log "Successfully installed Nerd Font '$chocoPackageName' via Chocolatey." "SUCCESS"
                                        Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Nerd Font '$fontName' (as '$chocoPackageName') installed via Chocolatey."
                                        $anyFontSuccessfullyProcessed = $true
                                    } else {
                                        Write-Log "Failed to install Nerd Font '$chocoPackageName' via Chocolatey. Exit code: $LASTEXITCODE" "ERROR"
                                        Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Error" -DetailMessage "Failed to install Nerd Font '$fontName' (as '$chocoPackageName') via Chocolatey. Exit code: $LASTEXITCODE"
                                        $allFontsHandledByThisMethod = $false # This font was not successfully handled by this method.
                                    }
                                }
                            }
                        } else {
                            Write-Log "Chocolatey command/provider not available, skipping Chocolatey method." "INFO"
                            $allFontsHandledByThisMethod = $false # Cannot use this method for any font.
                        }
                    } else {
                        Write-Log "Test-ChocolateyCommand function not found (module issue?), skipping Chocolatey method for Nerd Fonts." "WARNING"
                        $allFontsHandledByThisMethod = $false
                    }
                }
                'scoop' {
                    if (Get-Command 'Test-ScoopCommand' -ErrorAction SilentlyContinue) {
                        if (Test-ScoopCommand) { # Check if Scoop command is available
                            scoop bucket add nerd-fonts -ErrorAction SilentlyContinue # Ensure the nerd-fonts bucket is available.
                            foreach ($fontName in $fontsToInstall) {
                                Write-Log "Attempting Scoop install for Nerd Font '$fontName'..." "INFO"
                                if (Test-FontInstalled -FontName $fontName) {
                                    Write-Log "Nerd Font '$fontName' already installed, skipping Scoop attempt." "INFO"
                                    Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Nerd Font '$fontName' already installed (checked for Scoop)."
                                } else {
                                    scoop install $fontName # Scoop often uses the direct font name.
                                    if ($LASTEXITCODE -eq 0) {
                                        Write-Log "Successfully installed Nerd Font '$fontName' via Scoop." "SUCCESS"
                                        Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Nerd Font '$fontName' installed via Scoop."
                                        $anyFontSuccessfullyProcessed = $true
                                    } else {
                                        Write-Log "Failed to install Nerd Font '$fontName' via Scoop. Exit code: $LASTEXITCODE" "ERROR"
                                        Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Error" -DetailMessage "Failed to install Nerd Font '$fontName' via Scoop. Exit code: $LASTEXITCODE"
                                        $allFontsHandledByThisMethod = $false
                                    }
                                }
                            }
                        } else {
                            Write-Log "Scoop command/provider not available, skipping Scoop method." "INFO"
                            $allFontsHandledByThisMethod = $false
                        }
                    } else {
                        Write-Log "Test-ScoopCommand function not found (module issue?), skipping Scoop method for Nerd Fonts." "WARNING"
                        $allFontsHandledByThisMethod = $false
                    }
                }
                'github' {
                    # GitHub method attempts all listed fonts not yet installed.
                    # It internally calls Test-FontInstalled and Update-PhaseOutcome.
                    Write-Log "Attempting Nerd Font installation via direct GitHub download..." "INFO"
                    # The Install-NerdFontsFromGitHub function will handle individual outcomes.
                    # We assume if it's called, it attempts all specified fonts.
                    # Success here means the function completed its process for the listed fonts.
                    # Individual font success/failure is handled within that function.
                    Install-NerdFontsFromGitHub -NerdFontsConfig $NerdFontsConfig
                    # To determine if this method contributed to overall success:
                    # We might need Install-NerdFontsFromGitHub to return a status or check PhaseSummaries.
                    # For simplicity now, if we reach GitHub, we assume it's the final attempt or preferred fallback.
                    # $anyFontSuccessfullyProcessed will be true if any font got installed/confirmed by GitHub method.
                    # $allFontsHandledByThisMethod can be set to $true if we assume GitHub is the ultimate fallback.
                    # This part of logic might need refinement based on desired behavior for $allFontsHandledByThisMethod.
                    # For now, we'll assume it attempts all, and internal calls update phase outcomes.
                    $allFontsHandledByThisMethod = $true # Assume GitHub method attempts all remaining.
                }
            } # End Switch

            # If this method successfully handled all fonts, no need to try other methods.
            if ($allFontsHandledByThisMethod) {
                 # Check if all fonts are actually installed now
                 $allEffectivelyInstalled = $true
                 foreach($fontNameCheck in $fontsToInstall){
                     if (-not (Test-FontInstalled -FontName $fontNameCheck)) {
                         $allEffectivelyInstalled = $false; break
                     }
                 }
                 if($allEffectivelyInstalled) {
                    Write-Log "All listed Nerd Fonts appear to be installed after attempting method '$method'." "SUCCESS"
                    $anyFontSuccessfullyProcessed = $true # Ensure this is set
                    break # Exit methods loop
                 } else {
                    Write-Log "Method '$method' completed, but not all fonts are confirmed installed. Trying next method if available." "INFO"
                 }
            } elseif ($anyFontSuccessfullyProcessed) {
                 Write-Log "Some Nerd Fonts processed via method '$method'. Continuing with remaining fonts or other methods if needed." "INFO"
            }

        } catch {
            Write-Log "Error during Nerd Font installation attempt via method '$method': $($_.Exception.Message)" "WARNING"
            $allFontsHandledByThisMethod = $false # This method failed, ensure we don't break prematurely.
        }
    } # End foreach $method

    # Final check on overall success for the Nerd Fonts installation task.
    # This is a bit broad. The PhaseSummary will have per-font details.
    # We can check if all *requested* fonts are now installed.
    $finalCheckAllInstalled = $true
    foreach($fontNameFinalCheck in $fontsToInstall){
        if (-not (Test-FontInstalled -FontName $fontNameFinalCheck)) {
            $finalCheckAllInstalled = $false
            Write-Log "Nerd Font '$fontNameFinalCheck' still not found after all methods." "ERROR"
            # Update-PhaseOutcome for error was likely already called by the failing method.
            # If not (e.g. method skipped and GitHub never ran), this could be a place for a final error update.
            # However, this might lead to double error logging if a method already reported it.
            # For now, rely on methods to report their specific errors.
        }
    }

    if (-not $finalCheckAllInstalled) {
        Write-Log "One or more Nerd Fonts could not be installed after trying all available methods." "ERROR"
    } else {
        Write-Log "Nerd Font installation process completed. All requested fonts should be available." "INFO"
    }
}

<#
.SYNOPSIS
    Installs Nerd Fonts directly from GitHub releases.
.DESCRIPTION
    Iterates through a list of Nerd Font names provided in '$NerdFontsConfig.fonts'.
    For each font, it checks if it's already installed using 'Test-FontInstalled'.
    If not installed, it constructs a download URL for the font's ZIP file from the
    ryanoasis/nerd-fonts GitHub repository (latest release).
    It downloads the ZIP, extracts it to a temporary location, and then searches for
    .ttf and .otf font files within the extracted contents (including subdirectories).
    Each found font file is again checked with 'Test-FontInstalled' (using its specific name)
    and copied to the system fonts directory (C:\Windows\Fonts) if not already present.
    Errors during download, extraction, or copying are caught and logged for each font.
    Temporary files and directories are cleaned up afterwards.
    Outcomes are reported to the 'Fonts' phase summary.
.PARAMETER NerdFontsConfig
    A PowerShell object, typically from '$Config.fonts_list.nerdfonts', which must contain a '.fonts'
    property that is an array of Nerd Font names (e.g., "FiraCode", "JetBrainsMono").
.EXAMPLE
    PS C:\> $nfConfig = @{ fonts = @("FiraCode", "Terminus") }
    PS C:\> Install-NerdFontsFromGitHub -NerdFontsConfig $nfConfig
    This will attempt to download and install the FiraCode and Terminus Nerd Fonts from GitHub.
.NOTES
    Requires internet access. Assumes the font names in the config correspond to the ZIP file names
    on the ryanoasis/nerd-fonts releases page (e.g., "FiraCode" -> "FiraCode.zip").
    Uses Invoke-WebRequest for downloads and Expand-Archive for extraction.
    Individual font file installation uses Copy-Item.
#>
function Install-NerdFontsFromGitHub {
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$NerdFontsConfig
    )

    $baseTmpDir = Join-Path $env:TEMP "nerdfonts_github_install" # Made path more specific
    New-Item -ItemType Directory -Path $baseTmpDir -Force | Out-Null
    $anyFontProcessedSuccessfullyInThisRun = $false # Tracks if any action (install or found existing) occurred for any font.

    foreach ($fontName in $NerdFontsConfig.fonts) {
        # Check if the overall font (e.g., "FiraCode") is considered installed first.
        if (Test-FontInstalled -FontName $fontName) {
            Write-Log "Nerd Font '$fontName' (main name) detected as already installed (checked before download)." "INFO"
            Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Nerd Font '$fontName' already installed (checked before GitHub download)."
            $anyFontProcessedSuccessfullyInThisRun = $true
            continue # Skip to the next font in the list.
        }

        $fontSpecificTmpDir = Join-Path $baseTmpDir $fontName # Temp dir for this specific font.
        New-Item -ItemType Directory -Path $fontSpecificTmpDir -Force | Out-Null
        Write-Log "Attempting to install Nerd Font '$fontName' from GitHub..." "INFO"

        try {
            # Construct download URL (assumes fontName matches ZIP name).
            $url = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$fontName.zip"
            $zipPath = Join-Path $fontSpecificTmpDir "$fontName.zip"
            $extractPath = Join-Path $fontSpecificTmpDir "extracted"

            Write-Log "Downloading Nerd Font '$fontName' from $url to $zipPath..." "DEBUG"
            Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing -TimeoutSec 600 -ErrorAction Stop
            Write-Log "Download successful for $fontName.zip." "INFO"

            Write-Log "Extracting '$zipPath' to '$extractPath'..." "DEBUG"
            Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force -ErrorAction Stop
            Write-Log "Extraction successful for $fontName.zip." "INFO"

            # Find all .ttf and .otf font files in the extracted directory.
            $fontFilesFound = Get-ChildItem $extractPath -Recurse -Include *.ttf, *.otf
            if ($fontFilesFound.Count -eq 0) {
                Write-Log "No .ttf or .otf font files found in the extracted archive for $fontName." "WARNING"
                Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Warning" -DetailMessage "Nerd Font '$fontName': No .ttf or .otf files found in downloaded ZIP."
                # Continue to finally block for cleanup for this font.
                # Do not set $anyFontProcessedSuccessfullyInThisRun to true unless a font file is actually handled.
            }

            foreach ($fontFileItem in $fontFilesFound) {
                # Use the specific font file's base name (name without extension) for the installation check.
                $fontFileNameForTest = $fontFileItem.BaseName
                if (Test-FontInstalled -FontName $fontFileNameForTest) {
                    Write-Log "Font file '$($fontFileItem.Name)' (from $fontName package) already installed." "INFO"
                    Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Nerd Font file '$($fontFileItem.Name)' (from $fontName package) already installed."
                    $anyFontProcessedSuccessfullyInThisRun = $true
                    continue # Next font file
                }

                # Attempt to copy the font file to the system fonts directory.
                try {
                    Copy-Item $fontFileItem.FullName -Destination "$env:SystemRoot\Fonts" -Force -ErrorAction Stop
                    Write-Log "Successfully installed font file: $($fontFileItem.Name) to $env:SystemRoot\Fonts" "SUCCESS"
                    Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Installed Nerd Font file '$($fontFileItem.Name)' (from $fontName package)."
                    $anyFontProcessedSuccessfullyInThisRun = $true
                } catch {
                    $errorMsg = "Failed to copy font file '$($fontFileItem.Name)' (from Nerd Font '$fontName') to system font directory: $($_.Exception.Message)"
                    Write-Log $errorMsg "ERROR"
                    Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Error" -DetailMessage $errorMsg
                }
            }
        }
        catch {
            # Catch errors from Invoke-WebRequest, Expand-Archive, or other unexpected issues for this font.
            $errorMsg = "Failed to download, extract, or process Nerd Font '$fontName' from GitHub: $($_.Exception.Message)"
            Write-Log $errorMsg "ERROR"
            Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Error" -DetailMessage $errorMsg
        }
        finally {
            # Clean up the temporary directory for this specific font.
            if (Test-Path $fontSpecificTmpDir) {
                Write-Log "Cleaning up temporary directory for Nerd Font '$fontName': $fontSpecificTmpDir" "DEBUG"
                Remove-Item -Recurse -Force $fontSpecificTmpDir -ErrorAction SilentlyContinue
            }
        }
    } # End foreach $fontName in $NerdFontsConfig.fonts

    if ($anyFontProcessedSuccessfullyInThisRun) {
         Write-Log "GitHub Nerd Font installation/verification process finished for all listed fonts." "INFO"
    } else {
         Write-Log "No new Nerd Fonts were installed or confirmed existing from GitHub (either all failed or none were specified/found)." "WARNING"
    }
    # Cleanup base temp dir if it's empty (meaning all sub-folders were cleaned up).
    if (Test-Path $baseTmpDir -and (Get-ChildItem $baseTmpDir -ErrorAction SilentlyContinue).Count -eq 0) {
        Remove-Item -Recurse -Force $baseTmpDir -ErrorAction SilentlyContinue
    }
}

<#
.SYNOPSIS
    Installs a single custom font from a specified URL.
.DESCRIPTION
    This function handles the download and installation of a custom font. The font source is defined by a URL
    in the '$CustomFontConfig.url' property. The function first checks if a font matching
    '$CustomFontConfig.name' is already installed using 'Test-FontInstalled'.
    If not, it downloads the file from the URL.
    - If the downloaded file is a ZIP archive (.zip), it extracts the archive to a temporary location,
      searches for .ttf or .otf font files within it, checks each one with 'Test-FontInstalled',
      and copies new ones to the system fonts directory.
    - If the downloaded file is a direct font file (.ttf, .otf), it's copied to the system fonts directory
      (after a final 'Test-FontInstalled' check on its specific name).
    Errors during download, extraction, or copying are caught and logged. Temporary files are cleaned up.
    Outcomes are reported to the 'Fonts' phase summary.
.PARAMETER CustomFontConfig
    A PowerShell object representing a single custom font entry from the '$Config.fonts_list.custom' array.
    This object must contain:
    - 'name' (string): The display name of the font, used for checking if already installed and for logging.
    - 'url' (string): The direct URL to download the font file (can be a .zip, .ttf, or .otf).
    - 'enabled' (boolean): This should be checked by the caller; this function assumes the font is enabled.
.EXAMPLE
    PS C:\> $fontEntry = @{ name = "My корпоративный Font"; url = "http://example.com/fonts/MyCorpFont.zip"; enabled = $true }
    PS C:\> Install-CustomFont -CustomFontConfig $fontEntry
    This attempts to download "MyCorpFont.zip", extract it, and install any .ttf/.otf files found within.
.NOTES
    Requires internet access for downloading fonts.
    Uses Invoke-WebRequest for downloads, Expand-Archive for ZIPs, and Copy-Item for installation.
    Temporary files are created in $env:TEMP and cleaned up.
    Font names with special characters might affect temporary path creation; names are sanitized for paths.
#>
function Install-CustomFont {
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$CustomFontConfig
    )

    $fontName = $CustomFontConfig.name
    $fontUrl = $CustomFontConfig.url
    # $fontEnabled property is assumed to be checked by the caller (Install-Fonts function).

    Write-Log "Processing custom font: '$fontName' from URL: '$fontUrl'" "INFO"

    # Check if the font (by its configured name) is already installed.
    if (Test-FontInstalled -FontName $fontName) {
        Write-Log "Custom font '$fontName' already installed (checked by config name)." "INFO"
        Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Custom font '$fontName' already installed."
        return
    }

    # Sanitize font name for use in temporary directory path to avoid issues with special characters.
    $sanitizedFontName = $fontName -replace '[^a-zA-Z0-9_.-]','_' # Allow common path characters
    $tempDir = Join-Path $env:TEMP "custom_font_$($sanitizedFontName)_$(Get-Random -Maximum 99999)"
    $downloadedFilePath = ""
    $extractionDir = "" # For ZIPs
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        $fileNameFromUrl = $fontUrl | Split-Path -Leaf # Get the filename from the URL.
        $downloadedFilePath = Join-Path $tempDir $fileNameFromUrl

        Write-Log "Downloading custom font '$fontName' from '$fontUrl' to '$downloadedFilePath'..." "DEBUG"
        Invoke-WebRequest -Uri $fontUrl -OutFile $downloadedFilePath -UseBasicParsing -TimeoutSec 300 -ErrorAction Stop
        Write-Log "Custom font '$fontName' (file '$fileNameFromUrl') downloaded successfully." "INFO"

        # Process based on file type (ZIP archive or direct font file).
        if ($downloadedFilePath.EndsWith(".zip", [System.StringComparison]::OrdinalIgnoreCase)) {
            $extractionDir = Join-Path $tempDir "extracted"
            New-Item -ItemType Directory -Path $extractionDir -Force | Out-Null
            Write-Log "Expanding archive '$downloadedFilePath' to '$extractionDir'..." "DEBUG"
            Expand-Archive -Path $downloadedFilePath -DestinationPath $extractionDir -Force -ErrorAction Stop

            $fontFilesInZip = Get-ChildItem $extractionDir -Recurse -Include *.ttf, *.otf
            if ($fontFilesInZip.Count -eq 0) {
                Write-Log "No .ttf or .otf files found in extracted archive for custom font '$fontName'." "WARNING"
                Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Warning" -DetailMessage "Custom font '$fontName': No .ttf or .otf files found in ZIP '$fileNameFromUrl'."
            }
            foreach ($fontFileItem in $fontFilesInZip) {
                $fontFileNameForTest = $fontFileItem.BaseName # Check using the specific name of the font file.
                if (Test-FontInstalled -FontName $fontFileNameForTest) {
                    Write-Log "Font file '$($fontFileItem.Name)' (from custom font '$fontName' ZIP) already installed." "INFO"
                    Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Custom font file '$($fontFileItem.Name)' (from '$fontName' ZIP) already installed."
                    continue
                }
                # Attempt to copy the font file.
                Copy-Item $fontFileItem.FullName -Destination "$env:SystemRoot\Fonts" -Force -ErrorAction Stop
                Write-Log "Successfully installed custom font file: $($fontFileItem.Name) to $env:SystemRoot\Fonts (from '$fontName' ZIP)" "SUCCESS"
                Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Installed custom font file '$($fontFileItem.Name)' (for custom font '$fontName')."
            }
        }
        elseif ($downloadedFilePath.EndsWith(".ttf", [System.StringComparison]::OrdinalIgnoreCase) -or `
                 $downloadedFilePath.EndsWith(".otf", [System.StringComparison]::OrdinalIgnoreCase)) {
            # This is a direct font file. The initial Test-FontInstalled (by config name) failed.
            # Now, test again using the actual filename before copying.
            $actualFontFileName = $downloadedFilePath | Split-Path -Leaf
            if (Test-FontInstalled -FontName ($actualFontFileName | Split-Path -LeafBase)) {
                 Write-Log "Direct font file '$actualFontFileName' (for custom font '$fontName') already installed." "INFO"
                 Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Direct custom font file '$actualFontFileName' (for '$fontName') already installed."
            } else {
                $destinationPath = Join-Path "$env:SystemRoot\Fonts" $actualFontFileName
                Copy-Item $downloadedFilePath -Destination $destinationPath -Force -ErrorAction Stop
                Write-Log "Successfully installed custom font file: $actualFontFileName to $env:SystemRoot\Fonts" "SUCCESS"
                Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Installed custom font file '$actualFontFileName' (for custom font '$fontName')."
            }
        }
        else {
            # Unsupported file type.
            Write-Log "Downloaded file for custom font '$fontName' is not a .zip, .ttf, or .otf: '$fileNameFromUrl'. Cannot install." "WARNING"
            Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Warning" -DetailMessage "Custom font '$fontName': downloaded file '$fileNameFromUrl' is not a supported font type or ZIP."
        }
    }
    catch {
        # Catch errors from Invoke-WebRequest, Expand-Archive, Copy-Item, etc.
        $errorMsg = "Failed to install custom font '$fontName' (URL: $fontUrl): $($_.Exception.Message)"
        Write-Log $errorMsg "ERROR"
        Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Error" -DetailMessage $errorMsg
    }
    finally {
        # Clean up the temporary directory created for this font.
        if (Test-Path $tempDir) {
            Write-Log "Cleaning up temporary directory for custom font '$fontName': $tempDir" "DEBUG"
            Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
        }
    }
}

# Export public functions. Helper functions like Install-NerdFonts, Install-NerdFontsFromGitHub,
# and Install-CustomFont are typically not exported if Install-Fonts is the main entry point.
Export-ModuleMember -Function Install-Fonts, Test-FontInstalled
