# OpenReality CLI installer for Windows
# Usage: irm https://open-reality.com/install.ps1 | iex

$ErrorActionPreference = "Stop"

$Repo = "sinisterMage/Open-Reality"
$BinaryName = "orcli.exe"
$Archive = "orcli-x86_64-windows.zip"
$InstallDir = if ($env:OPENREALITY_INSTALL_DIR) { $env:OPENREALITY_INSTALL_DIR } else { "$env:USERPROFILE\.openreality\bin" }

function Main {
    Write-Host ""
    Write-Host "  OpenReality CLI Installer" -ForegroundColor Green
    Write-Host ""

    $Tag = Get-LatestTag
    Download-And-Install -Tag $Tag
    Setup-Path
    Write-Host ""
    Write-Host "  $BinaryName $Tag installed to $InstallDir\$BinaryName" -ForegroundColor Green
    Write-Host ""
}

function Get-LatestTag {
    Write-Host "  Fetching latest release..."
    $Release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest"
    $Tag = $Release.tag_name
    if (-not $Tag) {
        throw "Could not determine the latest release tag."
    }
    Write-Host "  Latest release: $Tag"
    return $Tag
}

function Download-And-Install {
    param([string]$Tag)

    $Url = "https://github.com/$Repo/releases/download/$Tag/$Archive"
    $TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $TempDir | Out-Null

    try {
        $ZipPath = Join-Path $TempDir $Archive

        Write-Host "  Downloading $Archive..."
        Invoke-WebRequest -Uri $Url -OutFile $ZipPath -UseBasicParsing

        Write-Host "  Extracting..."
        Expand-Archive -Path $ZipPath -DestinationPath $TempDir -Force

        if (-not (Test-Path $InstallDir)) {
            New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        }

        Copy-Item (Join-Path $TempDir $BinaryName) (Join-Path $InstallDir $BinaryName) -Force
    }
    finally {
        Remove-Item -Recurse -Force $TempDir -ErrorAction SilentlyContinue
    }
}

function Setup-Path {
    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")

    if ($UserPath -split ";" | Where-Object { $_ -eq $InstallDir }) {
        return
    }

    $NewPath = "$InstallDir;$UserPath"
    [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")

    # Update current session
    $env:Path = "$InstallDir;$env:Path"

    Write-Host "  Added $InstallDir to user PATH."
    Write-Host "  Restart your terminal to use $BinaryName."
}

Main
