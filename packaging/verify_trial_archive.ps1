# SPDX-FileCopyrightText: Copyright (c) 2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

<#
.SYNOPSIS
    Verifies the Windows x64 Minecraft 1.21.4 trial archive and writes its SHA-256.
#>
[CmdletBinding()]
param(
    [string]$ArchivePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem

$repoRoot = Split-Path -Parent $PSScriptRoot
$versionLines = @(Get-Content -LiteralPath (Join-Path $repoRoot 'gradle.properties') | Where-Object {
    $_ -match '^mod_version='
})
if ($versionLines.Count -ne 1) { throw 'Expected one mod_version in gradle.properties.' }
$baseVersion = $versionLines[0].Substring('mod_version='.Length).Trim()
if ($baseVersion -notmatch '-trial\.1\.21\.4(?:[-.]|$)') {
    throw "The checkout is not configured for the 1.21.4 trial: $baseVersion"
}
if (-not $ArchivePath) {
    $archives = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'build/distributions') `
        -Filter "rtx-remix-renderer-$baseVersion-*-win64.zip" -File)
    if ($archives.Count -ne 1) {
        throw "Expected exactly one Windows x64 trial ZIP, found $($archives.Count)."
    }
    $ArchivePath = $archives[0].FullName
}
$archiveFile = Get-Item -LiteralPath $ArchivePath
$expectedName = '^rtx-remix-renderer-' + [regex]::Escape($baseVersion) + '-\d{12}-[0-9a-f]{7}(-dirty)?-win64\.zip$'
if ($archiveFile.Name -notmatch $expectedName) {
    throw "Not a Windows x64 archive of this trial version: $($archiveFile.Name)"
}

function Get-RequiredEntry {
    param($Archive, [string]$Name)
    $entries = @($Archive.Entries | Where-Object { $_.FullName -ceq $Name })
    if ($entries.Count -ne 1 -or $entries[0].Length -eq 0) {
        throw "Expected one non-empty archive entry: $Name"
    }
    return $entries[0]
}

function Read-ArchiveText {
    param($Archive, [string]$Name)
    $entry = Get-RequiredEntry -Archive $Archive -Name $Name
    $stream = $entry.Open()
    $reader = New-Object System.IO.StreamReader($stream)
    try { return $reader.ReadToEnd() }
    finally { $reader.Dispose(); $stream.Dispose() }
}

function Assert-PackagedFile {
    param($Archive, [string]$EntryName, [string]$SourcePath)
    $entry = Get-RequiredEntry -Archive $Archive -Name $EntryName
    $stream = $entry.Open()
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $packagedHash = [BitConverter]::ToString($sha256.ComputeHash($stream)).Replace('-', '')
    } finally { $sha256.Dispose(); $stream.Dispose() }
    $sourceHash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
    if ($packagedHash -cne $sourceHash) {
        throw "Packaged file differs from the checkout: $EntryName"
    }
}

$release = [System.IO.Compression.ZipFile]::OpenRead($archiveFile.FullName)
$temporaryJar = Join-Path ([System.IO.Path]::GetTempPath()) ("trial-archive-" + [Guid]::NewGuid() + '.jar')
try {
    $outerFiles = @{
        'install.bat' = 'packaging/install.bat'
        'installer.ps1' = 'packaging/installer.ps1'
        'migrate_resource_packs.ps1' = 'packaging/migrate_resource_packs.ps1'
        'INSTALLER_REFERENCE.md' = 'packaging/INSTALLER_REFERENCE.md'
        'README.md' = 'packaging/INSTALL.md'
        'LICENSE' = 'LICENSE'
        'NOTICE' = 'NOTICE'
        'THIRD_PARTY_NOTICES.md' = 'THIRD_PARTY_NOTICES.md'
    }
    foreach ($name in $outerFiles.Keys) {
        Assert-PackagedFile -Archive $release -EntryName $name `
            -SourcePath (Join-Path $repoRoot $outerFiles[$name])
    }
    $licensesRoot = Join-Path $repoRoot 'packaging/licenses'
    foreach ($license in Get-ChildItem -LiteralPath $licensesRoot -File -Recurse) {
        $relativeName = $license.FullName.Substring($licensesRoot.Length + 1).Replace('\', '/')
        Assert-PackagedFile -Archive $release -EntryName "packaging/licenses/$relativeName" `
            -SourcePath $license.FullName
    }

    $modEntries = @($release.Entries | Where-Object { $_.FullName -match '^mods/[^/]+\.jar$' })
    if ($modEntries.Count -ne 1) {
        throw "Expected exactly one mod JAR in the trial ZIP, found $($modEntries.Count)."
    }
    $expectedJarName = "mods/$($archiveFile.BaseName).jar"
    if ($modEntries[0].FullName -cne $expectedJarName) {
        throw "Trial JAR and ZIP versions differ: $($modEntries[0].FullName)"
    }
    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($modEntries[0], $temporaryJar)
    $jar = [System.IO.Compression.ZipFile]::OpenRead($temporaryJar)
    try {
        $metadata = (Read-ArchiveText -Archive $jar -Name 'fabric.mod.json') | ConvertFrom-Json
        if ($metadata.id -cne 'rtx-remix-renderer' -or $metadata.depends.minecraft -cne '1.21.4') {
            throw 'The packaged mod is not the Minecraft 1.21.4 RTX Remix trial.'
        }
        if ("rtx-remix-renderer-$($metadata.version)" -cne $archiveFile.BaseName) {
            throw 'The packaged mod version does not match the trial archive filename.'
        }
        foreach ($entryName in @(
            'native/remix-sdk-win64/d3d9.dll',
            'native/remix-sdk-win64/remixbridge.dll',
            'native/remix-sdk-win64/remixbridge.pdb',
            'native/rtx.conf',
            'native/textures/overcast_thunderstorm_bc6u.dds',
            'native/textures/water_normals_flipbook.dds',
            'com/nvidia/rtxremix/minecraft/RtxRemixMod.class'
        )) {
            $null = Get-RequiredEntry -Archive $jar -Name $entryName
        }
        if (@($jar.Entries | Where-Object { $_.FullName -like 'native/remix-sdk-arm64/*' }).Count -ne 0) {
            throw 'The Windows x64 trial unexpectedly includes an ARM64 runtime.'
        }
    } finally { $jar.Dispose() }
} finally {
    $release.Dispose()
    if (Test-Path -LiteralPath $temporaryJar) { Remove-Item -LiteralPath $temporaryJar -Force }
}

$archiveHash = (Get-FileHash -LiteralPath $archiveFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
$checksumPath = $archiveFile.FullName + '.sha256'
[System.IO.File]::WriteAllText($checksumPath, "$archiveHash  $($archiveFile.Name)`n", [System.Text.Encoding]::ASCII)
Write-Output "Verified trial archive: $($archiveFile.Name)"
Write-Output "SHA-256: $archiveHash"
