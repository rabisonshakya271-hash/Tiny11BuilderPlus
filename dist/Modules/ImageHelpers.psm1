#Requires -RunAsAdministrator
<#
    ImageHelpers.psm1
    Wraps DISM/oscdimg operations for mounting, editing, and repackaging a
    Windows install image (install.wim / install.esd) — the same primitives
    Tiny11 Builder and NTLite use under the hood.
#>

function Copy-IsoContents {
    param(
        [Parameter(Mandatory)][string]$IsoPath,
        [Parameter(Mandatory)][string]$DestFolder
    )
    Write-Host "Mounting ISO $IsoPath ..."
    $mount = Mount-DiskImage -ImagePath $IsoPath -PassThru
    $driveLetter = ($mount | Get-Volume).DriveLetter
    try {
        if (-not (Test-Path $DestFolder)) { New-Item -ItemType Directory -Path $DestFolder | Out-Null }
        Write-Host "Copying ISO contents to $DestFolder ..."
        Copy-Item -Path "${driveLetter}:\*" -Destination $DestFolder -Recurse -Force
    }
    finally {
        Dismount-DiskImage -ImagePath $IsoPath | Out-Null
    }
    return $DestFolder
}

function Convert-EsdToWim {
    <# Some ISOs ship install.esd instead of install.wim; DISM can convert per-index. #>
    param(
        [Parameter(Mandatory)][string]$EsdPath,
        [Parameter(Mandatory)][string]$WimOutPath,
        [Parameter(Mandatory)][int]$Index
    )
    dism /Export-Image /SourceImageFile:$EsdPath /SourceIndex:$Index `
        /DestinationImageFile:$WimOutPath /Compress:max /CheckIntegrity
}

function Get-ImageEditions {
    param([Parameter(Mandatory)][string]$WimPath)
    $raw = dism /Get-WimInfo /WimFile:$WimPath
    $editions = @()
    $current = $null
    foreach ($line in $raw) {
        if ($line -match '^Index\s*:\s*(\d+)') { $current = [pscustomobject]@{ Index = [int]$Matches[1]; Name = $null } }
        if ($line -match '^Name\s*:\s*(.+)$' -and $current) {
            $current.Name = $Matches[1].Trim()
            $editions += $current
            $current = $null
        }
    }
    return $editions
}

function Mount-Image {
    param(
        [Parameter(Mandatory)][string]$WimPath,
        [Parameter(Mandatory)][int]$Index,
        [Parameter(Mandatory)][string]$MountDir
    )
    if (-not (Test-Path $MountDir)) { New-Item -ItemType Directory -Path $MountDir | Out-Null }
    Write-Host "Mounting index $Index of $WimPath -> $MountDir ..."
    dism /Mount-Image /ImageFile:$WimPath /Index:$Index /MountDir:$MountDir
}

function Dismount-ImageAndCommit {
    param(
        [Parameter(Mandatory)][string]$MountDir,
        [switch]$Discard
    )
    if ($Discard) {
        Write-Host "Discarding changes and unmounting $MountDir ..."
        dism /Unmount-Image /MountDir:$MountDir /Discard
    } else {
        Write-Host "Committing changes and unmounting $MountDir ..."
        dism /Unmount-Image /MountDir:$MountDir /Commit
    }
}

function Export-FinalIso {
    <#
        Requires the Windows ADK (specifically oscdimg.exe) installed.
        Default ADK path is used; override with -OscdimgPath if yours differs.
    #>
    param(
        [Parameter(Mandatory)][string]$SourceFolder,
        [Parameter(Mandatory)][string]$OutputIsoPath,
        [string]$OscdimgPath = "${env:ProgramFiles(x86)}\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
    )
    if (-not (Test-Path $OscdimgPath)) {
        throw "oscdimg.exe not found at '$OscdimgPath'. Install the Windows ADK 'Deployment Tools' component, or pass -OscdimgPath."
    }
    $bootData = "2#p0,e,b$SourceFolder\boot\etfsboot.com#pEF,e,b$SourceFolder\efi\microsoft\boot\efisys.bin"
    & $OscdimgPath -m -o -u2 -udfver102 -bootdata:$bootData $SourceFolder $OutputIsoPath
    Write-Host "ISO written to $OutputIsoPath"
}

Export-ModuleMember -Function Copy-IsoContents, Convert-EsdToWim, Get-ImageEditions, Mount-Image, Dismount-ImageAndCommit, Export-FinalIso
