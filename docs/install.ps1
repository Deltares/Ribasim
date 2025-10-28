<#
.SYNOPSIS
    Ribasim install script.
.DESCRIPTION
    This script is used to install Ribasim on Windows from the command line.
    The installation directory can be customized by setting the RIBASIM_HOME environment variable.
.LINK
    https://ribasim.org
#>

Set-StrictMode -Version Latest

$RibasimVersion = 'v2025.6.0'
$RibasimHome = "$Env:USERPROFILE\.ribasim"

function Publish-Env {
    if (-not ("Win32.NativeMethods" -as [Type])) {
        Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @"
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
"@
    }

    $HWND_BROADCAST = [IntPtr] 0xffff
    $WM_SETTINGCHANGE = 0x1a
    $result = [UIntPtr]::Zero

    [Win32.Nativemethods]::SendMessageTimeout($HWND_BROADCAST,
        $WM_SETTINGCHANGE,
        [UIntPtr]::Zero,
        "Environment",
        2,
        5000,
        [ref] $result
    ) | Out-Null
}

function Write-Env {
    param(
        [String] $name,
        [String] $val,
        [Switch] $global
    )

    $RegisterKey = if ($global) {
        Get-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    }
    else {
        Get-Item -Path 'HKCU:'
    }

    $EnvRegisterKey = $RegisterKey.OpenSubKey('Environment', $true)
    if ($null -eq $val) {
        $EnvRegisterKey.DeleteValue($name)
    }
    else {
        $RegistryValueKind = if ($val.Contains('%')) {
            [Microsoft.Win32.RegistryValueKind]::ExpandString
        }
        elseif ($EnvRegisterKey.GetValue($name)) {
            $EnvRegisterKey.GetValueKind($name)
        }
        else {
            [Microsoft.Win32.RegistryValueKind]::String
        }
        $EnvRegisterKey.SetValue($name, $val, $RegistryValueKind)
    }
    Publish-Env
}

function Get-Env {
    param(
        [String] $name,
        [Switch] $global
    )

    $RegisterKey = if ($global) {
        Get-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    }
    else {
        Get-Item -Path 'HKCU:'
    }

    $EnvRegisterKey = $RegisterKey.OpenSubKey('Environment')
    $RegistryValueOption = [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
    $EnvRegisterKey.GetValue($name, $null, $RegistryValueOption)
}

# Check for environment variable overrides
if ($Env:RIBASIM_HOME) {
    $RibasimHome = $Env:RIBASIM_HOME
}

$REPO_URL = "https://github.com/Deltares/Ribasim"
$DOWNLOAD_URL = "$REPO_URL/releases/download/$RibasimVersion/ribasim_windows.zip"

Write-Host "This script will automatically download and install Ribasim ($RibasimVersion) for you."
Write-Host "Getting it from this url: $DOWNLOAD_URL"
Write-Host "The binary will be installed into '$RibasimHome'"

# Check PowerShell version
If (($PSVersionTable.PSVersion.Major) -lt 5) {
    throw @"
Error: PowerShell 5 or later is required to install Ribasim.
Upgrade PowerShell:

    https://docs.microsoft.com/en-us/powershell/scripting/setup/installing-windows-powershell

"@
}

# Check architecture - Ribasim only supports x64
try {
    $a = [System.Reflection.Assembly]::LoadWithPartialName("System.Runtime.InteropServices.RuntimeInformation")
    $t = $a.GetType("System.Runtime.InteropServices.RuntimeInformation")
    $p = $t.GetProperty("OSArchitecture")
    $arch = $p.GetValue($null).ToString()

    if ($arch -ne "X64") {
        throw "Error: Ribasim only supports x64 Windows systems. Detected architecture: $arch"
    }
}
catch {
    # Fallback for older .NET versions
    if (-not [System.Environment]::Is64BitOperatingSystem) {
        throw "Error: Ribasim only supports 64-bit (x64) Windows systems."
    }
    # If it's 64-bit but we can't determine the specific architecture, proceed with a warning
    Write-Warning "Could not determine exact CPU architecture. Ribasim requires x64 (Intel/AMD 64-bit)."
}

# Safety check: require that the directory name contains "ribasim"
# to avoid accidental deletions when RIBASIM_HOME is set incorrectly
$DirectoryName = Split-Path -Leaf $RibasimHome
if (-not $DirectoryName.ToLower().Contains("ribasim")) {
    throw "Error: Installation directory name must contain 'ribasim'. Current: '$RibasimHome'"
}

$TEMP_FILE = [System.IO.Path]::GetTempFileName()
$ZIP_FILE = $TEMP_FILE + ".zip"

try {
    Write-Host "Downloading Ribasim..."
    Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $ZIP_FILE

    # Create the install directory if it doesn't exist
    if (Test-Path -Path $RibasimHome) {
        Write-Host "Removing existing installation..."
        Remove-Item -Path $RibasimHome -Recurse -Force
    }

    New-Item -ItemType Directory -Path $RibasimHome | Out-Null

    Write-Host "Extracting Ribasim..."
    # Extract to temporary location first
    $TempExtract = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
    New-Item -ItemType Directory -Path $TempExtract | Out-Null
    Expand-Archive -Path $ZIP_FILE -DestinationPath $TempExtract -Force

    # Move contents from ribasim_windows.zip/ribasim/ to RibasimHome
    $ExtractedRibasimDir = Join-Path $TempExtract "ribasim"
    if (Test-Path -Path $ExtractedRibasimDir) {
        Get-ChildItem -Path $ExtractedRibasimDir | Move-Item -Destination $RibasimHome -Force
    } else {
        throw "Error: Expected 'ribasim' directory not found in zip archive"
    }

    # Clean up temp extraction directory
    Remove-Item -Path $TempExtract -Recurse -Force -ErrorAction SilentlyContinue

    # Verify ribasim.exe exists
    $RibasimExe = Join-Path $RibasimHome "ribasim.exe"
    if (!(Test-Path -Path $RibasimExe)) {
        throw "Error: ribasim.exe not found in the extracted archive"
    }

    Write-Host "Successfully installed Ribasim"
}
catch {
    Write-Host "Error: Failed to download or install Ribasim"
    Write-Host $_.Exception.Message
    exit 1
}
finally {
    # Clean up temporary files
    if (Test-Path -Path $TEMP_FILE) {
        Remove-Item -Path $TEMP_FILE -ErrorAction SilentlyContinue
    }
    if (Test-Path -Path $ZIP_FILE) {
        Remove-Item -Path $ZIP_FILE -ErrorAction SilentlyContinue
    }
}

# Add Ribasim to PATH if the folder is not already in the PATH variable
$PATH = Get-Env 'PATH'
if ($PATH -notlike "*$RibasimHome*") {
    Write-Host "Adding $RibasimHome to PATH"
    # For future sessions
    Write-Env -name 'PATH' -val "$RibasimHome;$PATH"
    # For current session
    $Env:PATH = "$RibasimHome;$PATH"
    Write-Host ""
    Write-Host "Ribasim has been added to your PATH."
}
else {
    Write-Host "Ribasim is already in PATH"
}

Write-Host ""
Write-Host "Installation complete! Run 'ribasim --help' to get started."
