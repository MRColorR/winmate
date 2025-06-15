<#!
.SYNOPSIS
    Handles installation of Nerd Fonts and custom fonts
#>

function Install-Fonts {
    param(
        [PSObject]$Config
    )

    # Still check fonts_provisioner.enabled at the top level for phase control
    if (-not $Config.PSObject.Properties.Name -contains 'fonts_provisioner' -or -not $Config.fonts_provisioner.enabled) {
        Write-Log "Fonts installation phase is disabled in configuration via 'fonts_provisioner.enabled'." "INFO"
        return
    }

    Write-Log "Beginning font installation..." "INFO"
    Initialize-PhaseSummary "Fonts" # Initialize phase summary

    # Nerd Fonts Installation from fonts_list.nerdfonts
    if ($Config.PSObject.Properties.Name -contains 'fonts_list' -and `
        $null -ne $Config.fonts_list -and `
        $Config.fonts_list.PSObject.Properties.Name -contains 'nerdfonts' -and `
        $null -ne $Config.fonts_list.nerdfonts -and `
        $Config.fonts_list.nerdfonts.PSObject.Properties.Name -contains 'enabled' -and `
        $Config.fonts_list.nerdfonts.enabled -eq $true) {

        Write-Log "Nerd Fonts installation is enabled." "INFO"
        Install-NerdFonts -NerdFontsConfig $Config.fonts_list.nerdfonts
    }
    else {
        Write-Log "Nerd Fonts installation is disabled or 'fonts_list.nerdfonts' section is missing/misconfigured." "INFO"
    }

    # Custom Fonts Installation from fonts_list.custom
    if ($Config.PSObject.Properties.Name -contains 'fonts_list' -and `
        $null -ne $Config.fonts_list -and `
        $Config.fonts_list.PSObject.Properties.Name -contains 'custom' -and `
        $null -ne $Config.fonts_list.custom) {

        Write-Log "Processing custom fonts." "INFO"
        foreach ($customFontEntry in $Config.fonts_list.custom) {
            if ($customFontEntry.PSObject.Properties.Name -contains 'enabled' -and $customFontEntry.enabled -eq $true) {
                Install-CustomFont -CustomFontConfig $customFontEntry
            }
            else {
                Write-Log "Custom font '$($customFontEntry.name)' is disabled or 'enabled' key missing." "INFO"
            }
        }
    }
    else {
        Write-Log "'fonts_list.custom' section is missing or empty." "INFO"
    }

    Write-Log "Font installation phase complete." "SUCCESS"
}

function Test-FontInstalled {
    param(
        [string]$FontName
    )
    Write-Log "DEBUG: Test-FontInstalled checking for font matching '$FontName'" "DEBUG"
    $strippedFontName = $FontName -replace '\s',''

    # Check 1: System Fonts Directory
    $fontFiles = Get-ChildItem "$env:SystemRoot\Fonts" -File
    foreach ($fontFile in $fontFiles) {
        if (($fontFile.Name -replace '\s','') -match [regex]::Escape($strippedFontName)) {
            Write-Log "DEBUG: Found matching font file: $($fontFile.Name) for '$FontName'" "DEBUG"
            return $true
        }
    }

    # Check 2: Registry
    try {
        $registryFonts = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts\*' -ErrorAction SilentlyContinue
        foreach ($regFont in $registryFonts) {
            if (($regFont.PSChildName -replace '\s','') -match [regex]::Escape($strippedFontName)) {
                Write-Log "DEBUG: Found matching registry entry: $($regFont.PSChildName) for '$FontName'" "DEBUG"
                return $true
            }
            # Also check the font filename part in the registry data if available
            if ($regFont.PSObject.Properties.Value -is [string] -and (($regFont.PSObject.Properties.Value -replace '\s','') -match [regex]::Escape($strippedFontName))) {
                 Write-Log "DEBUG: Found matching font file in registry data: $($regFont.PSObject.Properties.Value) for '$FontName'" "DEBUG"
                return $true
            }
        }
    } catch {
        Write-Log "DEBUG: Could not query registry for fonts (this might happen on non-Windows or restricted environments): $_" "DEBUG"
    }

    Write-Log "DEBUG: Font '$FontName' not found by file or registry check." "DEBUG"
    return $false
}

function Install-NerdFonts {
    param(
        [PSObject]$NerdFontsConfig # This is $Config.fonts_list.nerdfonts
    )

    $methods = @('chocolatey', 'scoop', 'github') # Order of preference
    $fontsToInstall = $NerdFontsConfig.fonts
    $success = $false # Tracks if any method succeeds for ANY font

    if (-not $fontsToInstall -or $fontsToInstall.Count -eq 0) {
        Write-Log "No Nerd Fonts listed in configuration." "INFO"
        return
    }

    foreach ($method in $methods) {
        Write-Log "Attempting Nerd Font installation for all listed fonts via: $method" "INFO"
        $allFontsInstalledThisMethod = $true # Assume all will be installed by this method initially

        try {
            switch ($method) {
                'chocolatey' {
                    if (Get-Command 'Test-ChocolateyInstalled' -ErrorAction SilentlyContinue) {
                        if (Test-ChocolateyInstalled) {
                            foreach ($fontName in $fontsToInstall) {
                                # Assuming font name in config (e.g., "FiraCode") needs suffix for choco (e.g., "firacode-nerd-font")
                                # This mapping might be complex. For now, a simple heuristic or direct use.
                                $chocoPackageName = "$($fontName.ToLower())-nerd-font" # Example heuristic
                                Write-Log "Attempting Chocolatey install for '$fontName' as '$chocoPackageName'" "INFO"
                                if (Test-FontInstalled -FontName $fontName) {
                                    Write-Log "Nerd Font '$fontName' already installed, skipping choco." "INFO"
                                    Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Nerd Font '$fontName' already installed (checked for choco)."
                                    continue # Next font
                                }
                                choco install $chocoPackageName -y --source=community
                                if ($LASTEXITCODE -eq 0) {
                                    Write-Log "Successfully installed '$chocoPackageName' via Chocolatey." "SUCCESS"
                                    Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Nerd Font '$fontName' (as '$chocoPackageName') installed via Chocolatey."
                                    $success = $true # At least one font installed by some method
                                } else {
                                    Write-Log "Failed to install '$chocoPackageName' via Chocolatey. Exit code: $LASTEXITCODE" "ERROR"
                                    Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Error" -DetailMessage "Failed to install Nerd Font '$fontName' (as '$chocoPackageName') via Chocolatey. Exit code: $LASTEXITCODE"
                                    $allFontsInstalledThisMethod = $false # This method didn't get all fonts
                                }
                            }
                        } else { Write-Log "Chocolatey is not installed, skipping method." "INFO"; $allFontsInstalledThisMethod = $false }
                    } else { Write-Log "Chocolatey provider functions (Test-ChocolateyInstalled) not found, skipping Chocolatey method." "WARNING"; $allFontsInstalledThisMethod = $false }
                }
                'scoop' {
                    if (Get-Command 'Test-ScoopInstalled' -ErrorAction SilentlyContinue) {
                        if (Test-ScoopInstalled) {
                            scoop bucket add nerd-fonts -ErrorAction SilentlyContinue # Ensure bucket exists
                            foreach ($fontName in $fontsToInstall) {
                                Write-Log "Attempting Scoop install for '$fontName'" "INFO"
                                if (Test-FontInstalled -FontName $fontName) {
                                    Write-Log "Nerd Font '$fontName' already installed, skipping scoop." "INFO"
                                    Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Nerd Font '$fontName' already installed (checked for scoop)."
                                    continue
                                }
                                scoop install $fontName
                                if ($LASTEXITCODE -eq 0) {
                                    Write-Log "Successfully installed '$fontName' via Scoop." "SUCCESS"
                                    Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Nerd Font '$fontName' installed via Scoop."
                                    $success = $true
                                } else {
                                    Write-Log "Failed to install '$fontName' via Scoop. Exit code: $LASTEXITCODE" "ERROR"
                                    Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Error" -DetailMessage "Failed to install Nerd Font '$fontName' via Scoop. Exit code: $LASTEXITCODE"
                                    $allFontsInstalledThisMethod = $false
                                }
                            }
                        } else { Write-Log "Scoop is not installed, skipping method." "INFO"; $allFontsInstalledThisMethod = $false }
                    } else { Write-Log "Scoop provider functions (Test-ScoopInstalled) not found, skipping Scoop method." "WARNING"; $allFontsInstalledThisMethod = $false }
                }
                'github' {
                    # This will now handle its own loop internally and check Test-FontInstalled
                    Install-NerdFontsFromGitHub -NerdFontsConfig $NerdFontsConfig
                    # Assume Install-NerdFontsFromGitHub sets $success appropriately if it installs anything
                    # For simplicity, we'll rely on its internal logging for success/failure per font.
                    # If it installs at least one font, we can consider this method a success.
                    # A more robust way would be for Install-NerdFontsFromGitHub to return a status.
                    $success = $true # If github method is reached, we assume it tries its best.
                                     # The function itself logs errors if all individual fonts fail.
                    $allFontsInstalledThisMethod = $true # Or track based on return from Install-NerdFontsFromGitHub
                }
            } # End Switch

            if ($allFontsInstalledThisMethod -and $success) { # If current method installed everything successfully
                 Write-Log "All listed Nerd Fonts successfully processed via $method." "SUCCESS"
                 break # Exit methods loop
            } elseif ($success) { # If some fonts were installed by this method, but not all
                 Write-Log "Some Nerd Fonts installed via $method. Continuing with remaining fonts or other methods if needed." "INFO"
            }

        } catch {
            Write-Log "Error during Nerd Font installation via $method: $_" "WARNING"
            $allFontsInstalledThisMethod = $false # Ensure we don't break prematurely
        }
    } # End foreach method

    if (-not $success) {
        Write-Log "Failed to install one or more Nerd Fonts after trying all methods." "ERROR"
    } else {
        Write-Log "Nerd Font installation process completed." "INFO"
    }
}

function Install-NerdFontsFromGitHub {
    param(
        [PSObject]$NerdFontsConfig # This is $Config.fonts_list.nerdfonts
    )

    $baseTmpDir = Join-Path $env:TEMP "nerdfonts_github"
    New-Item -ItemType Directory -Path $baseTmpDir -Force | Out-Null
    $anyFontInstalledByThisFunction = $false

    foreach ($fontName in $NerdFontsConfig.fonts) {
        if (Test-FontInstalled -FontName $fontName) {
            Write-Log "Nerd Font '$fontName' detected as already installed (checked before download)." "INFO"
            Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Nerd Font '$fontName' already installed (checked before GitHub download)."
            $anyFontInstalledByThisFunction = $true # Consider it "handled" by this function
            continue
        }

        $fontSpecificTmpDir = Join-Path $baseTmpDir $fontName
        New-Item -ItemType Directory -Path $fontSpecificTmpDir -Force | Out-Null
        Write-Log "Attempting to install Nerd Font '$fontName' from GitHub..." "INFO"

        try {
            $url = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$fontName.zip"
            # Some fonts might have different casing or names in the URL, e.g. FiraCode vs Fira Code
            # For now, using the name directly. This could be a point of failure for some fonts.
            $zipPath = Join-Path $fontSpecificTmpDir "$fontName.zip"
            $extractPath = Join-Path $fontSpecificTmpDir "extracted"

            Write-Log "Downloading $url to $zipPath..." "DEBUG"
            Invoke-WebRequest -Uri $url -OutFile $zipPath -UseBasicParsing -TimeoutSec 600 # Increased timeout for large files
            Write-Log "Download successful for $fontName.zip" "INFO"

            Write-Log "Extracting $zipPath to $extractPath..." "DEBUG"
            Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
            Write-Log "Extraction successful for $fontName.zip" "INFO"

            $fontFiles = Get-ChildItem $extractPath -Recurse -Include *.ttf, *.otf
            if ($fontFiles.Count -eq 0) {
                Write-Log "No .ttf or .otf font files found in the extracted archive for $fontName." "WARNING"
            }

            foreach ($fontFileItem in $fontFiles) {
                # Use the font file's base name for a more specific check
                $fontFileNameForTest = $fontFileItem.BaseName
                if (Test-FontInstalled -FontName $fontFileNameForTest) {
                    Write-Log "Font file '$($fontFileItem.Name)' (from $fontName package) already installed." "INFO"
                    Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Nerd Font file '$($fontFileItem.Name)' (from $fontName package) already installed."
                    $anyFontInstalledByThisFunction = $true
                    continue
                }

                try {
                    Copy-Item $fontFileItem.FullName -Destination "$env:SystemRoot\Fonts" -Force -ErrorAction Stop
                    Write-Log "Successfully installed font file: $($fontFileItem.Name) to $env:SystemRoot\Fonts" "SUCCESS"
                    Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Installed Nerd Font file '$($fontFileItem.Name)' (from $fontName package)."
                    $anyFontInstalledByThisFunction = $true
                } catch {
                    $errorMsg = "Failed to copy font file '$($fontFileItem.Name)' (from Nerd Font '$fontName') to system font directory: $($_.Exception.Message)"
                    Write-Log $errorMsg "ERROR"
                    Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Error" -DetailMessage $errorMsg
                }
            }
        }
        catch {
            $errorMsg = "Failed to download or install Nerd Font '$fontName' from GitHub: $($_.Exception.Message)"
            Write-Log $errorMsg "ERROR"
            Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Error" -DetailMessage $errorMsg
        }
        finally {
            if (Test-Path $fontSpecificTmpDir) {
                Write-Log "Cleaning up temporary directory: $fontSpecificTmpDir" "DEBUG"
                Remove-Item -Recurse -Force $fontSpecificTmpDir -ErrorAction SilentlyContinue
            }
        }
    } # End foreach fontName

    if ($anyFontInstalledByThisFunction) {
         Write-Log "GitHub Nerd Font installation process finished for all listed fonts." "INFO"
    } else {
         Write-Log "No new Nerd Fonts were installed from GitHub (either all failed or were already present)." "WARNING"
    }
    # Cleanup base temp dir if empty, otherwise it means some font failed catastrophically and its dir wasn't cleaned.
    if (Test-Path $baseTmpDir -and (Get-ChildItem $baseTmpDir).Count -eq 0) {
        Remove-Item -Recurse -Force $baseTmpDir -ErrorAction SilentlyContinue
    }
}

function Install-CustomFont {
    param(
        [PSObject]$CustomFontConfig # This is an entry from $Config.fonts_list.custom
    )

    $fontName = $CustomFontConfig.name
    $fontUrl = $CustomFontConfig.url
    # $fontEnabled = $CustomFontConfig.enabled # Already checked by caller

    Write-Log "Processing custom font: '$fontName' from URL: $fontUrl" "INFO"

    if (Test-FontInstalled -FontName $fontName) {
        Write-Log "Custom font '$fontName' already installed." "INFO"
        Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Custom font '$fontName' already installed."
        return
    }

    $tempDir = Join-Path $env:TEMP "custom_font_$($fontName -replace '[^a-zA-Z0-9]','_')" # Sanitize name for path
    $downloadedFilePath = ""
    $extractionDir = ""
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        $fileNameFromUrl = $fontUrl | Split-Path -Leaf
        $downloadedFilePath = Join-Path $tempDir $fileNameFromUrl

        Write-Log "Downloading custom font '$fontName' from $fontUrl to $downloadedFilePath" "DEBUG"
        Invoke-WebRequest -Uri $fontUrl -OutFile $downloadedFilePath -UseBasicParsing -TimeoutSec 300
        Write-Log "Custom font '$fontName' downloaded successfully." "INFO"

        # Check if it's a ZIP or a direct font file
        if ($downloadedFilePath.EndsWith(".zip", [System.StringComparison]::OrdinalIgnoreCase)) {
            $extractionDir = Join-Path $tempDir "extracted"
            New-Item -ItemType Directory -Path $extractionDir -Force | Out-Null
            Write-Log "Expanding archive $downloadedFilePath to $extractionDir" "DEBUG"
            Expand-Archive -Path $downloadedFilePath -DestinationPath $extractionDir -Force

            $fontFiles = Get-ChildItem $extractionDir -Recurse -Include *.ttf, *.otf
            if ($fontFiles.Count -eq 0) {
                Write-Log "No .ttf or .otf files found in extracted archive for custom font '$fontName'." "WARNING"
            }
            foreach ($fontFileItem in $fontFiles) {
                $fontFileNameForTest = $fontFileItem.BaseName # Use specific name for check
                if (Test-FontInstalled -FontName $fontFileNameForTest) {
                    Write-Log "Font file '$($fontFileItem.Name)' (from custom font '$fontName') already installed." "INFO"
                    Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Custom font file '$($fontFileItem.Name)' (from '$fontName') already installed."
                    continue
                }
                Copy-Item $fontFileItem.FullName -Destination "$env:SystemRoot\Fonts" -Force -ErrorAction Stop
                Write-Log "Successfully installed custom font file: $($fontFileItem.Name) to $env:SystemRoot\Fonts" "SUCCESS"
                Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Installed custom font file '$($fontFileItem.Name)' (for custom font '$fontName')."
            }
        }
        elseif ($downloadedFilePath.EndsWith(".ttf", [System.StringComparison]::OrdinalIgnoreCase) -or $downloadedFilePath.EndsWith(".otf", [System.StringComparison]::OrdinalIgnoreCase)) {
            $destFileName = $downloadedFilePath | Split-Path -Leaf
            $destinationPath = Join-Path "$env:SystemRoot\Fonts" $destFileName
            Copy-Item $downloadedFilePath -Destination $destinationPath -Force -ErrorAction Stop
            Write-Log "Successfully installed custom font file: $destFileName to $env:SystemRoot\Fonts" "SUCCESS"
            Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Success" -DetailMessage "Installed custom font file '$destFileName' (for custom font '$fontName')."
        }
        else {
            Write-Log "Downloaded file for custom font '$fontName' is not a .zip, .ttf, or .otf: $fileNameFromUrl. Cannot install." "WARNING"
            Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Warning" -DetailMessage "Custom font '$fontName': downloaded file '$fileNameFromUrl' is not a supported font type or ZIP."
        }
    }
    catch {
        $errorMsg = "Failed to install custom font '$fontName': $($_.Exception.Message)"
        Write-Log $errorMsg "ERROR"
        Update-PhaseOutcome -PhaseName "Fonts" -OutcomeType "Error" -DetailMessage $errorMsg
    }
    finally {
        if (Test-Path $tempDir) {
            Write-Log "Cleaning up temporary directory for custom font '$fontName': $tempDir" "DEBUG"
            Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function *
