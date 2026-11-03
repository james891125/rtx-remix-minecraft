# RTX Remix for Minecraft 1.21.4: unofficial trial

This branch packages the experimental Minecraft **1.21.4** port from
[`efd5280`](https://github.com/james891125/rtx-remix-minecraft/commit/efd5280da270cebe81795a5e3c1ffdfa2cc696f1).
It is a community trial, **not an NVIDIA release**, and does not claim feature,
rendering, or performance parity with the upstream Minecraft 1.21.1 version.
A successful build checks compilation and tests, not live RTX gameplay.

## Install the trial

Use an installer ZIP built from this branch, not an upstream 1.21.1 release
or a lightweight JAR from `build/libs`.

1. Extract the entire ZIP to a normal folder on Windows x64.
2. Run `install.bat` without administrator privileges. Choose Install.
3. Sign in to your own Minecraft Java Edition account in Prism Launcher.
4. Launch **RTX Remix 1.21.4 Trial**. Test with a new world or a backup copy.

See [the archive README](packaging/INSTALL.md) and
[installer reference](packaging/INSTALLER_REFERENCE.md).
The trial uses a new Prism instance. Microsoft Launcher support is disabled
because the upstream installer uses its shared `.minecraft` directory.
Existing 1.21.1 instances and the branch backing upstream PR #71 are not
migration targets. Do not manually copy this JAR into an existing 1.21.1 game.

## Build an installable ZIP

Requirements: Windows, Git, a 64-bit JDK 21, and Visual Studio C++ tools.
The runtime is fetched from the unchanged public Packman pins. No game account
or credentials are needed to build. Use a fresh checkout; do not build while
Minecraft is using that checkout's native files.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File packaging/test_trial_installer.ps1
.\gradlew.bat --no-daemon clean releaseArchive -Parch=win64
powershell -NoProfile -ExecutionPolicy Bypass -File packaging/verify_trial_archive.ps1
```

`releaseArchive` runs the Java build and tests, compiles the x64 JNI bridge,
verifies the bundled runtime and licenses, then writes the installer ZIP to
`build/distributions/`. The final verifier checks the ZIP and bundled JAR and
writes SHA-256 checksums. These commands build an archive only; they do not install or launch the game.
This branch does not publish releases or upload public build artifacts.

## Trial boundaries

- Minecraft 1.21.4, Fabric Loader 0.16.9, Fabric API 0.119.4+1.21.4, Java 21.
- The build commands above produce **Windows x64 only**. ARM64 requires a separately
  built matching runtime; the installer rejects an archive lacking its host's
  native payload before changing the launcher.
- The named trial instance must match the Minecraft and Fabric pins before
  reuse. An incomplete or mismatched instance is refused, not converted.
- Junctions and symbolic links in installation/deletion targets are refused.
- The installer is unsigned. Inspect the source and checksum before running.
- Live login, world loading, shader compilation, rendering, and performance
  still require testing on suitable RTX hardware. A ZIP is not evidence that
  the entire port works.

The upstream architecture and development guides remain under [docs/](docs/)
and [tools/](tools/). They describe the 1.21.1 baseline unless explicitly
updated for this port. Baseline feature lists are not trial acceptance results.

## Privacy and licensing

The mod's bundled RTX Remix runtime can send session information and crash
reports to NVIDIA. Review the runtime's First Use Guide and Permissions tab;
see [the upstream privacy explanation](docs/PLAYING.md#crash-reports-and-privacy).
No launcher accounts, access tokens, saves, or user settings are bundled in the
build artifacts.

Original NVIDIA copyright, Apache-2.0 license, attribution notices, and runtime
third-party license files are preserved in both source and packaged output.
See [LICENSE](LICENSE), [NOTICE](NOTICE), and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Contributing

Follow [CONTRIBUTING.md](CONTRIBUTING.md). Contributions use the
[Developer Certificate of Origin](https://developercertificate.org/): sign off
each contribution with `git commit -s`. There is no Contributor License
Agreement to sign. Do not represent trial build results as upstream approval.

NOT AN OFFICIAL MINECRAFT PRODUCT. NOT APPROVED BY OR ASSOCIATED WITH MOJANG OR
MICROSOFT. Minecraft is a trademark of Mojang Synergies AB.
NVIDIA, GeForce, and RTX are trademarks and/or registered trademarks of NVIDIA
Corporation in the U.S. and other countries.
