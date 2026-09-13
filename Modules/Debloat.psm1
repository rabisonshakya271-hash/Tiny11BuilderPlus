#Requires -RunAsAdministrator
<#
    Debloat.psm1
    Removes provisioned Appx packages and applies telemetry/registry tweaks
    to an OFFLINE mounted image, driven entirely by Config\BloatApps.json.
#>

function Remove-BloatApps {
    param(
        [Parameter(Mandatory)][string]$MountDir,
        [Parameter(Mandatory)][string]$ConfigPath
    )
    $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $provisioned = Get-AppxProvisionedPackage -Path $MountDir

    foreach ($appPrefix in $cfg.ProvisionedPackages) {
        $matches = $provisioned | Where-Object { $_.PackageName -like "$appPrefix*" }
        foreach ($pkg in $matches) {
            Write-Host "Removing provisioned package: $($pkg.PackageName)"
            Remove-AppxProvisionedPackage -Path $MountDir -PackageName $pkg.PackageName -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

function Set-OfflineRegistryTweaks {
    param(
        [Parameter(Mandatory)][string]$MountDir,
        [Parameter(Mandatory)][string]$ConfigPath
    )
    $cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $hivePath = Join-Path $MountDir "Windows\System32\config\SOFTWARE"
    $loadedKey = "HKLM\ZSOFTWARE"

    reg load $loadedKey $hivePath | Out-Null
    try {
        foreach ($tweak in $cfg.RegistryTweaks) {
            $keyPath = $tweak.Hive -replace '^HKLM\\', 'HKLM:\'
            if (-not (Test-Path $keyPath)) {
                New-Item -Path $keyPath -Force | Out-Null
            }
            Write-Host "Applying tweak: $($tweak.Description)"
            New-ItemProperty -Path $keyPath -Name $tweak.Name -PropertyType $tweak.Type -Value $tweak.Value -Force | Out-Null
        }
    }
    finally {
        # Registry hives must be fully released before unloading, otherwise reg unload fails.
        [gc]::Collect()
        reg unload $loadedKey | Out-Null
    }
}

Export-ModuleMember -Function Remove-BloatApps, Set-OfflineRegistryTweaks
