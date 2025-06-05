function Import-ModuleFromFolder($name) {
    $path = Join-Path -Path $PSScriptRoot -ChildPath "modules/$name.ps1"
    if (Test-Path $path) {
        . $path
    } else {
        Write-Host "[WARNING] Module not found: $name.ps1" -ForegroundColor Yellow
    }
}

# Example usage:
Import-ModuleFromFolder -name "settings"
Import-ModuleFromFolder -name "logging"
