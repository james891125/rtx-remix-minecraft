# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

"""What a player sees running packaging/installer.ps1 from its menu, under Windows PowerShell 5.1 as
packaging/install.bat runs it.

The unofficial trial always selects Prism, regardless of other installed launchers, and rejects an explicit
Microsoft preference. The menu describes the isolated 1.21.4 trial instance.

A double-clicked install.bat owns its console window, which closes when the installer exits. A run that started from
the menu therefore waits for a key first, or its result and any error vanish with the window."""

import os
import re
import subprocess
from pathlib import Path

import pytest

from rtx_tools.benchmark import util

pytestmark = pytest.mark.skipif(os.name != "nt", reason="Windows PowerShell runs the installer")

INSTALLER = util.PROJECT_DIR / "packaging" / "installer.ps1"
HELD = "Window held"
QUEUED = "Queued key read"
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
# Loads the installer's constants and functions without its entry point, gives the mod an older build in each launcher
# named in -Installed, and runs one step: Upgrade and Install select the launcher as those modes do, printing any
# question asked as "Asked: <title>" and the pick, and MainMenu prints each main-menu item as "Item: <label> | <hint>".
# -NoPrism and -NoMs leave Prism or the Microsoft launcher uninstalled. Run runs the entry point with -Mode, as an
# interactive console would: the menu answers -Choice, the chosen
# mode ends as -Outcome says (ok, fail, or throw), the console holds -Queued keys typed ahead, each read of one prints
# QUEUED, and a wait for a fresh key prints HELD.
HARNESS = r"""
param([string]$Installer, [string]$Loaded, [string]$Action, [string]$Installed, [switch]$NoPrism, [switch]$NoMs,
      [string]$Preferred, [string]$Mode, [switch]$Unattended, [string]$Choice, [string]$Outcome, [int]$Queued)
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Installer, [ref]$null, [ref]$null)
$entryPoint = $ast.EndBlock.Statements[-1]
if ($entryPoint -isnot [System.Management.Automation.Language.TryStatementAst]) {
    throw 'installer.ps1 no longer ends with its entry point'
}
$start = $ast.ParamBlock.Extent.EndOffset
$body = $ast.Extent.Text.Substring($start, $entryPoint.Extent.StartOffset - $start)
[IO.File]::WriteAllText($Loaded, $body, [Text.UTF8Encoding]::new($true))
. $Loaded
$mods = @{}
foreach ($launcher in ($Installed -split ',' | Where-Object { $_ })) {
    $mods[$launcher] = 'rtx-remix-renderer-0.0.1.jar'
}
$launchers = [pscustomobject]@{ HasPrism = -not $NoPrism; HasMs = -not $NoMs }
function Invoke-Menu {
    param([string]$Title, [array]$Items, [string]$Footer)
    Write-Host "Asked: $Title"
    return $Items[0].Value
}
switch ($Action) {
    'Upgrade' {
        $detected = [pscustomobject]@{ ModInstalled = $mods }
        $picked = Select-Launcher -State $launchers -DetectedState $detected `
            -BiasToInstalledLauncher -Preferred $Preferred
        Write-Host "Picked: $picked"
    }
    'Install' {
        Write-Host "Picked: $(Select-Launcher -State $launchers -Preferred $Preferred)"
    }
    'Uninstall' {
        Write-Host "Picked: $(Select-LauncherForUninstall -State $launchers -Preferred $Preferred)"
    }
    'MainMenu' {
        function Get-DetectedState {
            [pscustomobject]@{
                ModInstalled = $mods; ModPackage = 'rtx-remix-renderer-0.0.2.jar'
                HasPrism = $launchers.HasPrism; HasMs = $launchers.HasMs
            }
        }
        function Write-DetectedStateBlock { param([pscustomobject]$State) }
        function Invoke-Menu {
            param([string]$Title, [array]$Items, [string]$Footer)
            foreach ($item in $Items) { Write-Host "Item: $($item.Label) | $($item.Hint)" }
        }
        $null = Show-MainMenu
    }
    'Run' {
        function Test-InteractiveHost { return $true }
        function Show-MainMenu { return $Choice }
        function Invoke-InstallOrUpgrade {
            switch ($Outcome) {
                'ok' { return 0 }
                'fail' { Write-Err 'Do not run the installer as Administrator.'; return 1 }
                'throw' { throw 'Download failed.' }
            }
        }
        $script:queuedKeys = $Queued
        function Test-KeyAvailable { return $script:queuedKeys -gt 0 }
        function Read-KeyRaw {
            if ($script:queuedKeys -gt 0) {
                $script:queuedKeys--
                Write-Host 'Queued key read'
            } else {
                Write-Host 'Window held'
            }
            return [ConsoleKeyInfo]::new([char]13, [ConsoleKey]::Enter, $false, $false, $false)
        }
        . ([scriptblock]::Create($entryPoint.Extent.Text))
    }
    default { throw "Unknown action: $Action" }
}
"""


def run_harness(tmp_path: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    harness = tmp_path / "harness.ps1"
    harness.write_text(HARNESS, encoding="ascii")
    command = [
        "powershell",
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(harness),
        "-Installer",
        str(INSTALLER),
        "-Loaded",
        str(tmp_path / "installer-functions.ps1"),
        *arguments,
    ]
    return subprocess.run(command, capture_output=True, encoding="utf-8", errors="replace", check=False)


def run_step(tmp_path: Path, action: str, installed: str, *, prism: bool = True, ms: bool = True) -> str:
    arguments = ["-Action", action, "-Installed", installed]
    if not prism:
        arguments.append("-NoPrism")
    if not ms:
        arguments.append("-NoMs")
    result = run_harness(tmp_path, *arguments)
    assert result.returncode == 0, result.stdout + result.stderr
    assert not result.stderr
    # The menu enters the alternate screen first, so its escape sequence prefixes the first line.
    return ANSI.sub("", result.stdout)


@pytest.mark.parametrize("action", ["Install", "Upgrade", "Uninstall"])
@pytest.mark.parametrize("installed", ["", "Microsoft", "Prism", "Microsoft,Prism"])
@pytest.mark.parametrize("prism", [False, True])
@pytest.mark.parametrize("ms", [False, True])
def test_trial_always_selects_prism_without_a_launcher_prompt(
    tmp_path: Path, action: str, installed: str, prism: bool, ms: bool
):
    output = run_step(tmp_path, action, installed, prism=prism, ms=ms)
    assert "Picked: Prism" in output.splitlines()
    assert "Asked:" not in output


@pytest.mark.parametrize("action", ["Install", "Upgrade", "Uninstall"])
def test_trial_rejects_an_explicit_microsoft_launcher(tmp_path: Path, action: str):
    result = run_harness(tmp_path, "-Action", action, "-Preferred", "Microsoft")
    assert result.returncode != 0
    assert "Microsoft Launcher is disabled in this trial" in result.stderr
    assert "Picked:" not in result.stdout


@pytest.mark.parametrize("action", ["Install", "Upgrade", "Uninstall"])
def test_trial_accepts_an_explicit_prism_launcher(tmp_path: Path, action: str):
    result = run_harness(tmp_path, "-Action", action, "-Preferred", "Prism")
    assert result.returncode == 0, result.stdout + result.stderr
    assert "Picked: Prism" in result.stdout.splitlines()
    assert "Asked:" not in result.stdout


@pytest.mark.parametrize("installed", ["Microsoft", "Prism", "Microsoft,Prism"])
@pytest.mark.parametrize("prism", [False, True])
@pytest.mark.parametrize("ms", [False, True])
def test_menu_describes_reinstalling_the_isolated_trial_instance(tmp_path: Path, installed: str, prism: bool, ms: bool):
    output = run_step(tmp_path, "MainMenu", installed, prism=prism, ms=ms)
    items = [line for line in output.splitlines() if line.startswith("Item: ")]
    assert items[0].startswith("Item: Upgrade |")
    assert "Item: Install | reinstall into the isolated 1.21.4 trial instance" in items
    assert not any("Microsoft" in item or "choose the launcher" in item for item in items)


@pytest.mark.parametrize(("outcome", "code"), [("ok", 0), ("fail", 1), ("throw", 1)])
def test_a_run_chosen_from_the_menu_waits_for_a_key_before_its_window_closes(tmp_path: Path, outcome: str, code: int):
    result = run_harness(tmp_path, "-Action", "Run", "-Choice", "Install", "-Outcome", outcome)
    assert result.returncode == code, result.stdout + result.stderr
    assert "Press any key to close this window." in result.stdout
    assert result.stdout.index("Press any key") < result.stdout.index(HELD)


def test_keys_typed_ahead_do_not_close_the_window(tmp_path: Path):
    # A key pressed during a download, or the Enter after a y/n answer, is still in the console's buffer when the run
    # ends. The wait discards those first and then needs a fresh key.
    result = run_harness(tmp_path, "-Action", "Run", "-Choice", "Install", "-Outcome", "ok", "-Queued", "2")
    assert result.returncode == 0, result.stdout + result.stderr
    assert result.stdout.count(QUEUED) == 2
    assert result.stdout.rindex(QUEUED) < result.stdout.index("Press any key") < result.stdout.index(HELD)


def test_quitting_the_menu_closes_without_waiting(tmp_path: Path):
    result = run_harness(tmp_path, "-Action", "Run", "-Choice", "Quit", "-Outcome", "ok", "-Queued", "1")
    assert result.returncode == 0, result.stdout + result.stderr
    assert HELD not in result.stdout
    assert QUEUED not in result.stdout


@pytest.mark.parametrize("unattended", [False, True])
def test_a_run_given_its_mode_does_not_wait(tmp_path: Path, unattended: bool):
    arguments = ["-Action", "Run", "-Mode", "Install", "-Outcome", "ok", "-Queued", "1"]
    if unattended:
        arguments.append("-Unattended")
    result = run_harness(tmp_path, *arguments)
    assert result.returncode == 0, result.stdout + result.stderr
    assert HELD not in result.stdout
    assert QUEUED not in result.stdout
