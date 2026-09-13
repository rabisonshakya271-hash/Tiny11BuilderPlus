<#
<<<<<<< HEAD
<<<<<<< HEAD
Build-Exe.ps1
Compiles TinyBuilderPlus.ps1 (+ its Modules/Config folders) into a
single-file TinyBuilderPlus.exe using the ps2exe module.

```
Run this ON WINDOWS, from inside the TinyBuilderPlus folder:
    .\Build-Exe.ps1

Notes:
- ps2exe bundles the SCRIPT, not the Modules/Config folders. Those must
  ship alongside the .exe (same folder), which this script arranges in
  .\dist automatically. The GUI script already resolves paths relative
  to $PSScriptRoot / the exe's own folder, so this "just works".
- -requireAdmin embeds a UAC manifest, since DISM/registry-hive edits
  need elevation.
```

#>

param(
[string]$OutputName = "TinyBuilderPlus.exe",
[string]$IconPath   = ""
=======
=======
>>>>>>> 8e41531c0bd94d12aec81a064170bf878422f09e
    Build-Exe.ps1
    Compiles TinyBuilderPlus.ps1 (+ its Modules/Config folders) into a
    single-file TinyBuilderPlus.exe using the ps2exe module.

    Run this ON WINDOWS, from inside the TinyBuilderPlus folder:
        .\Build-Exe.ps1

    Notes:
    - ps2exe bundles the SCRIPT, not the Modules/Config folders. Those must
      ship alongside the .exe (same folder), which this script arranges in
      .\dist automatically. The GUI script already resolves paths relative
      to $PSScriptRoot / the exe's own folder, so this "just works".
    - -requireAdmin embeds a UAC manifest, since DISM/registry-hive edits
      need elevation.
#>

param(
    [string]$OutputName = "TinyBuilderPlus.exe",
    [string]$IconPath   = ""
<<<<<<< HEAD
>>>>>>> 8e41531c0bd94d12aec81a064170bf878422f09e
=======
>>>>>>> 8e41531c0bd94d12aec81a064170bf878422f09e
)

$ScriptRoot = $PSScriptRoot
$DistDir    = Join-Path $ScriptRoot "dist"

if (-not (Get-Module -ListAvailable -Name ps2exe)) {
<<<<<<< HEAD
<<<<<<< HEAD
Write-Host "Installing ps2exe module (one-time)..."
Install-Module -Name ps2exe -Scope CurrentUser -Force
=======
    Write-Host "Installing ps2exe module (one-time)..."
    Install-Module -Name ps2exe -Scope CurrentUser -Force
>>>>>>> 8e41531c0bd94d12aec81a064170bf878422f09e
=======
    Write-Host "Installing ps2exe module (one-time)..."
    Install-Module -Name ps2exe -Scope CurrentUser -Force
>>>>>>> 8e41531c0bd94d12aec81a064170bf878422f09e
}
Import-Module ps2exe

New-Item -ItemType Directory -Path $DistDir -Force | Out-Null

$exeParams = @{
<<<<<<< HEAD
<<<<<<< HEAD
InputFile    = Join-Path $ScriptRoot "TinyBuilderPlus.ps1"
OutputFile   = Join-Path $DistDir $OutputName
noConsole    = $true
requireAdmin = $true
title        = "TinyBuilder+"
version      = "1.0.0.0"
company      = "You"
product      = "TinyBuilder+"
=======
=======
>>>>>>> 8e41531c0bd94d12aec81a064170bf878422f09e
    InputFile    = Join-Path $ScriptRoot "TinyBuilderPlus.ps1"
    OutputFile   = Join-Path $DistDir $OutputName
    noConsole    = $true
    requireAdmin = $true
    title        = "TinyBuilder+"
    version      = "1.0.0.0"
    company      = "You"
    product      = "TinyBuilder+"
<<<<<<< HEAD
>>>>>>> 8e41531c0bd94d12aec81a064170bf878422f09e
=======
>>>>>>> 8e41531c0bd94d12aec81a064170bf878422f09e
}
if ($IconPath -and (Test-Path $IconPath)) { $exeParams["iconFile"] = $IconPath }

Write-Host "Compiling TinyBuilderPlus.ps1 -> $($exeParams.OutputFile) ..."
Invoke-ps2exe @exeParams

Write-Host "Copying Modules/ and Config/ next to the exe (required at runtime)..."
Copy-Item -Path (Join-Path $ScriptRoot "Modules") -Destination $DistDir -Recurse -Force
Copy-Item -Path (Join-Path $ScriptRoot "Config")  -Destination $DistDir -Recurse -Force

Write-Host ""
<<<<<<< HEAD
<<<<<<< HEAD
Write-Host "Done. Distribute the entire 'dist' folder (exe + Modules + Config) as a unit -"
=======
Write-Host "Done. Distribute the entire 'dist' folder (exe + Modules + Config) as a unit —"
>>>>>>> 8e41531c0bd94d12aec81a064170bf878422f09e
=======
Write-Host "Done. Distribute the entire 'dist' folder (exe + Modules + Config) as a unit —"
>>>>>>> 8e41531c0bd94d12aec81a064170bf878422f09e
Write-Host "the exe expects Modules\ and Config\ to sit next to it."
