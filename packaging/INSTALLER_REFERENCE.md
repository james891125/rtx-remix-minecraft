# Unofficial 1.21.4 trial installer reference

This branch changes the upstream installer's supported scope to Prism only.
All modes target **RTX Remix 1.21.4 Trial**, never an upstream/legacy instance.
`-Launcher Microsoft` is rejected before execution.

## Commands

Run from the extracted ZIP in a non-administrator Windows terminal:

```powershell
.\install.bat
.\install.bat -Mode Install -Unattended -Launcher Prism
.\install.bat -Mode Upgrade -Unattended -Launcher Prism
.\install.bat -Mode Repair -Unattended -Launcher Prism
.\install.bat -Mode Install -PrismDataDir 'D:\Prism'
.\install.bat -Mode Uninstall -Unattended -AcknowledgeDataLoss -Launcher Prism
.\install.bat -Mode Export -Unattended -Launcher Prism -OutputPath 'D:\trial-export.zip'
```

`install.bat` runs the adjacent PowerShell script using Windows PowerShell 5.1.
It requests process-local ExecutionPolicy Bypass, not a lasting system policy
change. Read the shipped code before running an unsigned installer.

## Modes and options

- **Install** creates/reuses the isolated trial instance and installs the
  packaged mod plus matching Fabric API.
- **Upgrade / Repair** keep that same instance and its user data. They do not
  convert Minecraft/Fabric versions. An incomplete or mismatched instance fails
  before mutation.
- **Uninstall** removes mod/runtime files. `-AcknowledgeDataLoss` is mandatory
  with `-Unattended`. Interactive deeper cleanup explicitly deletes the
  selected instance, managed Java, or the entire trial portable Prism root.
- **Export** makes a copy of the existing trial instance for another Windows
  computer. It excludes the default saves, screenshots, logs, account-related
  name caches, saved servers, and launcher caches. It does not audit arbitrary
  custom configuration for secrets: inspect any export before sharing it.
  An existing `-OutputPath` is overwritten in unattended mode.
- **PrismDataDir** names an existing Prism data directory. Only the trial
  instance beneath it is managed, not sibling instances. A nonexistent path
  fails in unattended mode.
- **PrismVersion** optionally pins a Prism download. Without it the installer
  resolves a supported release using the upstream download checks.
- **DevServer** optionally adds a server only if no saved server list exists.
- **Verbose** adds diagnostics.
- **SkipHashCheck** is an inherited troubleshooting flag that disables
  download verification. Do not use it for a normal installation.
- **GitHubToken** is optional for public-download API rate limits. No token is
  required. Avoid passing secrets in command-line arguments or sharing logs.

## Isolation and safety checks

- Trial instance: `RTX Remix 1.21.4 Trial`.
- Trial managed root: `%LOCALAPPDATA%\RtxRemixMinecraftTrial1214`.
- No Microsoft Launcher install, profile rewrite, uninstall, or legacy
  migration. The old global `%APPDATA%\.minecraft` is not a target.
- Before installing, the JAR must identify this trial and Minecraft 1.21.4,
  and contain the host architecture's `d3d9.dll` and `remixbridge.dll`.
- Existing trial metadata must contain exactly one Minecraft 1.21.4 component
  and one Fabric Loader 0.16.9 component.
- Existing installation paths, their ancestors, and descendants are checked
  for reparse points. Junctions and symbolic links are refused rather than
  followed into other game directories.
- Download checksums remain enabled by default. The package preserves all
  license files and attribution from the source baseline.

Close Minecraft before changing the trial. No installer can guarantee safe
concurrent access if another program changes paths while it is writing.

## Build and verification

Use Windows, Git, JDK 21, and Visual Studio C++ tools:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File packaging/test_trial_installer.ps1
.\gradlew.bat --no-daemon clean releaseArchive -Parch=win64
powershell -NoProfile -ExecutionPolicy Bypass -File packaging/verify_trial_archive.ps1
```

`releaseArchive` includes the normal Java tests and native/payload checks. The
separate installer tests use temporary fixtures without downloading, launching
Prism, or touching real user data. The final ZIP verifier inspects the packaged
archive and writes SHA-256 checksums. None of these tests establishes live GPU,
world-loading, or rendering compatibility; that still needs a Windows RTX run.
