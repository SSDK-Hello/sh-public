$logFile = "C:\Temp\winget_upgrade_log2.txt"

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
        
        $wingetPath = (Get-ChildItem "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" | Select-Object -First 1 -ExpandProperty FullName)
        if ($null -ne $wingetPath) {
            Write-Log "winget.exe found at $wingetPath"
            
            # Check if winget is in PATH
            if ($Env:Path -notcontains $wingetPath) {
                $Env:Path += ";$wingetPath"
                Write-Log "Added winget to PATH"
            }

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
    } else {
        Write-Log "winget is not installed on this system."
        
        # Install winget
        Write-Log "Fetching the latest winget release URL from Microsoft..."
        $latestWingetUrl = (Invoke-WebRequest -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -UseBasicParsing | ConvertFrom-Json).assets[2].browser_download_url
        Write-Log "Latest winget release URL: $latestWingetUrl"
        
        Write-Log "Downloading winget installer..."
        Invoke-WebRequest -Uri $latestWingetUrl -OutFile 'winget.appxbundle'
        Write-Log "winget installer downloaded successfully."
        
        Write-Log "Installing winget..."
        Add-AppxPackage -Path 'winget.appxbundle'
        Write-Log "winget installed successfully."

        # Run winget upgrade command after installation
        Write-Log "Re-checking for winget executable after installation..."
        $wingetPath = (Get-ChildItem "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" | Select-Object -First 1 -ExpandProperty FullName)
        
        if ($null -ne $wingetPath) {
            Write-Log "winget.exe found at $wingetPath after installation"
            
            # Check if winget is in PATH
            if ($Env:Path -notcontains $wingetPath) {
                $Env:Path += ";$wingetPath"
                Write-Log "Added winget to PATH after installation"
            }

            # Retry upgrade command up to 4 times
            $retryCount = 0
            while ($retryCount -lt 4) {
                try {
                    Write-Log "Starting winget upgrade, attempt $($retryCount + 1) after installation"
                    & $wingetPath upgrade --all --accept-package-agreements --accept-source-agreements *>> $logFile
                    Write-Log "Winget upgrade completed successfully after installation"
                    break
                } catch {
                    Write-Log "Winget upgrade attempt $($retryCount + 1) after installation failed: $_"
                    $retryCount++
                    if ($retryCount -eq 4) {
                        Write-Log "Winget upgrade failed after 4 attempts post-installation"
                    }
                }
            }
        } else {
            Write-Log "winget.exe not found after installation"
            Write-Log "Updater requires elevated permissions. Please re-run as the account CTL"
        }
    }
} catch {
    Write-Log "An error occurred during script execution: $_"
}
