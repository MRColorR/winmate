function Import-ModuleFromFolder($name) {
    $moduleFileName = "$($name.ToLower()).ps1" # Force to lowercase

    # $PSScriptRoot in this context (importer.ps1 dot-sourced by post_install.ps1)
    # should refer to the directory of post_install.ps1.
    # Using -ForceBuild on Join-Path can help if intermediate directories don't exist, though "modules" should.
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath "modules\$moduleFileName"

    # For debugging, output the paths PowerShell is working with.
    Write-Host "Importer: Attempting to load module '$name' (normalized to '$moduleFileName')"
    Write-Host "Importer: PSScriptRoot is '$PSScriptRoot'"
    Write-Host "Importer: Trying module path '$modulePath'"

    if (Test-Path -Path $modulePath -PathType Leaf) {
        Write-Host "Importer: Module '$moduleFileName' FOUND at '$modulePath'. Dot-sourcing..."
        . $modulePath
        Write-Host "Importer: Module '$moduleFileName' successfully dot-sourced."
    } else {
        Write-Host "Importer: [CRITICAL ERROR] Module file '$moduleFileName' NOT FOUND at path '$modulePath'." -ForegroundColor Red
        # Attempt to list contents of the expected 'modules' directory for further diagnosis.
        $modulesExpectedDir = Join-Path -Path $PSScriptRoot -ChildPath "modules"
        if (Test-Path -Path $modulesExpectedDir -PathType Container) {
            Write-Host "Importer: Contents of expected modules directory '$modulesExpectedDir':"
            Get-ChildItem -Path $modulesExpectedDir | ForEach-Object { Write-Host "Importer:   Found: $($_.Name)" }
        } else {
            Write-Host "Importer: [CRITICAL ERROR] Expected modules directory NOT FOUND at '$modulesExpectedDir'." -ForegroundColor Red
        }
    }
}

# Example usage lines are removed as per instructions.
