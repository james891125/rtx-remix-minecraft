# RTX Remix for Minecraft 1.21.4: unofficial trial installer

**Community trial, not an official NVIDIA release.** This package targets
Minecraft Java Edition 1.21.4. It does not guarantee parity with the upstream
1.21.1 renderer. Build checks do not verify live gameplay or RTX rendering.

## Before installing

- Use Windows 10/11 x64 with a GeForce RTX GPU and current compatible NVIDIA
  drivers. The upstream baseline recommends an RTX 30-series or newer GPU and
  16 GB RAM; this port's performance has not been established.
- Own Minecraft Java Edition on the Microsoft account you use with Prism.
- Keep internet access available for Prism, Java, Minecraft, and Fabric API.
- Allow several GB for downloads, runtime files, and first-launch caches.
- Back up important worlds. Begin with a new world or a copy, not your only save.
- This installer ZIP is **x64 only**, not ARM64. The installer verifies that
  the packaged JAR contains a native runtime matching your host before install.

## Install

1. Extract the **entire ZIP**. Do not run the installer inside the ZIP viewer.
2. Double-click `install.bat`. Do **not** run as administrator.
3. Choose Install. This trial supports **Prism Launcher only**.
4. Sign in with your own Minecraft Java Edition account in Prism.
5. Launch **RTX Remix 1.21.4 Trial**. If it is not listed, refresh Prism with F5.
6. Allow first-launch downloads and shader compilation to finish.

If Prism is already installed, the installer creates a new instance under its
usual data directory. With a custom Prism data directory, use `-PrismDataDir`
as described in `INSTALLER_REFERENCE.md`. Otherwise it downloads a portable
Prism to `%LOCALAPPDATA%\RtxRemixMinecraftTrial1214\PrismLauncher`.
Its managed Java, when required, is separate at
`%LOCALAPPDATA%\RtxRemixMinecraftTrial1214\jdk-21`.

The instance's game directory is
`<Prism data directory>\instances\RTX Remix 1.21.4 Trial\.minecraft`.
The installer does not upgrade or migrate the upstream 1.21.1 instance, does
not change Microsoft Launcher's shared `%APPDATA%\.minecraft`, and does not
copy existing worlds. **Microsoft Launcher is deliberately disabled.**

A pre-existing trial instance must already target Minecraft 1.21.4 and Fabric
Loader 0.16.9. The installer refuses mismatched/incomplete instances and paths
containing junctions or symbolic links. Back up and move a conflicting trial
instance aside, then retry; do not point it at an old game directory.

## Upgrade, repair, and remove

Run `install.bat` again to update or repair this trial instance. Upgrade keeps
worlds and user configuration except for the installer's documented managed
JVM/memory and resource-pack ordering adjustments. The native runtime refreshes
from the bundled JAR when Minecraft next launches.

Normal Uninstall removes trial mod/runtime files and preserves worlds. Optional
**Remove instance** deletes that trial instance including its worlds. Optional
**Remove portable Prism** or **Scorched earth** deletes all instances and worlds
inside the trial portable directory. Back those up first. Other Prism data
roots and Microsoft's game directory are not cleanup targets.

## Package contents

- `install.bat`, `installer.ps1`: installer entry point and implementation.
- `mods/`: exactly one packaged, remapped trial JAR, including native runtime.
- `migrate_resource_packs.ps1`: resource-pack migration helper.
- `README.md`, `INSTALLER_REFERENCE.md`: these instructions and advanced usage.
- `LICENSE`, `NOTICE`, `THIRD_PARTY_NOTICES.md`, `packaging/licenses/`: preserved
  project and bundled-component licenses and attribution.

The JAR name includes `0.1.0-trial.1.21.4-installer.1`, build time, source commit,
and architecture. Keep the full name and `latest.log` for troubleshooting.
Never substitute a lightweight JAR from `build/libs` for the packaged JAR.
Compare the ZIP's SHA-256 with its supplied checksum before using it.
The scripts and JAR are unsigned.

## Runtime privacy and troubleshooting

The bundled RTX Remix runtime may send session information and crash reports
to NVIDIA. Review its First Use Guide and Permissions tab before opting in.
No account credentials or personal saves are included in this package.

- If login fails, use Prism's normal account sign-in. Do not share passwords or
  account tokens with anyone troubleshooting this mod.
- If the installer reports an unsupported architecture, use an appropriately
  built package. Do not disable the check or mix runtime DLLs.
- If startup/world loading fails, retain the full JAR filename and logs from
  this trial instance. Rendering compatibility remains experimental.
- Do not bypass antivirus or Windows security warnings automatically. Check
  the source, origin, and file hashes before deciding whether to trust a file.
