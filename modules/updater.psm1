<#!
<#
.SYNOPSIS
    Provides functionality to check for script updates against a GitHub repository.
.DESCRIPTION
    This module contains a function to compare the script's current version (defined in the
    configuration file) with the latest release tag on a specified GitHub repository.
    It handles GitHub API interaction and version comparison.
#>

<#
.SYNOPSIS
    Checks for a newer version of the script or configuration on GitHub.
.DESCRIPTION
    This function compares the local script version, as specified in the 'config.json' file
    (under 'metadata.version'), with the tag name of the latest release found on the GitHub
    repository (specified in 'config.json' under 'metadata.repo').
    It logs an informational message if a newer version is available, or a success message
    if the current version is up-to-date or newer. If the check cannot be completed
    (e.g., due to network issues, API errors, or invalid configuration), it logs a warning.
    The function attempts to parse versions using [System.Version] for accurate comparison,
    falling back to string comparison if that fails.
.PARAMETER Config
    The main configuration object for the script. This object must contain a 'metadata' property,
    which in turn must have:
    - 'repo' (string): The GitHub repository identifier in 'owner/repository' format or a full GitHub URL.
    - 'version' (string): The current version string of the local script/configuration (e.g., "1.0.0", "v1.0.1").
    This parameter is mandatory.
.PARAMETER GitHubToken
    Optional. A GitHub Personal Access Token (PAT). If provided, this token will be used for
    authenticated requests to the GitHub API, which helps in avoiding rate limits imposed on
    anonymous requests. If not provided, requests are made anonymously.
.EXAMPLE
    PS C:\> $myConfig = Get-Configuration -Path "./config/config.json"
    PS C:\> Test-ScriptUpdateAvailable -Config $myConfig -GitHubToken $myGitHubPat
    This command checks if there's a newer version of the script based on the 'repo' and 'version'
    fields in $myConfig, using $myGitHubPat for authentication with GitHub API.
    It logs the result (e.g., "New version X available" or "You are using the latest version").
.EXAMPLE
    PS C:\> Test-ScriptUpdateAvailable -Config $someConfig
    Performs the update check without a GitHub token, relying on anonymous API access.
.NOTES
    Uses the GitHub API (api.github.com/repos/{owner}/{repo}/releases/latest) to fetch information
    about the latest release.
    Handles errors during the API call gracefully by logging a warning and returning $false.
    Version comparison prioritizes using [System.Version] for semantic versioning logic (e.g., 1.10.0 > 1.9.0).
    If version strings are not compliant with [System.Version] (e.g., "1.0-alpha"), it falls back to direct string inequality.
    The function returns $true if an update is considered available (latest tag is different and potentially newer),
    and $false if no update is available, if the local version is newer, or if the check fails.
#>
function Test-ScriptUpdateAvailable {
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$Config,
        [string]$GitHubToken = $null
    )

    # Validate essential configuration parts needed for the update check.
    if (-not $Config.metadata -or -not $Config.metadata.repo -or -not $Config.metadata.version) {
        Write-Log "Updater: 'metadata.repo' or 'metadata.version' is missing in the configuration. Cannot check for updates." "WARNING"
        return $false # Cannot proceed without repository and version information.
    }

    # Extract repository owner and name from the provided 'repo' string.
    # It supports both full GitHub URLs and 'owner/repo' format.
    $repoPath = $Config.metadata.repo
    $Repo = $null
    if ($repoPath -match "github\.com/([^/]+)/([^/]+)") {
        # Matches https://github.com/owner/repo or github.com/owner/repo
        $owner = $matches[1]
        $repositoryName = $matches[2].Replace(".git", "") # Remove .git suffix if present
        $Repo = "$owner/$repositoryName"
    }
    elseif ($repoPath -match "^([^/]+)/([^/]+)$") {
        # Matches 'owner/repo' format directly
        $Repo = $repoPath
    }
    else {
        Write-Log "Updater: Invalid 'metadata.repo' URL or path format in config: '$repoPath'. Expected 'github.com/owner/repo' or 'owner/repo'." "ERROR"
        return $false # Cannot proceed with an invalid repository path.
    }

    $currentVersionString = $Config.metadata.version
    Write-Log "Updater: Current local version is '$currentVersionString'. Checking for updates for repository '$Repo'." "INFO"

    # Construct the GitHub API URL for fetching the latest release.
    $apiUrl = "https://api.github.com/repos/$Repo/releases/latest"
    $headers = @{} # Initialize empty hashtable for request headers.
    if (-not [string]::IsNullOrEmpty($GitHubToken)) {
        $headers["Authorization"] = "token $GitHubToken" # Add Authorization header if token is provided.
        Write-Log "Updater: Using GitHub token for API request to '$Repo'." "DEBUG"
    }
    else {
        Write-Log "Updater: No GitHub token provided for '$Repo'. Making anonymous API request (standard rate limits may apply)." "DEBUG"
    }

    try {
        # Fetch latest release information from GitHub API.
        # -UseBasicParsing is generally recommended for non-interactive scripts.
        # -ErrorAction Stop ensures that API errors are caught by the catch block.
        # -TimeoutSec helps prevent indefinite hanging on network issues.
        $response = Invoke-RestMethod -Uri $apiUrl -Headers $headers -UseBasicParsing -ErrorAction Stop -TimeoutSec 20
        $latestTagString = $response.tag_name # The tag name, typically used for versioning (e.g., "v1.2.0").

        if ([string]::IsNullOrEmpty($latestTagString)) {
            Write-Log "Updater: Latest release tag information is empty or not found for repository '$Repo'. Possible no releases or API issue." "WARNING"
            return $false # Cannot determine update if tag is missing.
        }

        # Normalize version strings by removing a leading 'v' (common in git tags) for [System.Version] compatibility.
        $currentVersionNormalized = $currentVersionString -replace '^v', ''
        $latestTagNormalized = $latestTagString -replace '^v', ''

        # Attempt to compare versions using the robust [System.Version] type.
        try {
            $currentSysVersion = [System.Version]$currentVersionNormalized
            $latestSysVersion = [System.Version]$latestTagNormalized

            if ($latestSysVersion -gt $currentSysVersion) {
                Write-Log "Updater: New version '$latestTagString' is available for '$Repo'. You are currently on '$currentVersionString'. Please visit https://github.com/$Repo/releases for details." "INFO"
                return $true # Indicates an update is available.
            }
            else {
                # Current version is same as latest, or newer (e.g., a pre-release or local build).
                Write-Log "Updater: You are using the latest version ('$currentVersionString') or a newer unreleased version for '$Repo'." "SUCCESS"
                return $false # No update needed, or local is ahead.
            }
        }
        catch {
            # Fallback to simple string comparison if [System.Version] conversion fails.
            # This can happen with non-standard versioning schemes (e.g., "1.0-custom", "latest").
            Write-Log "Updater: Could not parse version strings ('$currentVersionNormalized' or '$latestTagNormalized') using System.Version. Falling back to direct string comparison. Error details: $($_.Exception.Message)" "DEBUG"
            if ($latestTagString -ne $currentVersionString) {
                Write-Log "Updater: Latest release tag '$latestTagString' is different from current version '$currentVersionString' for '$Repo'. An update might be available. Please visit https://github.com/$Repo/releases for details." "INFO"
                return $true # Indicates a difference, potentially an update.
            }
            else {
                Write-Log "Updater: You are using the latest version '$currentVersionString' (based on string comparison) for '$Repo'." "SUCCESS"
                return $false # Versions are identical by string comparison.
            }
        }
    }
    catch {
        # Catch errors from Invoke-RestMethod (e.g., network issues, 404 Not Found, API rate limits if severe).
        Write-Log "Updater: Could not check for updates for repository '$Repo'. Error fetching release data: $($_.Exception.Message)" "WARNING"
        return $false # Failed to perform the update check.
    }
}

Export-ModuleMember -Function Test-ScriptUpdateAvailable
