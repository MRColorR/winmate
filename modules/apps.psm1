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
    foreach ($provider in $grouped.Keys) {
        if (-not (Test-PackageProvider $provider)) {
            Write-Log "Provider '$provider' not found. Installing..." "INFO"
            try {
                Install-PackageProvider $provider
            }
            catch {
                Write-Log "Cannot proceed with $provider apps." "ERROR"
                continue
            }
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
            $result = winget list --id $id 2>$null | Select-String $id
            if ($null -ne $result) { $isInstalled = $true }
        }
        'chocolatey' {
            $id = if ($AppConfig.package_name) { $AppConfig.package_name } else { $AppName }
            $result = choco list --local-only $id 2>$null | Select-String $id
            if ($null -ne $result) { $isInstalled = $true }
        }
        'scoop' {
            $id = if ($AppConfig.package_name) { $AppConfig.package_name } else { $AppName }
            $result = scoop list 2>$null | Select-String $id
            if ($null -ne $result) { $isInstalled = $true }
        }
        'manual' {
            if ($AppConfig.install_location) {
                $installPath = $AppConfig.install_location
                if (Test-Path $installPath) {
                    Write-Log "Manual app '$AppName' found at '$installPath'" "INFO"
                    $isInstalled = $true
                }
            }
        }
        default {
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
            }
            'chocolatey' {
                if ($null -ne $AppConfig.package_name) { $id = $AppConfig.package_name } else { $id = $AppName }
                Write-Log $install_mesg "INFO"
                choco install $id -y
            }
            'scoop' {
                if ($AppConfig.bucket) {
                    scoop bucket add $AppConfig.bucket -ErrorAction SilentlyContinue
                }
                if ($null -ne $AppConfig.package_name) { $id = $AppConfig.package_name } else { $id = $AppName }
                Write-Log $install_mesg "INFO"
                scoop install $id
            }
            'manual' {
                if ($AppConfig.install_location) {
                    $install_mesg += " to '$($AppConfig.install_location)'"
                }
                Write-Log $install_mesg "INFO"
                Install-ManualApp -AppName $AppName -AppConfig $AppConfig
            }
            default {
                Write-Log "Unknown provider: $Provider" "ERROR"
            }
        }
        Write-Log "Installed $AppName via $Provider" "SUCCESS"
    }
    catch {
        Write-Log "Failed installing ${AppName} (${Provider}): $_" "ERROR"
    }
}

function Install-ManualApp {
    param(
        [string]$AppName,
        [PSObject]$AppConfig
    )

    $url = $AppConfig.download_url
    if ($null -ne $AppConfig.install_args) { $installArgs = $AppConfig.install_args } else { $installArgs = "/S" }
    $file = Join-Path $env:TEMP (Split-Path $url -Leaf)

    try {
        Invoke-WebRequest $url -OutFile $file -UseBasicParsing
        $ext = [IO.Path]::GetExtension($file)

        switch ($ext) {
            '.exe' { Start-Process -FilePath $file -ArgumentList $installArgs -Wait }
            '.msi' { Start-Process msiexec.exe -ArgumentList "/i `"$file`" /qn" -Wait }
            default { Write-Log "Unknown installer type: $ext for $AppName" "WARNING" }
        }

        Write-Log "Manual app installed: $AppName" "SUCCESS"
        Remove-Item $file -Force -ErrorAction SilentlyContinue
    }
    catch {
        Write-Log "Manual install failed for ${AppName}: $_" "ERROR"
    }
}

Export-ModuleMember -Function *
