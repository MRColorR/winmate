<#!
.SYNOPSIS
    Checks GitHub for the latest version against config version
#>

function Check-LatestVersion {
    param(
        [PSObject]$Config
    )

    # Extract user and repo name from the full repo URL
    if ($Config.metadata.repo -match "github\.com/([^/]+)/([^/]+)") {
        $user = $matches[1]
        $repoName = $matches[2]
        $Repo = "$user/$repoName"
        Write-Log "Checking for updates for repository: $Repo" "INFO"
    } else {
        throw "Invalid repo URL format in config."
    }

    if ($null -ne $Config.metadata.version) { 
        $currentVersion = $Config.metadata.version 
    } else { 
        $currentVersion = "v0.0.0" 
    }
    $apiUrl = "https://api.github.com/repos/$Repo/releases/latest"

    try {
        $response = Invoke-RestMethod -Uri $apiUrl -UseBasicParsing
        $latestTag = $response.tag_name

        if ($latestTag -ne $currentVersion) {
            Write-Log "New version available: $latestTag. You are on $currentVersion. Visit https://github.com/$Repo/releases" "INFO"
        } else {
            Write-Log "You are using the latest version: $currentVersion" "SUCCESS"
        }
    } catch {
        Write-Log "Could not check for updates: $_" "WARNING"
    }
}

Export-ModuleMember -Function *
