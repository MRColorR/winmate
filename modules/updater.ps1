<#!
.SYNOPSIS
    Checks GitHub for the latest version against config version
#>

function Check-LatestVersion {
    param(
        [string]$Repo = "YourUser/YourRepo",
        [hashtable]$Config
    )

    $currentVersion = $Config.version ?? "v0.0.0"
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
