# Windows Post-Installation Automation Script

A comprehensive PowerShell-based automation solution for Windows post-installation tasks, designed with software engineering best practices including modular architecture, comprehensive logging, error handling, and JSON-driven configuration.

## 🚀 Features

### Core Functionality
- **Windows Debloating**: Remove unwanted pre-installed applications and bloatware
- **Font Management**: Automated installation of Nerd Fonts and custom fonts
- **Application Installation**: Multi-provider app installation (WinGet, Chocolatey, Scoop, MS Store)
- **Comprehensive Logging**: Structured logging with multiple levels and detailed reporting

### Technical Highlights
- **Modular Architecture**: Well-organized functions with single responsibility
- **Error Resilience**: Failures don't stop the entire process
- **JSON Configuration**: Flexible, human-readable configuration management
- **Multi-Provider Support**: Automatic package manager installation when needed
- **Extensive Documentation**: Comprehensive inline documentation and comments

## 📋 Prerequisites

- Windows 10/11
- PowerShell 5.1 or higher
- Administrator privileges
- Internet connection for downloads

## 🛠️ Installation & Usage

### Quick Start

1. **Download the scripts**:
   ```powershell
   # Download to your desired directory
   cd C:\PostInstall
   ```

2. **Customize the configuration**:
   - Edit `config.json` to match your preferences
   - Enable/disable sections as needed
   - Add or remove applications

3. **Run the script**:
   ```powershell
   # Run with default config.json
   powershell -ExecutionPolicy Bypass -File .\post_install.ps1
   
   # Run with custom configuration
   powershell -ExecutionPolicy Bypass -File .\post_install.ps1 -ConfigPath "custom-config.json" -LogPath "my-install.log"
   ```

### Advanced Usage

```powershell
# Run with specific parameters
.\post_install.ps1 -ConfigPath "config\enterprise.json" -LogPath "logs\$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

# Check execution policy first
Get-ExecutionPolicy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Run as administrator (required)
Start-Process PowerShell -Verb RunAs -ArgumentList "-File .\post_install.ps1"
```

## 📖 Configuration Guide

### Configuration File Structure

The `config.json` file is organized into main sections:

```json
{
  "apps_debloater": { "enabled": true },
  "fonts_provisioner": { "enabled": true },
  "fonts_list": {
    "nerdfonts": {
      "enabled": true,
      "fonts": ["FiraCode", "JetBrainsMono", "CascadiaCode"]
    },
    "custom": [
      {
        "name": "Inter Font",
        "url": "https://github.com/rsms/inter/releases/download/v3.19/Inter-3.19.zip",
        "enabled": true
      }
    ]
  },
  "apps_provisioner": { "enabled": true },
  "apps_list": { /* all app definitions here */ },
  "metadata": { /* ... */ }
}
```

### Section Details

#### 1. Apps Debloater Section
Controls removal of unwanted Windows applications:

```json
"apps_debloater": {
  "enabled": true,
  "description": "Controls whether to remove unwanted Windows applications"
}
```

#### 2. Fonts List (Top-Level)
Manages font installation including Nerd Fonts and custom fonts:

```json
"fonts_list": {
  "nerdfonts": {
    "enabled": true,
    "fonts": ["FiraCode", "JetBrainsMono", "CascadiaCode"]
  },
  "custom": [
    {
      "name": "Inter Font",
      "url": "https://github.com/rsms/inter/releases/download/v3.19/Inter-3.19.zip",
      "enabled": true
    }
  ]
}
```

#### 3. Fonts Provisioner Section
Controls whether the font installation phase runs:

```json
"fonts_provisioner": {
  "enabled": true,
  "description": "Handles installation of Nerd Fonts and custom fonts"
}
```

#### 4. Apps Provisioner Section
Controls application installation and removal:

```json
"apps_provisioner": {
  "enabled": true,
  "description": "Manages installation or removal of specified applications"
}
```

#### 5. Apps List (Top-Level)
All applications to be installed or removed are defined here:

```json
"apps_list": {
  "YourApp": {
    "remove": false,
    "install": true,
    "provider": "winget",
    "package_id": "Publisher.YourApp",
    "description": "Your application description"
  },
  "UnwantedApp": {
    "remove": true,
    "install": false,
    "provider": "winget",
    "package_id": "Publisher.UnwantedApp",
    "description": "Unwanted application description"
  }
}
```

**Supported Providers**:
- `winget`: Windows Package Manager
- `chocolatey`: Chocolatey package manager
- `scoop`: Scoop package manager
- `msstore`: Microsoft Store
- `manual`: Direct download and installation

#### 6. Metadata Section
General information about the configuration and compatibility.

```json
"metadata": {
  "repo": "https://github.com/MRColorR/winmate",
  "version": "1.0.0",
  "last_updated": "2025-06-05",
  "author": "Windows Post-Install Automation by MRColorR",
  "description": "Configuration file for automated Windows post-installation setup",
  "compatibility": {
    "windows_versions": ["10", "11"],
    "powershell_version": "5.1+"
  }
}
```

## 🔧 Application Management

### Adding New Applications

To add a new application for installation:

```json
"YourApp": {
  "remove": false,
  "install": true,
  "provider": "winget",
  "package_id": "Publisher.YourApp",
  "description": "Your application description"
}
```

### Removing Applications

To mark an application for removal:

```json
"UnwantedApp": {
  "remove": true,
  "install": false,
  "provider": "winget",
  "package_id": "Publisher.UnwantedApp",
  "description": "Unwanted application description"
}
```

### Provider-Specific Configuration

**WinGet**:
```json
"provider": "winget",
"package_id": "Microsoft.VisualStudioCode"
```

**Chocolatey**:
```json
"provider": "chocolatey",
"package_name": "googlechrome"
```

**Scoop**:
```json
"provider": "scoop",
"package_name": "git",
"bucket": "main"
```

**Manual Installation**:
```json
"provider": "manual",
"download_url": "https://example.com/installer.exe",
"install_args": "/S /v/qn"
```

## 📊 Logging System

### Log Levels
- `INFO`: General information
- `SUCCESS`: Successful operations
- `WARNING`: Non-critical issues
- `ERROR`: Critical errors

### Log File Location
- Default: `postinstall.log` in script directory
- Custom: Specify with `-LogPath` parameter

### Log File Format
```
[2025-06-05 14:30:15] [INFO] Starting Windows Post-Installation Automation
[2025-06-05 14:30:16] [SUCCESS] Configuration loaded successfully
[2025-06-05 14:30:17] [WARNING] Application not found: ExampleApp
[2025-06-05 14:30:18] [ERROR] Failed to install application: Critical error
```

## 🛡️ Error Handling

The script implements comprehensive error handling:

- **Non-blocking errors**: Individual failures don't stop the entire process
- **Detailed logging**: All errors are logged with context
- **Graceful degradation**: Alternative methods attempted when primary fails
- **Summary reporting**: Final summary shows success/warning/error counts

## 🔒 Security Considerations

### Administrator Privileges
The script requires administrator privileges for:
- Installing/removing applications
- Modifying system registry settings
- Installing fonts system-wide
- Changing system configurations

### Execution Policy
You may need to adjust PowerShell execution policy:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Package Manager Security
- WinGet: Uses Microsoft's trusted repository
- Chocolatey: Community-driven, verify packages before use
- Scoop: Open-source, generally safe
- Manual: Verify download URLs and checksums

## 🛡️ GitHub API Rate Limiting & Token Usage

Some features, such as fetching the default install location from the WinGet manifest repository, may require multiple requests to the GitHub API. GitHub imposes rate limits on unauthenticated requests. If you encounter warnings about rate limiting, you can provide a GitHub Personal Access Token (PAT) to increase your API quota.

**How the script uses a GitHub token:**
- The script will use a token if provided as a `-GitHubToken` parameter or if a `token.json` file is present in the `config/` directory alongside `config.json`.
- If both are provided, the parameter takes precedence.
- If no token is provided, the script will still work, but may hit GitHub API rate limits if run repeatedly or in automation.

**How to use a GitHub token with this script:**
- Generate a token at [GitHub Developer Settings](https://github.com/settings/tokens) (no special scopes required for public repo access).
- Pass the token as a parameter to the script, or create a `config/token.json` file with the following content:

```json
{
  "GitHubToken": "ghp_YourPersonalAccessTokenHere"
}
```

- The script will automatically use the token to mitigate rate limiting when fetching manifests.

**Example usage:**
```powershell
# With token as parameter
$token = "ghp_YourPersonalAccessTokenHere"
.\post_install.ps1 -GitHubToken $token

# Or with config/token.json present in the config directory
.\post_install.ps1
```

- If you do not provide a token and hit the rate limit, the script will log a warning and automatically retry after a delay.
- For most users, a token is not required unless running the script repeatedly or in automation with lots of apps to install.

---

## 🚀 Execution Phases

The script executes in five main phases:

1. **Phase 1: Windows Debloat**
   - Removes unwanted UWP applications
   - Cleans up provisioned packages
   - Uses multiple removal methods

2. **Phase 2: Font Installation**
   - Installs Nerd Fonts via multiple methods
   - Installs custom fonts from URLs
   - Registers fonts in system registry

3. **Phase 3: Application Installation**
   - Groups applications by provider
   - Installs package managers as needed
   - Handles different installation methods

4. **Phase 4: System Configuration**
   - Applies privacy settings
   - Optimizes performance settings
   - Configures UI preferences

5. **Phase 5: Cleanup**
   - Removes temporary files
   - Refreshes environment variables
   - Generates final summary

## 📈 Performance Optimization

### Batch Operations
- Applications grouped by provider for efficient installation
- Parallel operations where possible
- Minimal system restarts required

### Resource Management
- Temporary files cleaned automatically
- Memory usage optimized
- Network requests minimized

## 🔍 Troubleshooting

### Common Issues

**Script won't run**:
- Check execution policy: `Get-ExecutionPolicy`
- Run as administrator
- Verify PowerShell version: `$PSVersionTable.PSVersion`

**Package manager not found**:
- Script automatically installs missing providers
- Check internet connection
- Verify provider availability

**Application installation fails**:
- Check application availability in provider
- Verify package ID/name in configuration
- Check logs for detailed error information

**Registry modifications fail**:
- Ensure administrator privileges
- Check if registry path exists
- Verify system compatibility

### Log Analysis

Check the log file for detailed information:
```powershell
# View recent errors
Get-Content .\postinstall.log | Select-String "ERROR"

# View installation summary
Get-Content .\postinstall.log | Select-String "SUMMARY" -A 10
```

## 🤝 Contributing

### Code Standards
- Follow PowerShell best practices
- Include comprehensive documentation
- Implement proper error handling
- Add logging for all operations

### Testing
- Test on clean Windows installations
- Verify with different configurations
- Check administrator and standard user scenarios

### Pull Request Guidelines
- Provide clear description of changes
- Include updated documentation
- Test thoroughly before submission

## 🆘 Support

For issues, questions, or contributions:
1. Check the troubleshooting section
2. Review the log files
3. Open an issue with detailed information
4. Include configuration and log files when relevant

## 📚 Additional Resources

- [PowerShell Documentation](https://docs.microsoft.com/powershell/)
- [WinGet Documentation](https://docs.microsoft.com/windows/package-manager/)
- [Winget Create Documentation](https://github.com/microsoft/winget-create/)
- [Chocolatey Documentation](https://docs.chocolatey.org/)
- [Scoop Documentation](https://scoop.sh/)

## 🫶 Support the Projects

Your contributions are vital in helping to sustain the development of open-source projects and tools made freely available to everyone. If you find value in my work and wish to show your support, kindly consider making a donation:

### Cryptocurrency Wallets

- **Bitcoin (BTC):** `1EzBrKjKyXzxydSUNagAP8XLeRzBTxfHcg`
- **Ethereum (ETH):** `0xE65c32004b968cd1b4084bC3484C0dA051eeD3ee`
- **Solana (SOL):** `6kUAWW8q5169qnUJdxxLsNMPpaKPvbUSmryKDYTb9epn`
- **Polygon (MATIC):** `0xE65c32004b968cd1b4084bC3484C0dA051eeD3ee`
- **BNB (Binance Smart Chain):** `0xE65c32004b968cd1b4084bC3484C0dA051eeD3ee`

### Support via Other Platforms

- **Patreon:** [Support me on Patreon](https://patreon.com/mrcolorrain)
- **Buy Me a Coffee:** [Buy me a coffee](https://buymeacoffee.com/mrcolorrain)
- **Ko-fi:** [Support me on Ko-fi](https://ko-fi.com/mrcolorrain)

Your support, no matter how small, is enormously appreciated and directly fuels ongoing and future developments. Thank you for your generosity! 🙏

## ⚠️ Disclaimer
This project and its artifacts are provided "as is" and without warranty of any kind.

The author makes no warranties, express or implied, that this script is free of errors, defects, or suitable for any particular purpose.

The author shall not be held liable for any damages suffered by any user of this script, whether direct, indirect, incidental, consequential, or special, arising from the use of or inability to use this script or its documentation, even if the author has been advised of the possibility of such damages.

## 📄 License

This project is open source and available under the GPL 3.0 license.
