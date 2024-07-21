# Define the log file path
$logFile = "C:\Temp\winget_installation_log.txt"

# Create C:\Temp directory if it doesn't exist
if (-not (Test-Path -Path "C:\Temp")) {
    New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
    Write-Output "Created C:\Temp directory."
}

# Create log file if it doesn't exist
if (-not (Test-Path -Path $logFile)) {
    New-Item -ItemType File -Path $logFile -Force | Out-Null
    Write-Output "Created log file at $logFile."
}

# Define a function to write log messages
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
Write-Log "Checking for administrator privileges..."
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Log "This script must be run as an Administrator. Attempting to restart script with elevated permissions..."
    Start-Process powershell "-File $($MyInvocation.MyCommand.Path)" -Verb RunAs
    exit
}
Write-Log "Script is running with administrator privileges."

try {
    Write-Log "Starting script execution..."
    
    Write-Log "Checking if winget is installed..."
    $wingetDir = Get-ChildItem "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe" -ErrorAction SilentlyContinue | 
                 Select-Object -First 1 -ExpandProperty FullName
    
    if ($null -ne $wingetDir -and (Test-Path "$wingetDir\winget.exe")) {
        Write-Log "winget is installed at $wingetDir"
    } else {
        Write-Log "winget is not installed on this system. Proceeding with installation..."
        
        # Install winget system-wide
        Write-Log "Fetching the latest winget release URL from Microsoft..."
        $latestWingetUrl = (Invoke-WebRequest -Uri 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' -UseBasicParsing | 
                            ConvertFrom-Json).assets[2].browser_download_url
        Write-Log "Latest winget release URL: $latestWingetUrl"
        
        Write-Log "Downloading winget installer..."
        Invoke-WebRequest -Uri $latestWingetUrl -OutFile 'winget.msixbundle'
        Write-Log "winget installer downloaded successfully."
        
        Write-Log "Installing winget system-wide..."
        try {
            $process = Start-Process -FilePath "DISM.EXE" -ArgumentList "/Online", "/Add-ProvisionedAppxPackage", 
                       "/PackagePath:`"$PWD\winget.msixbundle`"", "/SkipLicense" -NoNewWindow -PassThru -Wait
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

        # Find the new winget directory
        $wingetDir = Get-ChildItem "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe" | 
                     Select-Object -First 1 -ExpandProperty FullName
    }

    # Ensure winget directory is found
    if ($null -ne $wingetDir -and (Test-Path "$wingetDir\winget.exe")) {
        Write-Log "winget executable found at $wingetDir\winget.exe"

        # Create new directory for winget
        $newWingetDir = "C:\winget"
        if (-not (Test-Path -Path $newWingetDir)) {
            New-Item -ItemType Directory -Path $newWingetDir -Force | Out-Null
            Write-Log "Created new directory for winget at $newWingetDir"
        } else {
            Write-Log "Directory $newWingetDir already exists."
        }
        
        # Copy all contents from old winget directory to new directory
        Write-Log "Copying winget files from $wingetDir to $newWingetDir..."
        Copy-Item -Path "$wingetDir\*" -Destination "$newWingetDir" -Recurse -Force
        Write-Log "Winget files copied successfully."

        # Set permissions for all users
        Write-Log "Setting permissions for all users on winget..."
        icacls "$newWingetDir" /grant Users:F
        icacls "$newWingetDir\winget.exe" /grant Users:F
        Write-Log "Permissions set successfully for all users on $newWingetDir and winget.exe"
        
        # Ensure winget directory is in the PATH
        $path = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
        if ($path -notcontains $newWingetDir) {
            [System.Environment]::SetEnvironmentVariable("Path", "$path;$newWingetDir", [System.EnvironmentVariableTarget]::Machine)
            Write-Log "Winget directory added to system PATH."
        } else {
            Write-Log "Winget directory is already in the system PATH."
        }

        # Method 3: CD to directory and run winget
        $retryCount = 0
        $maxRetries = 4
        while ($retryCount -lt $maxRetries) {
            try {
                Write-Log "Starting winget upgrade (Method 3), attempt $($retryCount + 1) of $maxRetries"
                Push-Location $newWingetDir
                Write-Log "Changed directory to $newWingetDir"
                
                $wingetOutput = & .\winget.exe upgrade --all --accept-package-agreements --accept-source-agreements 2>&1
                $wingetOutput | Out-File -FilePath "winget_output.txt" -Append
                
                Write-Log "Winget upgrade command executed. Output saved to winget_output.txt"
                Pop-Location
                Write-Log "Changed directory back to original location"
                
                Write-Log "Winget upgrade completed successfully (Method 3)"
                break
            } catch {
                Write-Log "Winget upgrade attempt $($retryCount + 1) failed (Method 3): $_"
                $retryCount++
                if ($retryCount -eq $maxRetries) {
                    Write-Log "Winget upgrade failed after $maxRetries attempts (Method 3)"
                } else {
                    Write-Log "Retrying in 5 seconds..."
                    Start-Sleep -Seconds 5
                }
            }
        }

    } else {
        Write-Log "winget executable not found. Please check the installation manually."
    }
} catch {
    $errorMessage = $_.Exception.Message
    $errorStackTrace = $_.Exception.StackTrace
    Write-Log "An error occurred: $errorMessage"
    Write-Log "Stack Trace: $errorStackTrace"
}

Write-Log "Script execution completed."
