$logFile = "C:\Temp\winget1239.txt"

# Create C:\Temp directory if it doesn't exist
if (-not (Test-Path -Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp" | Out-Null
}

# Create log file if it doesn't exist
if (-not (Test-Path -Path $logFile)) {
    New-Item -ItemType File -Path $logFile | Out-Null
}

function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string] $Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $Message"
    Add-Content -Path $logFile -Value $logMessage
    Write-Host $logMessage
}

# Check for administrator privileges
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Log "This script must be run as an Administrator. Please re-run this script as an Administrator."
    Write-Log "Attempting to restart script with elevated permissions..."
    Start-Process powershell "-File $($MyInvocation.MyCommand.Path)" -Verb RunAs
    exit
}

try {
    Write-Log "Starting script execution..."
    
    Write-Log "Checking if winget is installed..."
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-Log "winget command is available."
    } else {
        Write-Log "winget is not installed on this system."
        
        # Install winget system-wide
        Write-Log "Fetching the latest winget release URL from Microsoft..."
        $latestWingetUrl = (Invoke-WebRequest -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -UseBasicParsing | ConvertFrom-Json).assets[2].browser_download_url
        Write-Log "Latest winget release URL: $latestWingetUrl"
        
        Write-Log "Downloading winget installer..."
        Invoke-WebRequest -Uri $latestWingetUrl -OutFile 'winget.msixbundle'
        Write-Log "winget installer downloaded successfully."
        
        Write-Log "Installing winget system-wide..."
        try {
            $process = Start-Process -FilePath "DISM.EXE" -ArgumentList "/Online", "/Add-ProvisionedAppxPackage", "/PackagePath:`"$PWD\winget.msixbundle`"", "/SkipLicense" -NoNewWindow -PassThru -Wait
            if ($process.ExitCode -eq 0) {
                Write-Log "winget installed successfully system-wide."
            } else {
                Write-Log "DISM.EXE failed to install winget. Exit code: $($process.ExitCode)"
                throw "DISM.EXE installation failed"
            }
        } catch {
            Write-Log "Failed to install winget: $_"
            throw
        }

        # Add winget to system PATH
        $wingetPath = "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe"
        $systemPath = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine)
        if ($systemPath -notlike "*$wingetPath*") {
            [Environment]::SetEnvironmentVariable("PATH", $systemPath + ";$wingetPath", [EnvironmentVariableTarget]::Machine)
            Write-Log "Added winget to system PATH"
        }
    }

    # Find winget executable
    $wingetPath = (Get-ChildItem "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" | Select-Object -First 1 -ExpandProperty FullName)
    
    if ($null -ne $wingetPath) {
        Write-Log "winget.exe found at $wingetPath"
        
        # Retry upgrade command up to 4 times
        $retryCount = 0
        while ($retryCount -lt 4) {
            try {
                Write-Log "Starting winget upgrade, attempt $($retryCount + 1)"
                & $wingetPath upgrade --all --accept-package-agreements --accept-source-agreements *>> $logFile
                Write-Log "Winget upgrade completed successfully"
                break
            } catch {
                Write-Log "Winget upgrade attempt $($retryCount + 1) failed: $_"
                $retryCount++
                if ($retryCount -eq 4) {
                    Write-Log "Winget upgrade failed after 4 attempts"
                }
            }
        }
    } else {
        Write-Log "winget.exe not found in the expected directory"
        Write-Log "Updater requires elevated permissions. Please re-run as the account CTL"
    }
} catch {
    Write-Log "An error occurred during script execution: $_"
}
