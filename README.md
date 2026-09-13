# TinyBuilder+

A Tiny11-Builder-style Windows image customizer, with NTLite-style
pre-installed software and update slipstreaming — packaged as a PowerShell
GUI that you can compile into a standalone `.exe`.

**Must be run on Windows, with Administrator rights.** It relies on `dism.exe`,
`reg.exe`, and (for the final ISO) `oscdimg.exe` from the Windows ADK — none
of that exists on Linux/macOS, so this can't be tested in this sandbox, but
the code follows the same DISM workflow Tiny11 Builder and NTLite use.

## Folder layout

```
TinyBuilderPlus/
├── TinyBuilderPlus.ps1        # GUI entry point — run this
├── Build-Exe.ps1              # compiles the above into TinyBuilderPlus.exe
├── Modules/
│   ├── ImageHelpers.psm1      # ISO extract / DISM mount / oscdimg export
│   ├── Debloat.psm1           # removes bloat Appx + registry tweaks
│   ├── SoftwareInjector.psm1  # stages your chosen apps for first-boot install
│   └── UpdateIntegrator.psm1  # slipstreams .msu/.cab updates (NTLite-style)
└── Config/
    ├── BloatApps.json         # editable: what to remove/tweak
    └── SampleApps.json        # editable: what software to pre-install
```

## Prerequisites (on the Windows machine you build with)

1. **Windows 10/11**, running PowerShell **as Administrator**.
2. **Windows ADK** — install just the "Deployment Tools" component, needed
   for `oscdimg.exe` (final ISO creation).
   https://learn.microsoft.com/windows-hardware/get-started/adk-install
3. To compile to `.exe`: internet access once, to install the `ps2exe`
   PowerShell module (`Build-Exe.ps1` does this automatically).

## Running it as a script (no compiling needed)

```powershell
cd TinyBuilderPlus
powershell -ExecutionPolicy Bypass -File .\TinyBuilderPlus.ps1
```

The GUI walks you through:
1. Pick your Windows 11 ISO.
2. Pick the edition index (leave blank the first run — it'll show you the
   list of editions in that ISO, then re-run with the number).
3. Point at a software list JSON (edit `Config\SampleApps.json` with real
   installer paths + silent switches for your own apps).
4. Optionally point at a folder of `.msu`/`.cab` Windows Update packages to
   slipstream in — this is the "add updates like NTLite" feature.
5. Point at the debloat config (or use the default).
6. Pick where to save the finished ISO, click **Build Image**.

## Compiling to a standalone .exe

```powershell
cd TinyBuilderPlus
powershell -ExecutionPolicy Bypass -File .\Build-Exe.ps1
```

This produces `dist\TinyBuilderPlus.exe`. **Ship the whole `dist` folder**
(exe + `Modules\` + `Config\` together) — the exe reads those folders at
runtime, the same way the script does. Double-clicking the exe will prompt
for elevation automatically (a UAC manifest is embedded).

## Customizing what gets removed

Edit `Config\BloatApps.json`:
- `ProvisionedPackages`: package-name prefixes to strip from the image.
- `RegistryTweaks`: offline registry edits (telemetry, consumer features,
  widgets, etc.) applied by loading the image's `SOFTWARE` hive.

No code changes needed — just edit the JSON and re-run a build.

## Customizing what gets pre-installed

Edit `Config\SampleApps.json`. Each entry needs:
- `Source` — full path to the installer **on your build PC**.
- `SilentArgs` — that installer's real silent/unattended switch (check the
  vendor's docs; e.g. `/S`, `/silent`, `/quiet`, `/VERYSILENT`, etc.).
- `Enabled` — `true`/`false` toggle without deleting the entry.

These installers get copied into the image and run once, automatically, the
very first time the finished Windows install boots (via
`Windows\Setup\Scripts\SetupComplete.cmd`) — so from the end user's
perspective the software is simply "already there."

## Adding/updating Windows Updates (NTLite-style)

1. Download the `.msu` (or `.cab`) files you want from the
   [Microsoft Update Catalog](https://catalog.update.microsoft.com) —
   typically the latest cumulative update (LCU) and, if required, the
   servicing stack update (SSU) for that Windows build.
2. Put them in one folder.
3. Point the GUI's "Updates folder" field at it (or call
   `Add-UpdatePackages -MountDir <mount> -UpdatesFolder <folder>` directly
   from `Modules\UpdateIntegrator.psm1`).

Because this is just a folder + a DISM call, keeping your image current is
as simple as dropping in the newest `.msu` before your next build — no code
changes required. That's the same "recipe you re-run against a fresh base"
model NTLite uses for update integration.

## Safety/legal notes

- You need a legitimate license for the Windows ISO/edition you're
  customizing, and for every piece of software you inject.
- Removing certain components (e.g. Defender, Edge) can affect update
  eligibility, support, or security posture — test images in a VM before
  deploying them to real hardware.
- This tool doesn't download Windows ISOs or updates for you; you supply
  them, so you stay in control of provenance and licensing.

