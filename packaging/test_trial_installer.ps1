# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Offline isolation regression tests for the Windows 1.21.4 trial installer.
.DESCRIPTION
    Runs under Windows PowerShell 5.1 without Pester. Loads only top-level
    assignments and function definitions through the PowerShell AST, never the
    installer entry point. All filesystem fixtures live in a new temporary
    directory. Network and application launches are forbidden by test stubs.
#>
[CmdletBinding()]
param([string]$Installer = (Join-Path $PSScriptRoot 'installer.ps1'))

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Run these tests under Windows PowerShell 5.1 on Windows.' }
$installerPath = (Resolve-Path -LiteralPath $Installer).ProviderPath
$sourceDir = Split-Path -Parent $installerPath
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('rtx-trial-isolation-tests-' + [guid]::NewGuid().ToString('N'))
$savedEnvironment = @{}
foreach ($name in @('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP')) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
$script:Checks = 0
$script:Junctions = New-Object 'System.Collections.Generic.List[string]'

function Assert-True {
    param([bool]$Condition, [string]$Label)
    if (-not $Condition) { throw "FAIL: $Label" }
    $script:Checks++
}

function Assert-Throws {
    param([scriptblock]$Action, [string]$Label, [string]$MessagePattern = '.')
    $failure = $null
    try { & $Action | Out-Null } catch { $failure = $_.Exception.Message }
    if (-not $failure) { throw "FAIL: $Label did not refuse the unsafe action." }
    if ($failure -notmatch $MessagePattern) { throw "FAIL: $Label failed for an unexpected reason: $failure" }
    $script:Checks++
}

function Write-TestFile {
    param([string]$Path, [string]$Content = 'must remain unchanged')
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
}

function Get-TestTree {
    param([string]$Root)
    $full = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    return (@(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        '{0}|{1}' -f $_.FullName.Substring($full.Length), (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    }) -join "`n")
}

function New-TestInstance {
    param([string]$Root, [string]$Minecraft = '1.21.4', [string]$Loader = '0.16.9')
    $instance = Join-Path $Root $script:PRISM_INSTANCE_NAME
    Write-TestFile -Path (Join-Path $instance 'instance.cfg') -Content "InstanceType=OneSix`nname=Test`n"
    $pack = @{
        formatVersion = 1
        components = @(
            @{ uid = 'net.minecraft'; version = $Minecraft }
            @{ uid = 'net.fabricmc.fabric-loader'; version = $Loader }
        )
    }
    Write-TestFile -Path (Join-Path $instance 'mmc-pack.json') -Content ($pack | ConvertTo-Json -Depth 8)
    New-Item -ItemType Directory -Path (Join-Path $instance '.minecraft') -Force | Out-Null
    return $instance
}

function New-TestJunction {
    param([string]$Path, [string]$Target)
    New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
    New-Item -ItemType Directory -Path $Target -Force | Out-Null
    New-Item -ItemType Junction -Path $Path -Target $Target | Out-Null
    $script:Junctions.Add($Path)
}

function New-TestJar {
    param([string]$Path, [string]$Minecraft = '1.21.4', [string]$Version = "$($script:APP_VERSION)-test",
          [switch]$NoNative, [string[]]$Architectures = @('win64', 'arm64'))
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $metadata = @{ id = 'rtx-remix-renderer'; version = $Version; depends = @{ minecraft = $Minecraft } }
    $entries = @{ 'fabric.mod.json' = ($metadata | ConvertTo-Json -Depth 8) }
    if (-not $NoNative) {
        foreach ($arch in $Architectures) {
            foreach ($name in @('d3d9.dll', 'remixbridge.dll')) {
                $entries["native/remix-sdk-$arch/$name"] = 'non-executable test payload'
            }
        }
    }
    $zip = [IO.Compression.ZipFile]::Open($Path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $entries.Keys) {
            $entry = $zip.CreateEntry($name)
            $writer = [IO.StreamWriter]::new($entry.Open(), [Text.UTF8Encoding]::new($false))
            try { $writer.Write($entries[$name]) } finally { $writer.Dispose() }
        }
    } finally { $zip.Dispose() }
}

try {
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    foreach ($name in @('APPDATA', 'LOCALAPPDATA', 'TEMP', 'TMP')) {
        $path = Join-Path $testRoot $name
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        [Environment]::SetEnvironmentVariable($name, $path, 'Process')
    }

    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($installerPath, [ref]$tokens, [ref]$parseErrors)
    Assert-True -Condition ($parseErrors.Count -eq 0) -Label 'Installer parses without errors'
    $definitions = @($ast.EndBlock.Statements | Where-Object {
        $_ -is [Management.Automation.Language.AssignmentStatementAst] -or
        $_ -is [Management.Automation.Language.FunctionDefinitionAst]
    } | ForEach-Object { $_.Extent.Text }) -join "`r`n"
    $loaded = Join-Path $testRoot 'installer-functions.ps1'
    [IO.File]::WriteAllText($loaded, $definitions, [Text.UTF8Encoding]::new($true))
    . $loaded
    $ErrorActionPreference = 'Stop'
    $script:Unattended = $true
    $script:SkipHashCheck = $false
    $script:PrismDataDir = $null

    # Any unexpected work outside the filesystem fixture must fail loudly.
    function Invoke-WebRequest { throw 'FORBIDDEN: network access in isolation tests.' }
    function Invoke-RestMethod { throw 'FORBIDDEN: network access in isolation tests.' }
    function Invoke-VerifiedDownload { throw 'FORBIDDEN: downloads in isolation tests.' }
    function Start-Process { throw 'FORBIDDEN: application launch in isolation tests.' }
    function Find-PrismExe { return $null }
    function Invoke-Menu { throw 'FORBIDDEN: interactive prompt in isolation tests.' }

    foreach ($name in @('Assert-TrialPath', 'Assert-TrialMcDir', 'Assert-TrialPrismInstance', 'Assert-TrialPackage')) {
        Assert-True -Condition ([bool](Get-Command $name -CommandType Function -ErrorAction SilentlyContinue)) -Label "$name exists"
    }
    Assert-True -Condition ($script:MC_VERSION -eq '1.21.4') -Label 'Minecraft version is 1.21.4'
    Assert-True -Condition ($script:PRISM_INSTANCE_NAME -match '1\.21\.4' -and $script:PRISM_INSTANCE_NAME -match '(?i)trial') -Label 'Trial instance has a distinct versioned label'
    Assert-True -Condition (@($script:PRISM_INSTANCE_LEGACY_NAMES).Count -eq 0) -Label 'No legacy stable instance migration'
    $stableManaged = Join-Path $env:LOCALAPPDATA 'RtxRemixMinecraft'
    foreach ($path in @($script:PRISM_PORTABLE_DIR, $script:MANAGED_JDK_DIR)) {
        Assert-True -Condition (-not [IO.Path]::GetFullPath($path).StartsWith($stableManaged + '\', [StringComparison]::OrdinalIgnoreCase)) -Label 'Managed trial dependency does not share the stable root'
        Assert-True -Condition ([IO.Path]::GetFullPath($path).StartsWith($env:LOCALAPPDATA + '\', [StringComparison]::OrdinalIgnoreCase)) -Label 'Managed dependency stays inside test LOCALAPPDATA'
    }

    $prismData = Join-Path $env:APPDATA 'PrismLauncher'
    $script:PrismDataDir = $prismData
    New-Item -ItemType Directory -Path $prismData -Force | Out-Null
    $expectedMc = Join-Path $prismData "instances\$($script:PRISM_INSTANCE_NAME)\.minecraft"
    Assert-True -Condition ((Get-McDirForLauncher -Launcher Prism -PrismDataDir $prismData) -eq $expectedMc) -Label 'Prism resolves only the trial instance'
    Assert-Throws -Action { Get-McDirForLauncher -Launcher Microsoft -PrismDataDir $prismData } -Label 'Microsoft game directory is unavailable' -MessagePattern 'Prism|Microsoft|trial'
    $both = [pscustomobject]@{ HasPrism = $true; HasMs = $true; ModInstalled = @{ Prism = 'trial.jar'; Microsoft = 'stable.jar' } }
    Assert-True -Condition ((Select-Launcher -State $both -Unattended) -eq 'Prism') -Label 'Prism remains the only automatic launcher'
    foreach ($forbidden in @('Microsoft', 'Both')) {
        Assert-Throws -Action { Select-Launcher -State $both -Preferred $forbidden -Unattended } -Label "Reject install launcher $forbidden" -MessagePattern 'Prism|Microsoft|trial|Both'
        Assert-Throws -Action { Select-LauncherForUninstall -State $both -Preferred $forbidden -Unattended } -Label "Reject uninstall launcher $forbidden" -MessagePattern 'Prism|Microsoft|trial|Both'
    }
    foreach ($command in @('Initialize-MicrosoftLauncher', 'Set-MsLauncherProfileName', 'Write-MsLauncherJvmArgs')) {
        Assert-Throws -Action { & $command } -Label "$command cannot mutate a Microsoft profile" -MessagePattern 'Prism|Microsoft|trial'
    }

    # Protect all original locations with real byte-for-byte sentinels.
    $protectedRoots = @(
        (Join-Path $env:APPDATA '.minecraft'),
        (Join-Path $prismData 'instances\NVIDIA RTX Remix for Minecraft'),
        (Join-Path $prismData 'instances\NVIDIA RTX Remix'),
        (Join-Path $prismData 'instances\RTX Remix 1.21.1 (Fabric)'),
        $stableManaged
    )
    foreach ($root in $protectedRoots) {
        foreach ($relative in @(
            'mods\rtx-remix-renderer-stable.jar', 'mods\fabric-api-stable.jar', 'remix-sdk\d3d9.dll',
            'options.txt', 'rtx.conf', 'saves\keep\level.dat', 'instance.cfg', 'mmc-pack.json',
            '.minecraft\mods\rtx-remix-renderer-stable.jar', '.minecraft\mods\fabric-api-stable.jar',
            '.minecraft\remix-sdk\d3d9.dll', '.minecraft\options.txt', '.minecraft\rtx.conf',
            '.minecraft\saves\keep\level.dat', 'jdk-21\bin\java.exe', 'PrismLauncher\prismlauncher.exe'
        )) {
            Write-TestFile -Path (Join-Path $root $relative)
        }
    }
    Write-TestFile -Path (Join-Path $env:APPDATA '.minecraft\launcher_profiles.json') -Content '{"profiles":{"keep":{"name":"Original"}}}'
    $before = @{}
    foreach ($root in $protectedRoots) { $before[$root] = Get-TestTree -Root $root }
    Assert-True -Condition (-not (Get-LauncherState).HasMs) -Label 'Detection ignores the existing Microsoft launcher'
    Assert-Throws -Action { Assert-TrialMcDir -McDir (Join-Path $env:APPDATA '.minecraft') } -Label 'Shared Microsoft directory is rejected' -MessagePattern 'trial|instance|Prism|directory|path'
    $uninitializedMc = Join-Path $testRoot "uninitialized\$($script:PRISM_INSTANCE_NAME)\.minecraft"
    Assert-Throws -Action { Assert-TrialMcDir -McDir $uninitializedMc } -Label 'A missing trial instance cannot bypass initialization' -MessagePattern 'trial|instance|Prism|directory|path|initialized'

    # Existing incomplete or incompatible trial directories must fail before writes.
    $invalidRoot = Join-Path $testRoot 'invalid-instances'
    foreach ($case in @(
        @{ Name = 'minecraft-1211'; Minecraft = '1.21.1'; Loader = '0.16.9' },
        @{ Name = 'wrong-loader'; Minecraft = '1.21.4'; Loader = '0.15.0' }
    )) {
        $instance = New-TestInstance -Root (Join-Path $invalidRoot $case.Name) -Minecraft $case.Minecraft -Loader $case.Loader
        $snapshot = Get-TestTree -Root $instance
        Assert-Throws -Action { Initialize-PrismInstance -InstanceDir $instance } -Label "Reject $($case.Name) before reusing it" -MessagePattern 'Minecraft|Fabric|1\.21\.4|trial|version|loader'
        Assert-True -Condition ((Get-TestTree -Root $instance) -ceq $snapshot) -Label "$($case.Name) remains byte-identical"
    }
    foreach ($case in @('missing-pack', 'malformed-pack', 'missing-config', 'duplicate-minecraft')) {
        $instance = New-TestInstance -Root (Join-Path $invalidRoot $case)
        $packPath = Join-Path $instance 'mmc-pack.json'
        if ($case -eq 'missing-pack') { Remove-Item -LiteralPath $packPath -Force }
        elseif ($case -eq 'malformed-pack') { Write-TestFile -Path $packPath -Content '{bad json' }
        elseif ($case -eq 'missing-config') { Remove-Item -LiteralPath (Join-Path $instance 'instance.cfg') -Force }
        else {
            $duplicatePack = Get-Content -LiteralPath $packPath -Raw | ConvertFrom-Json
            $duplicatePack.components += [pscustomobject]@{ uid = 'net.minecraft'; version = '1.21.4' }
            Write-TestFile -Path $packPath -Content ($duplicatePack | ConvertTo-Json -Depth 8)
        }
        $snapshot = Get-TestTree -Root $instance
        Assert-Throws -Action { Initialize-PrismInstance -InstanceDir $instance } -Label "Reject $case before reusing it" -MessagePattern 'pack|JSON|trial|instance|parse|invalid|Minecraft'
        Assert-True -Condition ((Get-TestTree -Root $instance) -ceq $snapshot) -Label "$case remains byte-identical"
    }

    $trialInstance = Split-Path -Parent $expectedMc
    Initialize-PrismInstance -InstanceDir $trialInstance
    $manifest = Get-Content -LiteralPath (Join-Path $trialInstance 'mmc-pack.json') -Raw | ConvertFrom-Json
    Assert-True -Condition (@($manifest.components | Where-Object { $_.uid -eq 'net.minecraft' -and $_.version -eq '1.21.4' }).Count -eq 1) -Label 'Fresh instance pins Minecraft 1.21.4'
    Assert-TrialPrismInstance -InstanceDir $trialInstance
    $fresh = Get-TestTree -Root $trialInstance
    Initialize-PrismInstance -InstanceDir $trialInstance
    Assert-True -Condition ((Get-TestTree -Root $trialInstance) -ceq $fresh) -Label 'Reusing a valid trial is idempotent'

    # Use a non-executable dummy JAR and the real migration helper. No native
    # library or game is loaded. This tests actual copy/prune/remove targeting.
    $script:SCRIPT_DIR = Join-Path $testRoot 'distribution'
    New-Item -ItemType Directory -Path (Join-Path $script:SCRIPT_DIR 'mods') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceDir 'migrate_resource_packs.ps1') -Destination $script:SCRIPT_DIR
    $dummyJar = Join-Path $script:SCRIPT_DIR 'mods\rtx-remix-renderer-trial-test.jar'
    New-TestJar -Path $dummyJar
    Assert-TrialPackage -Jar $dummyJar
    foreach ($case in @('wrong-minecraft', 'stable-version', 'lightweight')) {
        $badJar = Join-Path $testRoot "$case.jar"
        if ($case -eq 'wrong-minecraft') { New-TestJar -Path $badJar -Minecraft '1.21.1' }
        elseif ($case -eq 'stable-version') { New-TestJar -Path $badJar -Version '0.1.0-stable' }
        else { New-TestJar -Path $badJar -NoNative }
        Assert-Throws -Action { Assert-TrialPackage -Jar $badJar } -Label "Reject $case package" -MessagePattern 'Package|trial|runtime'
    }
    $wrongArchJar = Join-Path $testRoot 'wrong-architecture.jar'
    $wrongArch = if (Test-HostIsArm64) { 'win64' } else { 'arm64' }
    New-TestJar -Path $wrongArchJar -Architectures @($wrongArch)
    Assert-Throws -Action { Assert-TrialPackage -Jar $wrongArchJar } -Label 'Reject native payload for another architecture' -MessagePattern 'Package|runtime'
    Assert-True -Condition ((Get-DistModJar) -eq $dummyJar) -Label 'Exactly one packaged runtime mod is selected'
    $extraJar = Join-Path $script:SCRIPT_DIR 'mods\rtx-remix-renderer-extra.jar'
    New-TestJar -Path $extraJar
    Assert-Throws -Action { Get-DistModJar } -Label 'Ambiguous release package is rejected' -MessagePattern 'Ambiguous'
    Remove-Item -LiteralPath $extraJar -Force
    Write-TestFile -Path (Join-Path $expectedMc 'mods\rtx-remix-renderer-prior-trial.jar')
    Write-TestFile -Path (Join-Path $expectedMc 'mods\unrelated.jar')
    Write-TestFile -Path (Join-Path $expectedMc 'saves\keep\level.dat')
    Install-ModFiles -McDir $expectedMc
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $expectedMc 'mods\rtx-remix-renderer-trial-test.jar')) -Label 'Trial mod installs in trial only'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $expectedMc 'mods\rtx-remix-renderer-prior-trial.jar'))) -Label 'Prior trial mod is replaced'
    Remove-ModArtifacts -McDir $expectedMc -Launcher Prism
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $expectedMc 'mods\unrelated.jar')) -Label 'Unrelated trial mod remains'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $expectedMc 'saves\keep\level.dat')) -Label 'Trial worlds survive normal uninstall'
    Assert-Throws -Action { Install-ModFiles -McDir (Join-Path $env:APPDATA '.minecraft') } -Label 'Low-level mod install rejects shared directory' -MessagePattern 'trial|instance|Prism|directory|path'
    Assert-Throws -Action { Remove-ModArtifacts -McDir (Join-Path $env:APPDATA '.minecraft') -Launcher Microsoft } -Label 'Low-level uninstall rejects Microsoft' -MessagePattern 'trial|instance|Prism|Microsoft|directory|path'

    # Both an ancestor junction and an internal mods junction can otherwise
    # turn a correctly named trial directory into writes to a stable install.
    $junctionTarget = Join-Path $testRoot 'junction-target'
    Write-TestFile -Path (Join-Path $junctionTarget 'must-keep.txt')
    $junctionSnapshot = Get-TestTree -Root $junctionTarget
    $ancestor = Join-Path $testRoot 'linked-ancestor'
    New-TestJunction -Path $ancestor -Target $junctionTarget
    Assert-Throws -Action { Assert-TrialPath -Path (Join-Path $ancestor 'not-created\mods') } -Label 'Junction ancestor is rejected' -MessagePattern 'reparse|junction|link'
    $danglingTarget = Join-Path $testRoot 'removed-junction-target'
    $dangling = Join-Path $testRoot 'dangling-junction'
    New-TestJunction -Path $dangling -Target $danglingTarget
    [IO.Directory]::Delete($danglingTarget)
    Assert-Throws -Action { Assert-TrialPath -Path (Join-Path $dangling 'not-created\mods') } -Label 'Dangling junction ancestor is rejected' -MessagePattern 'reparse|junction|link'
    $linkedInstance = New-TestInstance -Root (Join-Path $testRoot 'linked-instance')
    $linkedMc = Join-Path $linkedInstance '.minecraft'
    New-TestJunction -Path (Join-Path $linkedMc 'mods') -Target $junctionTarget
    Assert-Throws -Action { Install-ModFiles -McDir $linkedMc } -Label 'Junction mods directory is rejected before install' -MessagePattern 'reparse|junction|link'
    Assert-Throws -Action { Remove-ModArtifacts -McDir $linkedMc -Launcher Prism } -Label 'Junction mods directory is rejected before uninstall' -MessagePattern 'reparse|junction|link'
    Assert-Throws -Action { Remove-PrismInstance -DataDir (Join-Path $testRoot 'linked-parent') -InstanceName '..\escape' } -Label 'Arbitrary instance names cannot be removed' -MessagePattern 'trial|instance|Prism|directory|path|name'
    Assert-True -Condition ((Get-TestTree -Root $junctionTarget) -ceq $junctionSnapshot) -Label 'Junction target remains byte-identical'

    $stableTemp = Join-Path $env:TEMP 'rtx-remix-installer-old-stable'
    Write-TestFile -Path (Join-Path $stableTemp 'keep.txt')
    (Get-Item -LiteralPath $stableTemp).LastWriteTime = (Get-Date).AddDays(-3)
    Initialize-Session
    Remove-Session
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $stableTemp 'keep.txt')) -Label 'Trial temp cleanup does not sweep stable installer sessions'

    foreach ($root in $protectedRoots) {
        Assert-True -Condition ((Get-TestTree -Root $root) -ceq $before[$root]) -Label "Original files remain byte-identical: $root"
    }
    Write-Host "PASS: $($script:Checks) trial installer isolation assertions. No network, game launch, or real user install."
} finally {
    # Remove the junction object itself before recursive fixture cleanup.
    foreach ($junction in $script:Junctions) {
        try { [IO.Directory]::Delete($junction) } catch [IO.DirectoryNotFoundException] { }
    }
    foreach ($name in $savedEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
