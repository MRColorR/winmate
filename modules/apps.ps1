<#!
.SYNOPSIS
    Handles application installations via winget, choco, scoop, or manual methods
#>

function Install-Applications {
    param(
        [hashtable]$Config
    )

    $apps = $Config.apps
    $grouped = @{}

    foreach ($app in $apps.GetEnumerator()) {
        $name = $app.Key
        $data = $app.Value

        if ($data.install -eq $true) {
            $provider = $data.provider
            if (-not $grouped.ContainsKey($provider)) {
                $grouped[$provider] = @()
            }
            $grouped[$provider] += @{ Name = $name; Config = $data }
        }
    }

    foreach ($provider in $grouped.Keys) {
        if (-not (Test-PackageProvider $provider)) {
            Write-Log "Provider '$provider' not found. Installing..." "INFO"
            try {
                Install-PackageProvider $provider
            } catch {
                Write-Log "Cannot proceed with $provider apps." "ERROR"
                continue
            }
        }

        foreach ($app in $grouped[$provider]) {
            Install-SingleApp -AppName $app.Name -AppConfig $app.Config -Provider $provider
        }
    }

    Write-Log "Application installation complete." "SUCCESS"
}

function Install-SingleApp {
    param(
        [string]$AppName,
        [hashtable]$AppConfig,
        [string]$Provider
    )

    try {
        switch ($Provider.ToLower()) {
            'winget' {
                if ($null -ne $AppConfig.package_id) { $id = $AppConfig.package_id } else { $id = $AppName }
                winget install --id $id --silent --accept-package-agreements --accept-source-agreements
            }
            'chocolatey' {
                if ($null -ne $AppConfig.package_name) { $id = $AppConfig.package_name } else { $id = $AppName }
                choco install $id -y
            }
            'scoop' {
                if ($AppConfig.bucket) {
                    scoop bucket add $AppConfig.bucket -ErrorAction SilentlyContinue
                }
                if ($null -ne $AppConfig.package_name) { $id = $AppConfig.package_name } else { $id = $AppName }
                scoop install $id
            }
            'manual' {
                Install-ManualApp -AppName $AppName -AppConfig $AppConfig
            }
            default {
                Write-Log "Unknown provider: $Provider" "ERROR"
            }
        }
        Write-Log "Installed $AppName via $Provider" "SUCCESS"
    } catch {
        Write-Log "Failed installing ${AppName} (${Provider}): $_" "ERROR"
    }
}

function Install-ManualApp {
    param(
        [string]$AppName,
        [hashtable]$AppConfig
    )

    $url = $AppConfig.download_url
    if ($null -ne $AppConfig.install_args) { $args = $AppConfig.install_args } else { $args = "/S" }
    $file = Join-Path $env:TEMP (Split-Path $url -Leaf)

    try {
        Invoke-WebRequest $url -OutFile $file -UseBasicParsing
        $ext = [IO.Path]::GetExtension($file)

        switch ($ext) {
            '.exe' { Start-Process -FilePath $file -ArgumentList $args -Wait }
            '.msi' { Start-Process msiexec.exe -ArgumentList "/i `"$file`" /qn" -Wait }
            default { Write-Log "Unknown installer type: $ext for $AppName" "WARNING" }
        }

        Write-Log "Manual app installed: $AppName" "SUCCESS"
        Remove-Item $file -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Log "Manual install failed for ${AppName}: $_" "ERROR"
    }
}
