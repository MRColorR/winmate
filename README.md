# Windows Post-Installation Automation Script

A comprehensive PowerShell-based automation solution for Windows post-installation tasks, designed with software engineering best practices including modular architecture, comprehensive logging, error handling, and JSON-driven configuration.

## 🚀 Features

### Core Functionality
- **Windows Debloating**: Remove unwanted pre-installed applications and bloatware
- **Font Management**: Automated installation of Nerd Fonts and custom fonts
- **Application Installation**: Multi-provider app installation (WinGet, Chocolatey, Scoop, MS Store)
- **System Configuration**: Privacy, performance, and UI optimizations
- **Comprehensive Logging**: Structured logging with multiple levels and detailed reporting

### Technical Highlights
- **Modular Architecture**: Well-organized functions with single responsibility
- **Error Resilience**: Failures don't stop the entire process
- **JSON Configuration**: Flexible, human-readable configuration management
- **Multi-Provider Support**: Automatic package manager installation when needed
- **Extensive Documentation**: Comprehensive inline documentation and comments
- **Best Practices**: Follows PowerShell and software development best practices

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
   .\PostInstall.ps1
   
   # Run with custom configuration
   .\PostInstall.ps1 -ConfigPath "custom-config.json" -LogPath "my-install.log"
   ```

### Advanced Usage

```powershell
# Run with specific parameters
.\PostInstall.ps1 -ConfigPath "config\enterprise.json" -LogPath "logs\$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

# Check execution policy first
Get-ExecutionPolicy
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Run as administrator (required)
Start-Process PowerShell -Verb RunAs -ArgumentList "-File .\PostInstall.ps1"
```

## 📖 Configuration Guide

### Configuration File Structure

The `config.json` file is organized into main sections:

```json
{
  "debloat": { "enabled": true },
  "fonts": { "enabled": true },
  "apps": { "enabled": true },
  "settings": { "enabled": true }
}
```

### Section Details

#### 1. Debloat Section
Controls removal of unwanted Windows applications:

```json
"debloat": {
  "enabled": true,
  "description": "Controls whether to remove unwanted Windows applications"
}
```

#### 2. Fonts Section
Manages font installation including Nerd Fonts:

```json
"fonts": {
  "enabled": true,
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

#### 3. Apps Section
Controls application installation and removal:

```json
"apps": {
  "enabled": true,
  "AppName": {
    "remove": false,
    "install": true,
    "provider": "winget",
    "package_id": "Publisher.AppName",
    "description": "Application description"
  }
}
```

**Supported Providers**:
- `winget`: Windows Package Manager
- `chocolatey`: Chocolatey package manager
- `scoop`: Scoop package manager
- `msstore`: Microsoft Store
- `manual`: Direct download and installation

#### 4. Settings Section
System configuration and optimization:

```json
"settings": {
  "enabled": true,
  "privacy": {
    "enabled": true,
    "disable_telemetry": true,
    "disable_location": true,
    "disable_cortana": true
  },
  "performance": {
    "enabled": true,
    "disable_startup_delay": true,
    "optimize_visual_effects": true
  },
  "ui": {
    "enabled": true,
    "dark_mode": true,
    "show_file_extensions": true,
    "show_hidden_files": true
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
  "provider": "msstore",
  "description": "Application to be removed"
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

## 📄 License

This project is open source and available under the MIT License.

## 🆘 Support

For issues, questions, or contributions:
1. Check the troubleshooting section
2. Review the log files
3. Open an issue with detailed information
4. Include configuration and log files when relevant

## 📚 Additional Resources

- [PowerShell Documentation](https://docs.microsoft.com/powershell/)
- [WinGet Documentation](https://docs.microsoft.com/windows/package-manager/)
- [Chocolatey Documentation](https://docs.chocolatey.org/)
- [Scoop Documentation](https://scoop.sh/)

---

**Version**: 1.0.0  
**Last Updated**: June 5, 2025  
**Compatibility**: Windows 10/11, PowerShell 5.1+