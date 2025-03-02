#!pwsh
# =============================================================================
#
#  Dotfiles Installer Script for Windows Systems
#
#  Author: AnalogCyan
#  License: Unlicense
#
# =============================================================================

# =============================================================================
# CONFIGURATION
# =============================================================================

# Package lists - empty for now, to be populated later
$WINGET_APPS = @(
  "Microsoft.PowerShell"
  "Microsoft.WindowsTerminal"
  "Microsoft.Edge"
  "Microsoft.PCManager"
  "M2Team.NanaZip"
  "Microsoft.OneDrive"
  "Git.Git"
  "Microsoft.PowerToys"
  "Microsoft.VisualStudioCode"
  "Python.Python3"
  "Canonical.Ubuntu"
  "Microsoft.DevHome"
  "Starship.Starship"
)

# Git configuration
$GIT_USER_NAME = "AnalogCyan"
$GIT_USER_EMAIL = "git@thayn.me"

# Paths
$DOTFILES_DIR = Get-Location
$POWERSHELL_PROFILE_DIR = Split-Path -Parent $PROFILE
$CONFIG_DIR = "$env:USERPROFILE\.config"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Colors for terminal output
$COLOR_RED = 'DarkRed'
$COLOR_GREEN = 'DarkGreen'
$COLOR_YELLOW = 'DarkYellow'
$COLOR_BLUE = 'DarkBlue'

function Write-LogInfo {
  param([string]$Message)
  Write-Host "INFO: " -ForegroundColor $COLOR_BLUE -NoNewline
  Write-Host $Message
}

function Write-LogSuccess {
  param([string]$Message)
  Write-Host "SUCCESS: " -ForegroundColor $COLOR_GREEN -NoNewline
  Write-Host $Message
}

function Write-LogWarning {
  param([string]$Message)
  Write-Host "WARNING: " -ForegroundColor $COLOR_YELLOW -NoNewline
  Write-Host $Message
}

function Write-LogError {
  param([string]$Message)
  Write-Host "ERROR: " -ForegroundColor $COLOR_RED -NoNewline
  Write-Host $Message
}

function Confirm-Action {
  param([string]$Message)
  $response = Read-Host -Prompt "$Message (y/n)"
  return $response -match '^[yY]$'
}

function Install-WingetApp {
  [CmdletBinding()]
  param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]
    $name
  )
  
  Write-LogInfo "Installing $name via Windows Package Manager..."
  $n = winget upgrade --accept-package-agreements --accept-source-agreements --force -e $name
  if ($n -match "No installed package found matching input criteria.") {
    winget install --accept-package-agreements --accept-source-agreements --force -e $name
  }
}

# Function to manage sudo functionality
function Configure-SudoSupport {
  Write-LogInfo "Configuring sudo functionality..."

  # Check Windows version to see if built-in sudo is available
  $WinVer = [System.Environment]::OSVersion.Version
  $SupportsBuiltInSudo = ($WinVer.Major -eq 10 -and $WinVer.Build -ge 25300) -or ($WinVer.Major -ge 11 -and $WinVer.Build -ge 22631)

  if ($SupportsBuiltInSudo) {
    Write-LogInfo "Built-in sudo is supported on this system."
    
    # Check if gsudo is installed and uninstall it
    if (Get-Command "gsudo" -ErrorAction SilentlyContinue) {
      Write-LogInfo "Uninstalling gsudo..."
      winget uninstall gsudo --silent
    }

    # Enable built-in sudo if not already enabled
    $SudoEnabled = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo" -Name "Enabled" -ErrorAction SilentlyContinue).Enabled
    if ($SudoEnabled -ne 1) {
      Start-Process powershell -Verb runAs -ArgumentList "-NoLogo -NoProfile -Command reg add 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo' /v 'Enabled' /t REG_DWORD /d 1 /f" -Wait
      Write-LogSuccess "Enabled built-in sudo!"
    }
    else {
      Write-LogInfo "Built-in sudo is already enabled."
    }
  }
  else {
    Write-LogInfo "Built-in sudo is NOT supported on this version of Windows. Falling back to gsudo."
    if (-not (Get-Command "gsudo" -ErrorAction SilentlyContinue)) {
      Write-LogInfo "Installing gsudo..."
      winget install gerardog.gsudo --silent --accept-package-agreements --accept-source-agreements
    }
    else {
      Write-LogInfo "gsudo is already installed."
    }
  }

  Write-LogSuccess "Sudo configuration completed."
}

# =============================================================================
# INSTALLATION FUNCTIONS
# =============================================================================

function Test-SystemRequirements {
  Write-LogInfo "Checking system requirements..."

  # Check Windows version (Windows 11 or newer)
  $osVersion = [System.Environment]::OSVersion.Version
  if ($osVersion.Major -lt 10 -or ($osVersion.Major -eq 10 -and $osVersion.Build -lt 22000)) {
    Write-LogError "This script requires Windows 11 or newer!"
    exit 1
  }

  # Check if running without admin privileges (preferred)
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
  if ($isAdmin) {
    Write-LogError "Script should not be run as administrator!"
    exit 1
  }

  Write-LogSuccess "System requirements check passed."
}

function Set-SystemConfiguration {
  Write-LogInfo "Configuring system settings..."

  # Virtualization enable check and WSL update
  if ((Get-Command wsl.exe -ErrorAction SilentlyContinue) -and (Get-Command ubuntu.exe -ErrorAction SilentlyContinue)) {
    Write-LogInfo "Configuring WSL..."
    wsl --set-default-version 2
    wsl -- ./install.sh
  }
  elseif (-not (Get-Command hvc.exe -ErrorAction SilentlyContinue) -or (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-LogInfo "Enabling virtualization features (Hyper-V, Sandbox, WSL, etc.)..."
    Start-Process powershell -Verb runAs -ArgumentList "-NoLogo -NoProfile wsl --enable; Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart | Out-Null; Enable-WindowsOptionalFeature -Online -FeatureName HypervisorPlatform -All -NoRestart | Out-Null; Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All -NoRestart | Out-Null" -Wait
  }

  Write-LogSuccess "System configuration completed."
}

function Update-System {
  Write-LogInfo "Ensuring system is up-to-date..."

  $command = 'Get-CimInstance -Namespace "Root\cimv2\mdm\dmmap" -ClassName "MDM_EnterpriseModernAppManagement_AppManagement01" | Invoke-CimMethod -MethodName UpdateScanMethod; if (-not(Get-Command PSWindowsUpdate -ErrorAction SilentlyContinue)) { Install-Module -ErrorAction SilentlyContinue -Name PSWindowsUpdate -Force }; Import-Module PSWindowsUpdate; Install-WindowsUpdate -AcceptAll -IgnoreReboot -MicrosoftUpdate -NotCategory "Drivers" -RecurseCycle 2'
  Start-Process powershell -Verb runAs -ArgumentList "-NoLogo -NoProfile $command" -Wait

  Write-LogSuccess "System update check completed."
}

function Install-PackageManagers {
  Write-LogInfo "Installing package managers..."

  # Install Windows Package Manager
  if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    Write-LogInfo "Installing Windows Package Manager..."
    Start-Process powershell -Verb runAs -ArgumentList "-NoLogo -NoProfile choco install winget -y" -Wait
    refreshenv
  }
  else {
    Write-LogInfo "Windows Package Manager is already installed."
  }

  Write-LogSuccess "Package managers installation completed."
}

function Install-Applications {
  Write-LogInfo "Installing applications..."

  # Install Winget applications
  Write-LogInfo "Installing Windows Package Manager applications..."
  foreach ($app in $WINGET_APPS) {
    Install-WingetApp -name $app
  }

  # Install Terminal-Icons
  Write-LogInfo "Installing Terminal-Icons PowerShell module..."
  if (-not (Get-Module -ListAvailable -Name Terminal-Icons)) {
    Install-Module -Name Terminal-Icons -Repository PSGallery -Force
  }
  else {
    Write-LogInfo "Terminal-Icons module is already installed."
  }

  # Install Starship prompt
  Write-LogInfo "Installing Starship prompt..."
  Install-WingetApp -name "Starship.Starship"

  Write-LogSuccess "Applications installation completed."
}

function Install-PowerShellModules {
  Write-LogInfo "Installing PowerShell modules..."

  # Install PSReadLine
  if (-not (Get-Module -ListAvailable -Name PSReadLine)) {
    Write-LogInfo "Installing PSReadLine..."
    Install-Module -Name PSReadLine -Force
  }
  else {
    Write-LogInfo "PSReadLine is already installed."
  }

  Write-LogSuccess "PowerShell modules installation completed."
}

function Install-StarshipPrompt {
  Write-LogInfo "Configuring Starship prompt..."
    
  # Create config directory if it doesn't exist
  if (-not (Test-Path $CONFIG_DIR)) {
    New-Item -ItemType Directory -Path $CONFIG_DIR -Force | Out-Null
    Write-LogInfo "Created config directory at $CONFIG_DIR"
  }
    
  # Copy starship.toml from dotfiles repo
  $starshipConfigSource = Join-Path $DOTFILES_DIR "starship.toml"
  $starshipConfigDest = Join-Path $CONFIG_DIR "starship.toml"
    
  if (Test-Path $starshipConfigSource) {
    Copy-Item -Path $starshipConfigSource -Destination $starshipConfigDest -Force
    Write-LogSuccess "Copied starship.toml to $starshipConfigDest"
  }
  else {
    Write-LogError "starship.toml not found at $starshipConfigSource"
    Write-LogInfo "Creating fallback configuration..."
    $url = "https://starship.rs/presets/toml/minimal.toml"
    Invoke-WebRequest -Uri $url -OutFile $starshipConfigDest
  }

  # Ensure Starship is installed via winget
  if (-not (Get-Command starship -ErrorAction SilentlyContinue)) {
    Write-LogInfo "Installing Starship via winget..."
    winget install --accept-source-agreements --accept-package-agreements -e Starship.Starship
  }

  Write-LogSuccess "Starship prompt configured."
}

function Install-DotfilesConfigs {
  Write-LogInfo "Installing dotfiles configurations..."

  # Create PowerShell profile directory if it doesn't exist
  if (-not (Test-Path $POWERSHELL_PROFILE_DIR)) {
    New-Item -ItemType Directory -Path $POWERSHELL_PROFILE_DIR -Force | Out-Null
  }

  # Copy PowerShell profile
  $sourcePSProfile = Join-Path $DOTFILES_DIR "Windows\Profile.ps1"
  if (Test-Path $sourcePSProfile) {
    Write-LogInfo "Installing PowerShell profile..."
    Copy-Item -Path $sourcePSProfile -Destination $PROFILE -Force
  }
  else {
    Write-LogWarning "PowerShell profile not found at $sourcePSProfile"
  }

  # Copy Windows Terminal settings
  $terminalSettingsSource = Join-Path $DOTFILES_DIR "Windows\Terminal\settings.json"
  $terminalSettingsDestination = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
  if (Test-Path $terminalSettingsSource) {
    Write-LogInfo "Installing Windows Terminal settings..."
    Copy-Item -Path $terminalSettingsSource -Destination $terminalSettingsDestination -Force
  }
  else {
    Write-LogWarning "Windows Terminal settings not found at $terminalSettingsSource"
  }

  Write-LogSuccess "Dotfiles configurations installed."
}

function Set-GitConfiguration {
  Write-LogInfo "Configuring Git..."

  if (Get-Command git -ErrorAction SilentlyContinue) {
    # Choose appropriate editor
    $editor = if (Get-Command code -ErrorAction SilentlyContinue) {
      "code --wait"
    }
    else {
      "vim"
    }

    # Set Git configuration
    git config --global core.editor $editor
    git config --global user.name $GIT_USER_NAME
    git config --global user.email $GIT_USER_EMAIL

    Write-LogSuccess "Git configuration completed."
  }
  else {
    Write-LogWarning "Git is not installed. Cannot configure Git."
  }
}

function Install-SSHConfig {
  Write-LogInfo "Setting up SSH configuration..."

  $sshPath = "$env:USERPROFILE\.ssh"
  
  # Create .ssh directory if it doesn't exist
  if (-not (Test-Path $sshPath)) {
    New-Item -ItemType Directory -Path $sshPath -Force | Out-Null
    Write-LogInfo "Created SSH directory at $sshPath"
  }

  # TODO: Implement SSH key copy or generation logic here

  Write-LogSuccess "SSH configuration completed."
}

# =============================================================================
# MAIN SCRIPT
# =============================================================================

function Start-Installation {
  # Print banner
  Write-Host "=====================================" -ForegroundColor Cyan
  Write-Host "  Windows Dotfiles Installation Script" -ForegroundColor Cyan
  Write-Host "=====================================" -ForegroundColor Cyan
  Write-Host ""

  # Check if user is aware this script assumes the user is running a fresh up-to-date Windows installation
  Write-Host "This script assumes the user is running a fresh up-to-date Windows installation."
  Write-Host "Please ensure you have backed up all important data before running this script."
  Read-Host -Prompt "Press Enter to continue or Ctrl+C to cancel"

  # Run installation steps
  Test-SystemRequirements
  Configure-SudoSupport
  Set-SystemConfiguration
  Update-System
  Install-PackageManagers
  Install-Applications
  Install-PowerShellModules
  Install-StarshipPrompt
  Install-DotfilesConfigs
  Set-GitConfiguration
  Install-SSHConfig

  # TODO: Additional tasks as noted in the original script
  # - Configure paths
  # - Install Win11 cursors
  # - Configure additional settings

  # Completion message
  Write-Host ""
  Write-Host "=====================================" -ForegroundColor Cyan
  Write-LogSuccess "Dotfiles installation complete!"
  Write-Host "=====================================" -ForegroundColor Cyan
    
  if (Confirm-Action "Would you like to restart your computer now to complete the setup?") {
    Write-LogInfo "Restarting system..."
    Restart-Computer
  }
  else {
    Write-LogInfo "No restart selected. Some changes may require a restart to take effect."
  }
}

# Execute the installation
Start-Installation
