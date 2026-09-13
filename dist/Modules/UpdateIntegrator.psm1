#Requires -RunAsAdministrator
<#
    UpdateIntegrator.psm1
    NTLite-style update slipstreaming: integrates .msu / .cab Windows Update
    packages directly into the OFFLINE mounted image via DISM, so the final
    ISO already includes them — no post-install "Windows Update" step needed.

    Workflow:
      1. Download the update(s) you want (e.g. from the Microsoft Update
         Catalog: https://catalog.update.microsoft.com) as .msu or .cab.
      2. Drop them in a folder.
      3. Call Add-UpdatePackages -MountDir <mount> -UpdatesFolder <folder>

    You can re-run this against a fresh image any time a new cumulative
    update ships — that's the "keep it updateable" behavior you get from
    NTLite's update-integration feature.
#>

function Add-UpdatePackages {
    param(
        [Parameter(Mandatory)][string]$MountDir,
        [Parameter(Mandatory)][string]$UpdatesFolder
    )
    if (-not (Test-Path $UpdatesFolder)) {
        Write-Warning "Updates folder '$UpdatesFolder' does not exist — skipping."
        return
    }

    $packages = Get-ChildItem -Path $UpdatesFolder -Include *.msu, *.cab -Recurse
    if (-not $packages -or $packages.Count -eq 0) {
        Write-Host "No .msu/.cab files found in $UpdatesFolder — nothing to integrate."
        return
    }

    # Apply in filename order; Microsoft's naming (e.g. SSU before LCU) usually sorts correctly,
    # but double-check against the KB release notes if DISM reports a dependency error.
    foreach ($pkg in ($packages | Sort-Object Name)) {
        Write-Host "Integrating update package: $($pkg.Name) ..."
        $result = dism /Image:$MountDir /Add-Package /PackagePath:"$($pkg.FullName)" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "DISM reported an issue with $($pkg.Name):`n$result"
        }
    }
}

function Get-IntegratedPackages {
    <# Lists packages already present in the offline image, so you can verify what's baked in. #>
    param([Parameter(Mandatory)][string]$MountDir)
    dism /Image:$MountDir /Get-Packages
}

Export-ModuleMember -Function Add-UpdatePackages, Get-IntegratedPackages
