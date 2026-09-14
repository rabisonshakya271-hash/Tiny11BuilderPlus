#Requires -RunAsAdministrator
<#
    TinyBuilderPlus.ps1
    A Tiny11-Builder-style Windows image customizer with NTLite-style
    software pre-install and update-slipstreaming, wrapped in a simple GUI.

    Run this directly with PowerShell, or compile it to TinyBuilderPlus.exe
    with Build-Exe.ps1.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ScriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

# ---------------------------------------------------------------------
# Import project modules
# ---------------------------------------------------------------------

$ImageHelpersPath = Join-Path $ScriptRoot "Modules\ImageHelpers.psm1"
$DebloatPath = Join-Path $ScriptRoot "Modules\Debloat.psm1"
$SoftwareInjectorPath = Join-Path $ScriptRoot "Modules\SoftwareInjector.psm1"
$UpdateIntegratorPath = Join-Path $ScriptRoot "Modules\UpdateIntegrator.psm1"

if (Test-Path -LiteralPath $ImageHelpersPath) {
    Import-Module $ImageHelpersPath -Force -ErrorAction Stop
}

if (Test-Path -LiteralPath $DebloatPath) {
    Import-Module $DebloatPath -Force -ErrorAction Stop
}

if (Test-Path -LiteralPath $SoftwareInjectorPath) {
    Import-Module $SoftwareInjectorPath -Force -ErrorAction Stop
}

if (Test-Path -LiteralPath $UpdateIntegratorPath) {
    Import-Module $UpdateIntegratorPath -Force -ErrorAction Stop
}

# =====================================================================
# FIXED IMAGE HELPER
# =====================================================================

function Mount-Image {
    param(
        [Parameter(Mandatory = $true)]
        [string]$WimPath,

        [Parameter(Mandatory = $true)]
        [int]$Index,

        [Parameter(Mandatory = $true)]
        [string]$MountDir
    )

    if (-not (Test-Path -LiteralPath $WimPath)) {
        throw "WIM file not found: $WimPath"
    }

    if ($Index -lt 1) {
        throw "Invalid image index: $Index. The index must be 1 or greater."
    }

    if (-not (Test-Path -LiteralPath $MountDir)) {
        New-Item `
            -ItemType Directory `
            -Path $MountDir `
            -Force |
            Out-Null
    }

    # Make sure the mount directory is empty before mounting.
    $existingItems = Get-ChildItem `
        -LiteralPath $MountDir `
        -Force `
        -ErrorAction SilentlyContinue

    if ($existingItems) {
        throw "Mount directory is not empty: $MountDir"
    }

    Write-Host "Mounting WIM image..."
    Write-Host "WIM: $WimPath"
    Write-Host "Index: $Index"
    Write-Host "Mount directory: $MountDir"

    $arguments = @(
        "/English",
        "/Mount-Wim",
        "/WimFile:$WimPath",
        "/Index:$Index",
        "/MountDir:$MountDir"
    )

    $process = Start-Process `
        -FilePath "dism.exe" `
        -ArgumentList $arguments `
        -Wait `
        -PassThru `
        -NoNewWindow

    if ($process.ExitCode -ne 0) {
        throw "DISM failed to mount the image. Exit code: $($process.ExitCode)"
    }

    Write-Host "WIM image mounted successfully."

    return $true
}

# =====================================================================
# FIXED SECTION — ISO extraction helper
# =====================================================================

function Copy-IsoContents {
    param(
        [Parameter(Mandatory = $true)]
        [string]$IsoPath,

        [Parameter(Mandatory = $true)]
        [string]$DestFolder
    )

    try {
        if (-not (Test-Path -LiteralPath $IsoPath)) {
            throw "ISO file not found: $IsoPath"
        }

        # Create destination folder
        if (-not (Test-Path -LiteralPath $DestFolder)) {
            New-Item -ItemType Directory -Path $DestFolder -Force | Out-Null
        }

        Write-Log "Mounting ISO..."

        # Mount ISO
        $diskImage = Mount-DiskImage `
            -ImagePath $IsoPath `
            -PassThru `
            -ErrorAction Stop

        try {
            # Get mounted volume
            $volume = $diskImage |
                Get-Volume `
                -ErrorAction Stop

            if (-not $volume.DriveLetter) {
                throw "Could not determine the drive letter of the mounted ISO."
            }

            $isoDrive = "$($volume.DriveLetter):"

            Write-Log "ISO mounted at $isoDrive"
            Write-Log "Copying ISO contents..."

            # Use robocopy so hidden/system files and the complete
            # Windows installation structure are copied.
            $robocopyArgs = @(
                "$isoDrive\",
                "$DestFolder\",
                "/E",
                "/COPY:DAT",
                "/DCOPY:DAT",
                "/R:1",
                "/W:1",
                "/XJ",
                "/NFL",
                "/NDL"
            )

            $process = Start-Process `
                -FilePath "robocopy.exe" `
                -ArgumentList $robocopyArgs `
                -Wait `
                -PassThru `
                -NoNewWindow

            # Robocopy exit codes 0-7 are normally successful/non-fatal.
            if ($process.ExitCode -gt 7) {
                throw "Robocopy failed while extracting the ISO. Exit code: $($process.ExitCode)"
            }

            Write-Log "ISO contents copied successfully."
        }
        finally {
            Write-Log "Dismounting ISO..."

            Dismount-DiskImage `
                -ImagePath $IsoPath `
                -ErrorAction SilentlyContinue
        }

        return $true
    }
    catch {
        throw "ISO extraction failed: $($_.Exception.Message)"
    }
}

# ---------- Working paths ----------
$Work = Join-Path $env:TEMP "TinyBuilderPlus"
$ExtractDir = Join-Path $Work "Extracted"
$MountDir   = Join-Path $Work "Mount"

New-Item -ItemType Directory -Path $Work -Force | Out-Null

# ---------- Main window ----------
$form                 = New-Object System.Windows.Forms.Form
$form.Text            = "TinyBuilder+"
$form.Size            = New-Object System.Drawing.Size(560, 520)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox     = $false

function New-Label($text, $x, $y, $w = 500) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, 20)
    $form.Controls.Add($l)
    return $l
}

function New-TextBox($x, $y, $w = 350) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($x, $y)
    $t.Size = New-Object System.Drawing.Size($w, 22)
    $form.Controls.Add($t)
    return $t
}

function New-Button($text, $x, $y, $w = 90) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, 25)
    $form.Controls.Add($b)
    return $b
}

New-Label "1. Windows 11 ISO path:" 15 15
$isoBox = New-TextBox 15 38
$isoBrowse = New-Button "Browse..." 375 37 80

$isoBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "ISO files (*.iso)|*.iso"

    if ($dlg.ShowDialog() -eq "OK") {
        $isoBox.Text = $dlg.FileName
    }
})

New-Label "2. Edition index (leave blank to list editions during build):" 15 70
$indexBox = New-TextBox 15 92 100

New-Label "3. Software list (JSON):" 15 130
$appsBox = New-TextBox 15 152
$appsBox.Text = Join-Path $ScriptRoot "Config\SampleApps.json"

$appsBrowse = New-Button "Browse..." 375 151 80

$appsBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "JSON files (*.json)|*.json"

    if ($dlg.ShowDialog() -eq "OK") {
        $appsBox.Text = $dlg.FileName
    }
})

New-Label "4. Updates folder (.msu/.cab), optional:" 15 190
$updatesBox = New-TextBox 15 212
$updatesBrowse = New-Button "Browse..." 375 211 80

$updatesBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog

    if ($dlg.ShowDialog() -eq "OK") {
        $updatesBox.Text = $dlg.SelectedPath
    }
})

New-Label "5. Bloat/tweak config (JSON):" 15 250
$bloatBox = New-TextBox 15 272
$bloatBox.Text = Join-Path $ScriptRoot "Config\BloatApps.json"

$bloatBrowse = New-Button "Browse..." 375 271 80

$bloatBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = "JSON files (*.json)|*.json"

    if ($dlg.ShowDialog() -eq "OK") {
        $bloatBox.Text = $dlg.FileName
    }
})

New-Label "6. Output ISO path:" 15 310
$outBox = New-TextBox 15 332
$outBrowse = New-Button "Browse..." 375 331 80

$outBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.SaveFileDialog
    $dlg.Filter = "ISO files (*.iso)|*.iso"

    if ($dlg.ShowDialog() -eq "OK") {
        $outBox.Text = $dlg.FileName
    }
})

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.Location = New-Object System.Drawing.Point(15, 370)
$logBox.Size = New-Object System.Drawing.Size(515, 70)
$form.Controls.Add($logBox)

function Write-Log($msg) {
    $logBox.AppendText("$(Get-Date -Format 'HH:mm:ss')  $msg`r`n")
    [System.Windows.Forms.Application]::DoEvents()
}

$buildBtn = New-Button "Build Image" 15 450 150

$buildBtn.Add_Click({
    try {
        $buildBtn.Enabled = $false

        if (-not $isoBox.Text -or -not (Test-Path $isoBox.Text)) {
            throw "Select a valid ISO path."
        }

        if (-not $outBox.Text) {
            throw "Select an output ISO path."
        }

        # -------------------------------------------------------------
        # Validate edition index
        # -------------------------------------------------------------

        $selectedIndex = 0

        if ($indexBox.Text.Trim()) {
            if (-not [int]::TryParse(
                $indexBox.Text.Trim(),
                [Globalization.NumberStyles]::Integer,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$selectedIndex
            )) {
                throw "Edition index must be a number, for example 1, 2, 3, etc. Do not enter an edition name such as Pro."
            }

            if ($selectedIndex -lt 1) {
                throw "Edition index must be 1 or greater."
            }
        }

        Write-Log "Extracting ISO..."

        Copy-IsoContents `
            -IsoPath $isoBox.Text `
            -DestFolder $ExtractDir

        $wimPath = Join-Path $ExtractDir "sources\install.wim"
        $esdPath = Join-Path $ExtractDir "sources\install.esd"

        if (-not (Test-Path $wimPath) -and (Test-Path $esdPath)) {
            if (-not $indexBox.Text) {
                throw "install.esd found — enter the edition index to convert (see Get-ImageEditions)."
            }

            Write-Log "Converting install.esd to install.wim for index $selectedIndex..."

            Convert-EsdToWim `
                -EsdPath $esdPath `
                -WimOutPath $wimPath `
                -Index $selectedIndex
        }

        if (-not (Test-Path -LiteralPath $wimPath)) {
            throw "Could not find or create install.wim: $wimPath"
        }

        if (-not $indexBox.Text) {
            $editions = Get-ImageEditions -WimPath $wimPath

            $list = ($editions | ForEach-Object {
                "$($_.Index): $($_.Name)"
            }) -join "`n"

            [System.Windows.Forms.MessageBox]::Show(
                "Available editions:`n$list`n`nRe-run and enter an index.",
                "Choose an edition"
            ) | Out-Null

            return
        }

        Write-Log "Mounting image index $selectedIndex..."

        Mount-Image `
            -WimPath $wimPath `
            -Index $selectedIndex `
            -MountDir $MountDir

        Write-Log "Removing bloat apps..."

        Remove-BloatApps `
            -MountDir $MountDir `
            -ConfigPath $bloatBox.Text

        Write-Log "Applying registry tweaks..."

        Set-OfflineRegistryTweaks `
            -MountDir $MountDir `
            -ConfigPath $bloatBox.Text

        if ($appsBox.Text -and (Test-Path $appsBox.Text)) {
            Write-Log "Staging pre-installed software..."

            Add-PreinstalledSoftware `
                -MountDir $MountDir `
                -ConfigPath $appsBox.Text
        }

        if ($updatesBox.Text -and (Test-Path $updatesBox.Text)) {
            Write-Log "Integrating Windows updates..."

            Add-UpdatePackages `
                -MountDir $MountDir `
                -UpdatesFolder $updatesBox.Text
        }

        Write-Log "Committing and unmounting image..."

        Dismount-ImageAndCommit `
            -MountDir $MountDir

        Write-Log "Exporting final ISO (requires Windows ADK oscdimg)..."

        Export-FinalIso `
            -SourceFolder $ExtractDir `
            -OutputIsoPath $outBox.Text

        Write-Log "Done! Output: $($outBox.Text)"

        [System.Windows.Forms.MessageBox]::Show(
            "Build complete:`n$($outBox.Text)",
            "TinyBuilder+"
        ) | Out-Null
    }
    catch {
        Write-Log "ERROR: $($_.Exception.Message)"

        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "Build failed",
            "OK",
            "Error"
        ) | Out-Null
    }
    finally {
        $buildBtn.Enabled = $true
    }
})

# =====================================================================
# ADDED SECTION — do not remove: Windows 11/10 ISO grabber,
# NTLite-style Post Setup (Before/After Login), and Updates manager.
# Everything above this point is untouched original code.
# =====================================================================

$form.Size = New-Object System.Drawing.Size(560, 680)

# ---------- Get Windows ISO ----------
New-Label "7. Get Windows ISO:" 15 485

$win11Btn = New-Button "Windows 11" 15 507 100
$win10Btn = New-Button "Windows 10" 130 507 100
$downloadIsoBtn = New-Button "Download ISO..." 245 507 140

$isoStatusLabel = New-Label `
    "Selected: Windows 11 — opens Microsoft's official page. Use Download ISO to fetch it automatically." `
    15 `
    535 `
    515

$script:SelectedWinVersion = "11"

$win11Btn.Add_Click({
    $script:SelectedWinVersion = "11"

    $isoStatusLabel.Text = "Selected: Windows 11 — opens Microsoft's official page. Use Download ISO to fetch it automatically."

    Start-Process "https://www.microsoft.com/software-download/windows11"
})

$win10Btn.Add_Click({
    $script:SelectedWinVersion = "10"

    $isoStatusLabel.Text = "Selected: Windows 10 — opens Microsoft's official page. Use Download ISO to fetch it automatically."

    Start-Process "https://www.microsoft.com/software-download/windows10"
})

function Get-FidoScript {
    # Fido (by pbatard, GPLv3) resolves the real, official Microsoft ISO
    # download link the same way the Microsoft download page's own
    # JavaScript does — this is the same open-source resolver used inside Rufus.

    $fidoPath = Join-Path $Work "Fido.ps1"

    if (-not (Test-Path $fidoPath)) {
        Write-Log "Fetching Fido (official Microsoft ISO link resolver)..."

        Invoke-WebRequest `
            -Uri "https://raw.githubusercontent.com/pbatard/Fido/master/Fido.ps1" `
            -OutFile $fidoPath `
            -UseBasicParsing `
            -ErrorAction Stop
    }

    return $fidoPath
}

$downloadIsoBtn.Add_Click({
    try {
        $downloadIsoBtn.Enabled = $false

        $saveDlg = New-Object System.Windows.Forms.SaveFileDialog
        $saveDlg.Filter = "ISO files (*.iso)|*.iso"
        $saveDlg.FileName = "Windows$($script:SelectedWinVersion).iso"

        if ($saveDlg.ShowDialog() -ne "OK") {
            return
        }

        $fidoPath = Get-FidoScript

        Write-Log "Resolving official Windows $($script:SelectedWinVersion) download link..."

        $urlOutput = & $fidoPath `
            -Win $script:SelectedWinVersion `
            -Rel Latest `
            -Ed Pro `
            -Lang "English International" `
            -Arch x64 `
            -GetUrl

        $url = ($urlOutput | Select-Object -Last 1).ToString().Trim()

        if (-not $url -or $url -notmatch '^https?://') {
            throw "Could not resolve a direct download link right now. Use the Windows $($script:SelectedWinVersion) button to download manually from Microsoft's site instead."
        }

        Write-Log "Downloading Windows $($script:SelectedWinVersion) ISO (this can take a while)..."

        Invoke-WebRequest `
            -Uri $url `
            -OutFile $saveDlg.FileName `
            -UseBasicParsing `
            -ErrorAction Stop

        $isoBox.Text = $saveDlg.FileName

        Write-Log "Download complete: $($saveDlg.FileName)"

        [System.Windows.Forms.MessageBox]::Show(
            "Windows $($script:SelectedWinVersion) ISO downloaded and set as the build source (step 1).",
            "Download complete"
        ) | Out-Null
    }
    catch {
        Write-Log "ERROR: $($_.Exception.Message)"

        [System.Windows.Forms.MessageBox]::Show(
            $_.Exception.Message,
            "Download failed",
            "OK",
            "Error"
        ) | Out-Null
    }
    finally {
        $downloadIsoBtn.Enabled = $true
    }
})

# ---------- Post Setup / Updates launcher buttons ----------
New-Label "8. Post Setup & Updates (NTLite-style):" 15 565

$postSetupBtn = New-Button "Post Setup..." 15 587 150
$updatesMgrBtn = New-Button "Updates..." 175 587 150

# ---------- Post Setup data (Before Login / After Login) ----------
$script:PostSetupBeforeLogin = New-Object System.Collections.ArrayList
# runs during specialize pass, SYSTEM context, before any user logs in

$script:PostSetupAfterLogin = New-Object System.Collections.ArrayList
# runs as a first-logon command, after the user logs in

function New-PostSetupTab {
    param(
        $TabControl,
        $Title,
        [System.Collections.ArrayList]$List
    )

    $tab = New-Object System.Windows.Forms.TabPage
    $tab.Text = $Title
    $TabControl.TabPages.Add($tab)

    $lv = New-Object System.Windows.Forms.ListView
    $lv.View = "Details"
    $lv.FullRowSelect = $true
    $lv.Location = New-Object System.Drawing.Point(10, 10)
    $lv.Size = New-Object System.Drawing.Size(430, 150)

    $lv.Columns.Add("Name", 120) | Out-Null
    $lv.Columns.Add("Path / Command", 180) | Out-Null
    $lv.Columns.Add("Arguments", 120) | Out-Null

    $tab.Controls.Add($lv)

    foreach ($item in $List) {
        $li = New-Object System.Windows.Forms.ListViewItem($item.Name)

        [void]$li.SubItems.Add($item.Path)
        [void]$li.SubItems.Add($item.Arguments)

        $lv.Items.Add($li) | Out-Null
    }

    $nameLbl = New-Object System.Windows.Forms.Label
    $nameLbl.Text = "Name:"
    $nameLbl.Location = New-Object System.Drawing.Point(10, 170)
    $nameLbl.Size = New-Object System.Drawing.Size(50, 20)
    $tab.Controls.Add($nameLbl)

    $nameTb = New-Object System.Windows.Forms.TextBox
    $nameTb.Location = New-Object System.Drawing.Point(65, 168)
    $nameTb.Size = New-Object System.Drawing.Size(160, 22)
    $tab.Controls.Add($nameTb)

    $pathLbl = New-Object System.Windows.Forms.Label
    $pathLbl.Text = "Path/Cmd:"
    $pathLbl.Location = New-Object System.Drawing.Point(10, 198)
    $pathLbl.Size = New-Object System.Drawing.Size(55, 20)
    $tab.Controls.Add($pathLbl)

    $pathTb = New-Object System.Windows.Forms.TextBox
    $pathTb.Location = New-Object System.Drawing.Point(65, 196)
    $pathTb.Size = New-Object System.Drawing.Size(300, 22)
    $tab.Controls.Add($pathTb)

    $pathBrowse = New-Object System.Windows.Forms.Button
    $pathBrowse.Text = "..."
    $pathBrowse.Location = New-Object System.Drawing.Point(370, 195)
    $pathBrowse.Size = New-Object System.Drawing.Size(35, 24)
    $tab.Controls.Add($pathBrowse)

    $pathBrowse.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog

        $dlg.Filter = "Installers (*.exe;*.msi;*.cmd;*.bat)|*.exe;*.msi;*.cmd;*.bat|All files (*.*)|*.*"

        if ($dlg.ShowDialog() -eq "OK") {
            $pathTb.Text = $dlg.FileName
        }
    })

    $argsLbl = New-Object System.Windows.Forms.Label
    $argsLbl.Text = "Arguments:"
    $argsLbl.Location = New-Object System.Drawing.Point(10, 228)
    $argsLbl.Size = New-Object System.Drawing.Size(60, 20)
    $tab.Controls.Add($argsLbl)

    $argsTb = New-Object System.Windows.Forms.TextBox
    $argsTb.Location = New-Object System.Drawing.Point(65, 226)
    $argsTb.Size = New-Object System.Drawing.Size(300, 22)
    $tab.Controls.Add($argsTb)

    $passiveChk = New-Object System.Windows.Forms.CheckBox
    $passiveChk.Text = "Auto-add /passive"
    $passiveChk.Checked = $true
    $passiveChk.Location = New-Object System.Drawing.Point(65, 254)
    $passiveChk.Size = New-Object System.Drawing.Size(150, 22)
    $tab.Controls.Add($passiveChk)

    $addBtn = New-Object System.Windows.Forms.Button
    $addBtn.Text = "Add"
    $addBtn.Location = New-Object System.Drawing.Point(290, 252)
    $addBtn.Size = New-Object System.Drawing.Size(75, 26)
    $tab.Controls.Add($addBtn)

    $removeBtn = New-Object System.Windows.Forms.Button
    $removeBtn.Text = "Remove Selected"
    $removeBtn.Location = New-Object System.Drawing.Point(10, 286)
    $removeBtn.Size = New-Object System.Drawing.Size(140, 26)
    $tab.Controls.Add($removeBtn)

    $addBtn.Add_Click({
        if (-not $nameTb.Text -or -not $pathTb.Text) {
            [System.Windows.Forms.MessageBox]::Show(
                "Enter at least a Name and a Path/Command.",
                "Missing info"
            ) | Out-Null

            return
        }

        $finalArgs = $argsTb.Text

        if ($passiveChk.Checked -and ($finalArgs -notmatch '(?i)/passive')) {
            $finalArgs = ("$finalArgs /passive").Trim()
        }

        $entry = [PSCustomObject]@{
            Name      = $nameTb.Text
            Path      = $pathTb.Text
            Arguments = $finalArgs
        }

        [void]$List.Add($entry)

        $li = New-Object System.Windows.Forms.ListViewItem($entry.Name)

        [void]$li.SubItems.Add($entry.Path)
        [void]$li.SubItems.Add($entry.Arguments)

        $lv.Items.Add($li) | Out-Null

        $nameTb.Text = ""
        $pathTb.Text = ""
        $argsTb.Text = ""
    })

    $removeBtn.Add_Click({
        if ($lv.SelectedIndices.Count -eq 0) {
            return
        }

        $idx = $lv.SelectedIndices[0]

        $List.RemoveAt($idx)
        $lv.Items.RemoveAt($idx)
    })
}

function Show-PostSetupDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Post Setup (NTLite-style)"
    $dlg.Size = New-Object System.Drawing.Size(480, 420)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false

    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Location = New-Object System.Drawing.Point(10, 10)
    $tabs.Size = New-Object System.Drawing.Size(450, 325)
    $dlg.Controls.Add($tabs)

    New-PostSetupTab `
        -TabControl $tabs `
        -Title "Before Login" `
        -List $script:PostSetupBeforeLogin

    New-PostSetupTab `
        -TabControl $tabs `
        -Title "After Login" `
        -List $script:PostSetupAfterLogin

    $saveBtn = New-Object System.Windows.Forms.Button
    $saveBtn.Text = "Save && Close"
    $saveBtn.Location = New-Object System.Drawing.Point(345, 345)
    $saveBtn.Size = New-Object System.Drawing.Size(115, 28)
    $dlg.Controls.Add($saveBtn)

    $saveBtn.Add_Click({
        $cfgDir = Join-Path $ScriptRoot "Config"

        New-Item `
            -ItemType Directory `
            -Path $cfgDir `
            -Force |
            Out-Null

        $cfg = [PSCustomObject]@{
            BeforeLogin = @($script:PostSetupBeforeLogin)
            # SYSTEM-context, runs before any user logs on (specialize pass)

            AfterLogin = @($script:PostSetupAfterLogin)
            # runs at first user logon (FirstLogonCommands)
        }

        $cfgPath = Join-Path $cfgDir "PostSetup.json"

        $cfg |
            ConvertTo-Json -Depth 5 |
            Set-Content -Path $cfgPath -Encoding UTF8

        Write-Log "Post Setup config saved: $cfgPath"

        $dlg.Close()
    })

    $dlg.ShowDialog() | Out-Null
}

$postSetupBtn.Add_Click({
    Show-PostSetupDialog
})

# ---------- Updates manager (NTLite-style) ----------
function Show-UpdatesDialog {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "Windows Updates (NTLite-style)"
    $dlg.Size = New-Object System.Drawing.Size(480, 400)
    $dlg.StartPosition = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false

    $folderLbl = New-Object System.Windows.Forms.Label
    $folderLbl.Text = "Updates folder (.msu/.cab)"
    $folderLbl.Location = New-Object System.Drawing.Point(10, 10)
    $folderLbl.Size = New-Object System.Drawing.Size(200, 20)
    $dlg.Controls.Add($folderLbl)

    $folderTb = New-Object System.Windows.Forms.TextBox
    $folderTb.Text = $updatesBox.Text
    $folderTb.Location = New-Object System.Drawing.Point(10, 32)
    $folderTb.Size = New-Object System.Drawing.Size(340, 22)
    $dlg.Controls.Add($folderTb)

    $folderBrowse = New-Object System.Windows.Forms.Button
    $folderBrowse.Text = "Browse..."
    $folderBrowse.Location = New-Object System.Drawing.Point(360, 31)
    $folderBrowse.Size = New-Object System.Drawing.Size(90, 24)
    $dlg.Controls.Add($folderBrowse)

    $fileList = New-Object System.Windows.Forms.ListBox
    $fileList.Location = New-Object System.Drawing.Point(10, 65)
    $fileList.Size = New-Object System.Drawing.Size(440, 210)
    $dlg.Controls.Add($fileList)

    function Update-FileList {
        $fileList.Items.Clear()

        if ($folderTb.Text -and (Test-Path $folderTb.Text)) {
            Get-ChildItem `
                -Path $folderTb.Text `
                -Include *.msu, *.cab `
                -Recurse `
                -ErrorAction SilentlyContinue |
                ForEach-Object {
                    $fileList.Items.Add($_.Name) | Out-Null
                }
        }
    }

    Update-FileList

    $folderBrowse.Add_Click({
        $fbd = New-Object System.Windows.Forms.FolderBrowserDialog

        if ($fbd.ShowDialog() -eq "OK") {
            $folderTb.Text = $fbd.SelectedPath
            Update-FileList
        }
    })

    $addFilesBtn = New-Object System.Windows.Forms.Button
    $addFilesBtn.Text = "Add Update File(s)..."
    $addFilesBtn.Location = New-Object System.Drawing.Point(10, 282)
    $addFilesBtn.Size = New-Object System.Drawing.Size(150, 28)
    $dlg.Controls.Add($addFilesBtn)

    $addFilesBtn.Add_Click({
        if (-not $folderTb.Text) {
            [System.Windows.Forms.MessageBox]::Show(
                "Choose an updates folder first.",
                "No folder"
            ) | Out-Null

            return
        }

        New-Item `
            -ItemType Directory `
            -Path $folderTb.Text `
            -Force |
            Out-Null

        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = "Update packages (*.msu;*.cab)|*.msu;*.cab"
        $ofd.Multiselect = $true

        if ($ofd.ShowDialog() -eq "OK") {
            foreach ($f in $ofd.FileNames) {
                Copy-Item `
                    -Path $f `
                    -Destination $folderTb.Text `
                    -Force
            }

            Update-FileList
        }
    })

    $removeFileBtn = New-Object System.Windows.Forms.Button
    $removeFileBtn.Text = "Remove Selected"
    $removeFileBtn.Location = New-Object System.Drawing.Point(170, 282)
    $removeFileBtn.Size = New-Object System.Drawing.Size(130, 28)
    $dlg.Controls.Add($removeFileBtn)

    $removeFileBtn.Add_Click({
        if ($fileList.SelectedItem) {
            Remove-Item `
                -Path (Join-Path $folderTb.Text $fileList.SelectedItem) `
                -Force `
                -ErrorAction SilentlyContinue

            Update-FileList
        }
    })

    $catalogBtn = New-Object System.Windows.Forms.Button
    $catalogBtn.Text = "Open Microsoft Update Catalog"
    $catalogBtn.Location = New-Object System.Drawing.Point(10, 318)
    $catalogBtn.Size = New-Object System.Drawing.Size(220, 28)
    $dlg.Controls.Add($catalogBtn)

    $catalogBtn.Add_Click({
        Start-Process "https://www.catalog.update.microsoft.com/Home.aspx"
    })

    $closeBtn = New-Object System.Windows.Forms.Button
    $closeBtn.Text = "Save && Close"
    $closeBtn.Location = New-Object System.Drawing.Point(360, 318)
    $closeBtn.Size = New-Object System.Drawing.Size(90, 28)
    $dlg.Controls.Add($closeBtn)

    $closeBtn.Add_Click({
        $updatesBox.Text = $folderTb.Text
        $dlg.Close()
    })

    $dlg.ShowDialog() | Out-Null
}

$updatesMgrBtn.Add_Click({
    Show-UpdatesDialog
})

# =====================================================================
# END ADDED SECTION
# =====================================================================

$form.Add_Shown({
    $form.Activate()
})

[void]$form.ShowDialog()
