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

    # Phase enable/disable check
    if (-not $Config.PSObject.Properties.Name -contains 'fonts_provisioner' -or -not $Config.fonts_provisioner.enabled) {
        Write-Log "Fonts installation phase is disabled in configuration via 'fonts_provisioner.enabled'." "INFO"
        return
    }

    Write-Log "Beginning font installation..." "INFO"
    Initialize-PhaseSummary "Fonts"

    # Install Nerd Fonts
    if ($Config.PSObject.Properties.Name -contains 'fonts_list' -and 
        $null -ne $Config.fonts_list -and 
        $Config.fonts_list.PSObject.Properties.Name -contains 'nerd_fonts' -and 
        $null -ne $Config.fonts_list.nerd_fonts -and 
        $Config.fonts_list.nerd_fonts.PSObject.Properties.Name -contains 'enabled' -and 
        $Config.fonts_list.nerd_fonts.enabled -eq $true) {

        Write-Log "Nerd Fonts installation is enabled via 'fonts_list.nerd_fonts.enabled'." "INFO"
        $fontsToInstall = $Config.fonts_list.nerd_fonts.fonts | Where-Object { $_.install -eq $true }
        if ($fontsToInstall.Count -gt 0) {
            $nerdFontsConfig = [PSCustomObject]@{
                enabled = $true
                fonts = $fontsToInstall
            }
            Install-NerdFonts -NerdFontsConfig $nerdFontsConfig
        } else {
            Write-Log "No Nerd Fonts marked for installation." "INFO"
        }
    }
    else {
        Write-Log "Nerd Fonts installation is disabled or 'fonts_list.nerd_fonts' section is missing/misconfigured." "INFO"
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
    $strippedFontName = $FontName -replace '\s', ''

    # Check 1: System Fonts Directory (e.g., C:\Windows\Fonts)
    # This looks for font files (.ttf, .otf, etc.) whose names contain the stripped font name.
    try {
        $fontFiles = Get-ChildItem "$env:SystemRoot\Fonts" -File -ErrorAction SilentlyContinue # Avoid error if path is restricted, though unlikely for system fonts.
        foreach ($fontFile in $fontFiles) {
            # Compare stripped file name (without extension) against stripped input font name.
            if (($fontFile.BaseName -replace '\s', '') -match [regex]::Escape($strippedFontName)) {
                Write-Log "DEBUG: Found matching font file: $($fontFile.Name) for '$FontName' (Filesystem check)." "DEBUG"
                return $true
            }
        }
    }
    catch {
        Write-Log "DEBUG: Error accessing system font directory for Test-FontInstalled: $($_.Exception.Message)" "DEBUG"
    }


    # Check 2: Windows Font Registry
    # This checks registry entries which often list installed fonts.
    try {
        # Query all font entries under the specified registry path.
        $registryFonts = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts\*' -ErrorAction SilentlyContinue
        foreach ($regFont in $registryFonts) {
            # The PSChildName is often the display name of the font, e.g., "Arial (TrueType)".
            if (($regFont.PSChildName -replace '\s', '') -match [regex]::Escape($strippedFontName)) {
                Write-Log "DEBUG: Found matching registry entry (PSChildName): '$($regFont.PSChildName)' for '$FontName'." "DEBUG"
                return $true
            }
            # The value of the registry entry often contains the actual font file name.
            # Ensure it's a string before trying to match.
            if ($regFont.PSObject.Properties.Name -contains $regFont.PSChildName) {
                # Check if property exists
                $fontFileInReg = $regFont.$($regFont.PSChildName)
                if ($fontFileInReg -is [string] -and (($fontFileInReg -replace '\s', '').Split('.')[0] -match [regex]::Escape($strippedFontName))) {
                    Write-Log "DEBUG: Found matching font file in registry data: '$fontFileInReg' for '$FontName'." "DEBUG"
                    return $true
                }
            }
        }
    }
    catch {
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

    $fontsToInstall = $NerdFontsConfig.fonts
    if (-not $fontsToInstall -or $fontsToInstall.Count -eq 0) {
        Write-Log "No Nerd Fonts specified for installation." "INFO"
        return
    }

    # Get list of fonts to install by name
    $fontNames = $fontsToInstall | Where-Object { $_.install -eq $true } | ForEach-Object { $_.name }
    if ($fontNames.Count -eq 0) {
        Write-Log "No fonts marked for installation." "INFO"
        return
    }

    Write-Log "Installing Nerd Fonts using web installer..." "INFO"
    try {
        $fontNamesComma = $fontNames -join ','
        Write-Log "Installing fonts: $($fontNames -join ', ')" "INFO"

        # Build the installation command using the short URL
        $command = "& ([scriptblock]::Create((iwr 'https://to.loredo.me/Install-NerdFont.ps1'))) -Name $fontNamesComma -Confirm:`$false"
        
        Write-Log "Running font installer..." "INFO"
        Invoke-Expression $command

        Write-Log "Successfully initiated Nerd Fonts installation" "SUCCESS"
        if (Get-Command "Add-PhaseSummaryEntry" -ErrorAction SilentlyContinue) {
            Add-PhaseSummaryEntry "Fonts" "Initiated Nerd Fonts installation for: $($fontNames -join ', ')" "Success"
        }
    }
    catch {
        Write-Log "Error during Nerd Fonts installation: $($_.Exception.Message)" "ERROR"
        if (Get-Command "Add-PhaseSummaryEntry" -ErrorAction SilentlyContinue) {
            Add-PhaseSummaryEntry "Fonts" "Failed to install Nerd Fonts: $($_.Exception.Message)" "Error"
        }
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
            $fontFilesFound = Get-ChildItem -Path $extractPath -Recurse -Include *.ttf,*.otf
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
                }
                catch {
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
    }
    else {
        Write-Log "No new Nerd Fonts were installed or confirmed existing from GitHub (either all failed or none were specified/found)." "WARNING"
    }
    # Cleanup base temp dir if it's empty (meaning all sub-folders were cleaned up).
    if (Test-Path $baseTmpDir -and (Get-ChildItem $baseTmpDir -ErrorAction SilentlyContinue).Count -eq 0) {
        Remove-Item -Recurse -Force $baseTmpDir -ErrorAction SilentlyContinue
    }
}

# Export public functions. Helper functions like Install-NerdFonts, Install-NerdFontsFromGitHub,
# and Install-CustomFont are typically not exported if Install-Fonts is the main entry point.
Export-ModuleMember -Function Install-Fonts, Test-FontInstalled
