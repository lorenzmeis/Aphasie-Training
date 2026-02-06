# deploy.ps1 - Script to build, copy, and deploy the XCmaps application to a VPS

# --- Configuration ---
$ErrorActionPreference = "Stop" # Exit script on any error

# Project root directory (where this script is located)
$ProjectRoot = $PSScriptRoot

# Path to your private key file (.ppk format)
$PrivateKeyPath = "C:\Users\lmeis\source\Putty_ppk\myPrivateKey.ppk" 

# SSH Username for VPS
$SshUser = "root"

# Remote directory on VPS
$RemoteDir = "/home/user/aphasie-trainer"

# Files and directories to copy
$FilesToCopy = @(
    "server.js",
    "package.json",
    "package-lock.json",
    "Dockerfile",
    ".dockerignore"
)
$DirsToCopy = @(
    "public"
)

# --- Helper Functions ---
function Get-EnvVariable {
    param(
        [string]$FilePath = "$ProjectRoot\.env",
        [string]$VariableName
    )
    if (-not (Test-Path $FilePath)) {
        Write-Error ".env file not found at $FilePath"
        exit 1
    }
    $content = Get-Content $FilePath
    # Allow for optional whitespace around the equals sign
    $line = $content | Where-Object { $_ -match "^\s*$VariableName\s*=" } | Select-Object -First 1
    if ($line) {
        # Split on the first '=', take the second part, and trim whitespace
        $val = ($line -split '=', 2)[1].Trim()
        # Remove potential quotes
        $val = $val -replace '^["'']', '' -replace '["'']$', ''
        return $val
    } else {
        Write-Error "Variable $VariableName not found in $FilePath"
        exit 1
    }
}

function Run-Command {
    param(
        [string]$Command,
        [string[]]$Arguments,
        [string]$ErrorMessage
    )
    Write-Host "Running: $Command $($Arguments -join ' ')"
    & $Command $Arguments
    if ($LASTEXITCODE -ne 0) {
        Write-Error "$ErrorMessage (Exit Code: $LASTEXITCODE)"
        exit 1
    }
    Write-Host "Success."
}

# --- Main Script ---

# 1. Read VPS IP from .env
Write-Host "Reading VPS_IP from .env file..."
$VpsIp = Get-EnvVariable -VariableName "VPS_IP"
Write-Host "VPS IP: $VpsIp"

# Construct SSH target string
$SshTarget = "$SshUser@$VpsIp"

# 2. Copy files and directories to VPS
Write-Host "Copying files and directories to ${SshTarget}:${RemoteDir}..."

# Ensure remote directory exists (using plink)
Write-Host "Ensuring remote directory $RemoteDir exists..."
Run-Command "plink" @("-i", $PrivateKeyPath, $SshTarget, "mkdir -p $RemoteDir") "Failed to create remote directory $RemoteDir."

# Copy individual files
foreach ($file in $FilesToCopy) {
    $localPath = Join-Path -Path $ProjectRoot -ChildPath $file
    if (Test-Path $localPath) {
        Run-Command "pscp" @("-i", $PrivateKeyPath, $localPath, "$SshTarget`:$RemoteDir/") "Failed to copy $file."
    } else {
        Write-Warning "File not found, skipping: $localPath"
    }
}

# Copy directories (using -r flag)
foreach ($dir in $DirsToCopy) {
    $localPath = Join-Path -Path $ProjectRoot -ChildPath $dir
    if (Test-Path $localPath) {
        # Normal copy for directories
        Run-Command "pscp" @("-r", "-i", $PrivateKeyPath, $localPath, "$SshTarget`:$RemoteDir/") "Failed to copy directory $dir."
    } else {
        Write-Warning "Directory not found, skipping: $localPath"
    }
}

# 3. Run docker build and run on VPS
Write-Host "Building and running Docker container on VPS..."
$ContainerName = "aphasie-trainer"
$Port = 4000
$RemoteCommand = "cd $RemoteDir && docker build -t $ContainerName . && docker stop $ContainerName 2>/dev/null; docker rm $ContainerName 2>/dev/null; docker run -d --name $ContainerName -p 127.0.0.1:4000:4000 --restart always $ContainerName"
Run-Command "plink" @("-i", $PrivateKeyPath, $SshTarget, $RemoteCommand) "Failed to run Docker commands on VPS."

Write-Host "Testing connection to port 4000 on VPS..." -ForegroundColor Cyan
Run-Command "plink" @("-i", $PrivateKeyPath, $SshTarget, "curl -I http://127.0.0.1:4000") "Failed to connect to port 4000 on VPS."

Write-Host "Deployment script completed successfully!"