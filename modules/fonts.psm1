<#!
.SYNOPSIS
    Handles installation of Nerd Fonts and custom fonts
#>

function Install-Fonts {
    param(
        [hashtable]$Config
    )

    if (-not $Config.steps.fonts.enabled) {
        Write-Log "Fonts step is disabled in configuration." "INFO"
        return
    }

    Write-Log "Beginning font installation..." "INFO"

    if ($Config.fonts.nerdfonts.enabled) {
        Install-NerdFonts -FontConfig $Config.fonts.nerdfonts
    }

    if ($Config.fonts.custom) {
        foreach ($font in $Config.fonts.custom) {
            if ($font.enabled -eq $true) {
                Install-CustomFont -FontConfig $font
            }
        }
    }

    Write-Log "Font installation complete." "SUCCESS"
}

function Install-NerdFonts {
    param(
        [hashtable]$FontConfig
    )

    $methods = @('chocolatey', 'scoop', 'github')
    $fonts = $FontConfig.fonts
    $success = $false

    foreach ($method in $methods) {
        Write-Log "Trying Nerd Font install via: ${method}" "INFO"
        try {
            switch ($method) {
                'chocolatey' {
                    if (Test-PackageProvider 'chocolatey') {
                        foreach ($f in $fonts) { choco install $f -y }
                        $success = $true
                        break
                    }
                }
                'scoop' {
                    if (Test-PackageProvider 'scoop') {
                        scoop bucket add nerd-fonts -ErrorAction SilentlyContinue
                        foreach ($f in $fonts) { scoop install $f }
                        $success = $true
                        break
                    }
                }
                'github' {
                    Install-NerdFontsFromGitHub -Fonts $fonts
                    $success = $true
                    break
                }
            }
        } catch {
            Write-Log "Failed using method: ${method} — $_" "WARNING"
        }
    }

    if (-not $success) {
        Write-Log "All Nerd Font install methods failed." "ERROR"
    }
}

function Install-NerdFontsFromGitHub {
    param(
        [array]$Fonts
    )

    $tmp = Join-Path $env:TEMP "nerdfonts"
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null

    foreach ($font in $Fonts) {
        try {
            $url = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$font.zip"
            $zip = "$tmp\$font.zip"
            $extract = "$tmp\$font"

            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
            Expand-Archive -Path $zip -DestinationPath $extract -Force

            Get-ChildItem $extract -Recurse -Include *.ttf,*.otf | ForEach-Object {
                Copy-Item $_.FullName -Destination "$env:SystemRoot\Fonts" -Force
            }

            Write-Log "Installed ${font} via GitHub" "SUCCESS"
        } catch {
            Write-Log "Failed GitHub install: ${font} — $_" "ERROR"
        }
    }

    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

function Install-CustomFont {
    param(
        [hashtable]$FontConfig
    )

    $path = $FontConfig.path
    $url = $FontConfig.url

    try {
        if ($url) {
            $file = Join-Path $env:TEMP "$($FontConfig.name).zip"
            Invoke-WebRequest $url -OutFile $file -UseBasicParsing
            Expand-Archive $file -DestinationPath $env:TEMP -Force
            $fonts = Get-ChildItem $env:TEMP -Include *.ttf,*.otf -Recurse
            foreach ($font in $fonts) {
                Copy-Item $font.FullName -Destination "$env:SystemRoot\Fonts" -Force
            }
            Remove-Item $file -Force -ErrorAction SilentlyContinue
            Write-Log "Custom font installed: $($FontConfig.name)" "SUCCESS"
        } elseif ($path) {
            Copy-Item $path -Destination "$env:SystemRoot\Fonts" -Force
            Write-Log "Local custom font installed: $($FontConfig.name)" "SUCCESS"
        }
    } catch {
        Write-Log "Failed custom font install: $($FontConfig.name) - Error: $_" "ERROR"
    }
}

Export-ModuleMember -Function *
