param(
    [switch]$Apply
)


# =====================================================================
# SECTION 1: CONFIGURATION (safe)
# =====================================================================

# --- Time and region ---
[string]$TimeZoneId = "Eastern Standard Time"
[int]$CountryGeoId = 244
[string]$CultureName = "en-US"      # date, time, and number formats

# --- Site-specific settings (kept OUT of git) ---
# School-specific values live in site-config.psd1 next to this script, so
# the code can be shared publicly without revealing which school uses it.
# The repo only has site-config.example.psd1: copy it, rename the copy to
# site-config.psd1, and fill in the real values.
[string]$ConfigFolder = $PSScriptRoot
if (-not $ConfigFolder) {
    $ConfigFolder = (Get-Location).Path
}
[string]$SiteConfigPath = Join-Path $ConfigFolder "site-config.psd1"

if (-not (Test-Path $SiteConfigPath)) {
    # Write-Host, not Write-Step: helper functions aren't defined yet here.
    Write-Host "ERROR: site-config.psd1 not found in $ConfigFolder" -ForegroundColor Red
    Write-Host "Copy site-config.example.psd1, rename it to site-config.psd1, and fill in your values." -ForegroundColor Red
    exit 1
}

# Import-PowerShellDataFile reads a .psd1 file and returns its hashtable.
# It only accepts data (no commands), so it's safe to load.
$SiteConfig = Import-PowerShellDataFile -Path $SiteConfigPath

# Stop early if a required value is missing or empty.
foreach ($RequiredKey in @("SchoolHomeUrl", "CanvasUrl")) {
    if (-not $SiteConfig[$RequiredKey]) {
        Write-Host "ERROR: '$RequiredKey' is missing or empty in site-config.psd1" -ForegroundColor Red
        exit 1
    }
}

# --- Desktop shortcuts ---
# Each shortcut is a small hashtable: Url = the site, Icon = the .ico file
# name inside the icons folder below. Desktop order follows this list.
$Shortcuts = [ordered]@{
    "School Home" = @{ Url = $SiteConfig.SchoolHomeUrl;                     Icon = "school-home.ico" }
    "Canvas"     = @{ Url = $SiteConfig.CanvasUrl;                         Icon = "canvas-lms.ico" }
    "Cengage"    = @{ Url = "https://account.cengage.com/login";           Icon = "cengage.ico" }
    "Outlook"    = @{ Url = "https://outlook.cloud.microsoft/";            Icon = "microsoft-outlook.ico" }
    "Word"       = @{ Url = "https://word.cloud.microsoft/";               Icon = "microsoft-word.ico" }
    "Excel"      = @{ Url = "https://excel.cloud.microsoft/";              Icon = "microsoft-excel.ico" }
    "PowerPoint" = @{ Url = "https://powerpoint.cloud.microsoft/";         Icon = "microsoft-powerpoint.ico" }
}

# Folder (next to this script) that holds the .ico files above.
[string]$IconSourceFolderName = "Student_Laptop_Icons_Pack 2"
# The script copies the icons here so they keep working after the USB
# stick is removed (same idea as the wallpaper).
[string]$IconTargetFolder = "C:\ProgramData\StudentLaptopSetup\Icons"

# The script removes EVERY program published by HP EXCEPT names that
# match a pattern below. These keep drivers, firmware, and the
# function keys (brightness, volume, airplane mode) working.
[string[]]$HpKeepPatterns = @(
    "*Driver*",
    "*Firmware*",
    "*BIOS*",
    "*Hotkey*",
    "*System Event*",    
    "*SystemEvent*",
    "*Programmable Key*",
    "*Wolf*",              
    "*Sure Click*",
    "*Sure Sense*"
)

# Other traditional (Win32) programs to remove, they name have to be EXACT
[string[]]$Win32RemoveList = @(
    "Microsoft 365 - en-us",
    "Microsoft OneDrive",
    "Microsoft Teams",                    # older Teams (classic) installs
    "Microsoft Teams classic",
    "Teams Machine-Wide Installer",       # reinstalls classic Teams for every new account
    "McAfee",
    "McAfee WebAdvisor",
    "McAfee LiveSafe"
)


[string[]]$AppxRemoveList = @(
    "Microsoft.Copilot",
    "Microsoft.MicrosoftOfficeHub",       
    "Microsoft.OutlookForWindows",        
    "Microsoft.Todos",                    
    "MSTeams",                            
    "MicrosoftTeams",                     
    "Microsoft.PowerAutomateDesktop",     
    # General Windows bloat
    "Microsoft.BingNews",
    "Microsoft.BingWeather",
    "Microsoft.BingSearch",
    "Microsoft.GetHelp",
    "Microsoft.Getstarted",
    "Microsoft.MicrosoftSolitaireCollection",
    "Microsoft.WindowsFeedbackHub",
    "Microsoft.ZuneMusic",
    "Microsoft.ZuneVideo",
    "Microsoft.People",
    "Microsoft.SkypeApp",
    "Microsoft.XboxApp",
    "Microsoft.XboxGamingOverlay",
    "Microsoft.XboxGameOverlay",
    "Microsoft.Xbox.TCUI",
    "Microsoft.GamingApp",
    "Microsoft.549981C3F5F10",            # this is rortana
    "Clipchamp.Clipchamp",
    "*CandyCrush*",
    "*Disney*",
    "*DropboxOEM*",                       # Dropbox promo on the taskbar
    "*McAfee*",
    # Every HP Store app. "AD2F1837" is HP's publisher ID, so this
    # pattern catches all of them. $HpKeepPatterns still protects
    # anything hotkey-related.
    "AD2F1837.*"
)
# Deliberately KEPT: Microsoft Store, Edge, Calculator, Photos,
# Notepad, Snipping Tool, Xbox Identity Provider (other apps use it
# to sign in), and Visual C++ Redistributables (programs need them).

# Startup entries to LEAVE ON
[string[]]$StartupKeepPatterns = @(
    "SecurityHealth*"
)

# improves preformance
[bool]$KeepFontSmoothing = $true

#Log location
[string]$LogFolder = "C:\ProgramData\StudentLaptopSetup"

# --- McAfee cleanup tool (MCPR) ---
# McAfee often refuses a normal silent uninstall. If it's still installed
# after Section 5, the script runs McAfee's own removal engine from this
# folder (next to the script). See tools\MCPR\HOW-TO-GET-MCPR.txt.
[string]$McprFolder = Join-Path $ConfigFolder "tools\MCPR"

#School wallpaper
[string]$WallpaperFileName = "wallpaper.png"

# The script copies the image here so the wallpaper keeps working after
# the USB stick / setup folder is gone. Students can read ProgramData.
[string]$WallpaperFolder = "C:\ProgramData\StudentLaptopSetup\Wallpaper"
# How the image fits the screen (Settings > Personalization > Background):
#   "10" = Fill   "6" = Fit   "2" = Stretch   "0" = Center   "22" = Span
[string]$WallpaperStyle = "10"

# --- Windows Update ---
# "Active hours": Windows won't restart the laptop for updates between
# these hours (24-hour clock, max 18 hours apart). Set to school hours.
[int]$ActiveHoursStart = 8     # 8 AM
[int]$ActiveHoursEnd = 22      # 10 PM


# =====================================================================
# SECTION 2: HELPER FUNCTIONS
# =====================================================================

# Prints a colored line so the output is easy to scan.
function Write-Step {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

# THE CORE OF THE DRY-RUN SYSTEM.
# Every change in this script goes through this function. It receives:
#   $Description : plain-English summary of the change
#   $Action      : a [scriptblock], code wrapped in { } that is stored
#                  now and only executed later with the & operator
# Dry run: print the description only.
# -Apply:  run the code. try/catch stops one failure from killing the
#          whole script; it gets reported and the script moves on.
function Invoke-Change {
    param(
        [string]$Description,
        [scriptblock]$Action
    )

    if ($Apply) {
        Write-Step "  [DOING]   $Description" "Green"
        try {
            & $Action
        }
        catch {
            Write-Step "  [FAILED]  $Description : $($_.Exception.Message)" "Red"
        }
    }
    else {
        Write-Step "  [DRY RUN] Would: $Description" "Yellow"
    }
}

# Returns $true if $Text matches ANY pattern in $Patterns.
# Used for the "keep" lists.
function Test-MatchesAny {
    param(
        [string]$Text,
        [string[]]$Patterns
    )
    foreach ($Pattern in $Patterns) {
        if ($Text -like $Pattern) {
            return $true
        }
    }
    return $false
}

# Writes one registry value, creating the key first if it's missing.
# Set-ItemProperty fails if the key doesn't exist, so this saves
# repeating the same "create if missing" check everywhere.
function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = "DWord"
    )
    if (-not (Test-Path $Path)) {
        New-Item -Path $Path -Force | Out-Null
    }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
}

# Works out a SILENT uninstall command for a traditional program, or
# returns $null if there isn't one. Each installed program leaves an
# "UninstallString" in the registry: the exact command Windows runs
# when you click Uninstall. Different installer types need different
# tricks to run with no pop-ups.
function Get-SilentUninstallCommand {
    param(
        $Program
    )
    [string]$UninstallString = $Program.UninstallString
    [string]$QuietString = $Program.QuietUninstallString

    # 1. Some programs provide a ready-made silent command.
    if ($QuietString) {
        return $QuietString
    }

    # 2. MSI installers: the command contains a product code in braces,
    #    like {1234ABCD-...}. -match stores what matched in $Matches.
    #    /x = uninstall, /qn = no window, /norestart = no surprise reboot
    if ($UninstallString -match "msiexec" -and $UninstallString -match "\{[0-9A-Fa-f\-]+\}") {
        [string]$ProductCode = $Matches[0]
        return "msiexec.exe /x $ProductCode /qn /norestart"
    }

    # 3. Microsoft 365 (Click-to-Run). Adding DisplayLevel=False
    #    makes Office's own uninstaller run with no window.
    if ($UninstallString -match "OfficeClickToRun\.exe") {
        return "$UninstallString DisplayLevel=False"
    }

    # 4. OneDrive's uninstaller (/uninstall) is already silent.
    if ($UninstallString -match "OneDriveSetup\.exe") {
        return $UninstallString
    }

    return $null
}

# Applies a wallpaper to the signed-in account RIGHT NOW (no restart).
# Writing the registry alone only takes effect at next sign-in, so this
# calls the Windows API function SystemParametersInfo directly, which is
# exactly what Settings does when you pick a background.
# PowerShell can't call Windows API functions natively, so Add-Type
# compiles a tiny piece of C# that exposes the function from user32.dll.
function Set-DesktopWallpaper {
    param(
        [string]$ImagePath
    )

    # Add-Type fails if the type already exists (e.g. running the script
    # twice in the same PowerShell window), so only add it once.
    if (-not ("WallpaperNative" -as [type])) {
        Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public static class WallpaperNative {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SystemParametersInfo(int uiAction, int uiParam, string pvParam, int fWinIni);
}
"@
    }

    [int]$SPI_SETDESKWALLPAPER = 0x0014   # "set the desktop wallpaper"
    [int]$SPIF_UPDATEINIFILE = 0x01       # save it to the user's registry
    [int]$SPIF_SENDWININICHANGE = 0x02    # tell open windows it changed

    [bool]$Worked = [WallpaperNative]::SystemParametersInfo(
        $SPI_SETDESKWALLPAPER,
        0,
        $ImagePath,
        ($SPIF_UPDATEINIFILE -bor $SPIF_SENDWININICHANGE)
    )

    # Throwing an error makes Invoke-Change's catch report it in red.
    if (-not $Worked) {
        throw "Windows refused to set the wallpaper (SystemParametersInfo returned false)."
    }
}


# =====================================================================
# SECTION 3: SAFETY CHECKS AND LOGGING
# =====================================================================

# --- Must be running as Administrator ---
[Security.Principal.WindowsPrincipal]$CurrentUser = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)
[bool]$IsAdmin = $CurrentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Write-Step "ERROR: Right-click PowerShell > Run as administrator, then try again." "Red"
    exit 1
}

# --- Start logging everything shown on screen ---
if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory | Out-Null
}
[string]$TimeStamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
[string]$LogFile = Join-Path $LogFolder "setup_$TimeStamp.log"
Start-Transcript -Path $LogFile | Out-Null

if ($Apply) {
    Write-Step "=== RUNNING FOR REAL on $env:COMPUTERNAME as $env:USERNAME ===" "Cyan"
}
else {
    Write-Step "=== DRY RUN on $env:COMPUTERNAME as $env:USERNAME (nothing will change) ===" "Cyan"
}

# --- Restore point, so you can roll back if something breaks ---
# System Restore is often OFF on Windows 11 Home, so turn it on first.
if ($Apply) {
    Write-Step "`n[Restore point]" "Cyan"
    try {
        Enable-ComputerRestore -Drive "C:\" -ErrorAction Stop
        Checkpoint-Computer -Description "Before student laptop setup" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Step "  Restore point created." "Green"
    }
    catch {
        Write-Step "  WARNING: No restore point: $($_.Exception.Message)" "Red"
    }
}


# =====================================================================
# SECTION 4: TIME, TIME ZONE, AND COUNTRY
# =====================================================================
Write-Step "`n[Time and region]" "Cyan"

Invoke-Change "Set time zone to '$TimeZoneId'" {
    Set-TimeZone -Id $TimeZoneId
}

Invoke-Change "Set country/region to GeoId $CountryGeoId and formats to $CultureName" {
    Set-WinHomeLocation -GeoId $CountryGeoId
    Set-Culture -CultureInfo $CultureName
}

Invoke-Change "Turn on automatic time sync and sync the clock now" {
    # W32Time is the Windows Time service. Make it start automatically.
    Set-Service -Name "W32Time" -StartupType Automatic
    Start-Service -Name "W32Time"

    # Type = NTP is what Settings' "Set time automatically" toggle sets.
    Set-RegistryValue -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -Name "Type" -Value "NTP" -Type "String"

    # Point it at Microsoft's time server, then force a sync right now.
    # Out-Null hides w32tm's chatty output.
    w32tm /config /manualpeerlist:"time.windows.com,0x9" /syncfromflags:manual /update | Out-Null
    w32tm /resync /force | Out-Null
}


# =====================================================================
# SECTION 5: REMOVE TRADITIONAL PROGRAMS (HP apps, M365, OneDrive, McAfee)
# Installed programs are listed in 3 registry locations:
#   HKLM 64-bit, HKLM 32-bit (WOW6432Node), and HKCU (per-user installs,
#   which is where OneDrive usually lives).
# =====================================================================
Write-Step "`n[Traditional programs]" "Cyan"

[string[]]$UninstallKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

# Read every program, skip entries with no name (hidden system parts).
$AllPrograms = Get-ItemProperty -Path $UninstallKeys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName }

# Build the list of programs to remove:
#   (a) anything published by HP that is NOT on the keep list
#   (b) anything whose name is exactly on $Win32RemoveList
$ProgramsToRemove = @()
foreach ($Program in $AllPrograms) {
    [string]$Name = $Program.DisplayName
    [string]$Publisher = $Program.Publisher

    [bool]$IsHp = ($Publisher -like "HP*") -or ($Publisher -like "Hewlett*")
    [bool]$IsKept = Test-MatchesAny -Text $Name -Patterns $HpKeepPatterns
    [bool]$IsOnList = $Win32RemoveList -contains $Name

    if (($IsHp -and -not $IsKept) -or $IsOnList) {
        $ProgramsToRemove += $Program
    }
    elseif ($IsHp -and $IsKept) {
        Write-Step "  Keeping (driver/hotkey): $Name" "DarkGray"
    }
}

# OneDrive and Office refuse to uninstall while they're running.
Invoke-Change "Close OneDrive and Office if they're open" {
    Get-Process -Name "OneDrive", "WINWORD", "EXCEL", "POWERPNT", "OUTLOOK" -ErrorAction SilentlyContinue |
        Stop-Process -Force
}

[bool]$HasWinget = [bool](Get-Command winget -ErrorAction SilentlyContinue)

foreach ($Program in $ProgramsToRemove) {
    [string]$Name = $Program.DisplayName
    [string]$SilentCommand = Get-SilentUninstallCommand -Program $Program

    if ($SilentCommand) {
        # PLAN A: run the program's own uninstaller silently.
        # cmd /c runs the command string exactly as Windows would.
        Invoke-Change "Uninstall '$Name'" {
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c `"$SilentCommand`"" -Wait -WindowStyle Hidden
        }
    }
    elseif ($HasWinget) {
        # PLAN B: let winget work out how to uninstall it.
        Invoke-Change "Uninstall '$Name' (winget)" {
            winget uninstall --name $Name --exact --silent --accept-source-agreements --disable-interactivity | Out-Null
        }
    }
    else {
        # PLAN C: no silent option. Don't launch a pop-up uninstaller
        # from a script; flag it so you remove it by hand.
        Write-Step "  MANUAL: '$Name' has no silent uninstaller. Remove it in Settings > Apps." "Red"
    }

    # VERIFY: an uninstaller can "finish" without removing anything (McAfee
    # does this). winget and msiexec are native programs, so a failure
    # never reaches Invoke-Change's catch. Re-check the registry instead.
    if ($Apply) {
        $StillThere = Get-ItemProperty -Path $UninstallKeys -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -eq $Name }
        if ($StillThere) {
            Write-Step "            STILL INSTALLED: '$Name'" "Red"
        }
        else {
            Write-Step "            Confirmed removed: '$Name'" "Green"
        }
    }
}
# NOTE: the code inside { } can use $Name and $SilentCommand because
# Invoke-Change runs it IMMEDIATELY, while the loop is still on this
# program. The block reads whatever the variables hold at that moment.


# =====================================================================
# SECTION 5B: McAFEE DEEP CLEAN
# Runs only if McAfee survived Section 5. Uses McAfee's own removal
# engine (mccleanup.exe from MCPR) silently, then removes leftovers:
#   - "ghost" Programs-and-Features entries whose uninstaller is gone
#     (each one is backed up to a .reg file first)
#   - leftover McAfee folders, but only once no McAfee service remains
# =====================================================================
Write-Step "`n[McAfee cleanup]" "Cyan"

# Returns the uninstaller's .exe path from an UninstallString, or "".
# Strings look like:  "C:\Path\uninst.exe" /args   or   C:\Path\uninst.exe /args
function Get-UninstallerPath {
    param(
        [string]$UninstallString
    )
    if ($UninstallString -match '^\s*"([^"]+)"') {
        return $Matches[1]
    }
    if ($UninstallString -match '^\s*(.+?\.exe)') {
        return $Matches[1]
    }
    return ""
}

# $true if McAfee still shows in Programs and Features OR its folder exists.
function Test-McAfeePresent {
    $Entries = Get-ItemProperty -Path $UninstallKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like "McAfee*" }
    [bool]$HasFolder = Test-Path "C:\Program Files\McAfee"
    return ([bool]$Entries -or $HasFolder)
}

[string]$McCleanupExe = Join-Path $McprFolder "mccleanup.exe"

# The component list McAfee's removal wizard passes to mccleanup.exe.
# -v = verbose, -s = silent (no window, no prompts).
[string]$McprArguments = "-p StopServices,MFSY,PEF,MXD,CSP,Sustainability,MOCP,MFP,APPSTATS,Auth,EMproxy,FWdiver,HW,MAS,MAT,MBK,MCPR,McProxy,McSvcHost,VUL,MHN,MNA,MOBK,MPFP,MPFPCU,MPS,SHRED,MPSCU,MQC,MQCCU,MSAD,MSHR,MSK,MSKCU,MWL,NMC,RedirSvc,VS,REMEDIATION,MSC,YAP,TRUEKEY,LAM,PCB,Symlink,SafeConnect,MGS,WMIRemover,RESIDUE -v -s"

if (-not (Test-McAfeePresent)) {
    Write-Step "  McAfee not found. Nothing to clean." "DarkGray"
}
elseif (-not (Test-Path $McCleanupExe)) {
    Write-Step "  McAfee is still installed and $McCleanupExe was not found." "Red"
    Write-Step "  Add the MCPR files (see tools\MCPR\HOW-TO-GET-MCPR.txt), or remove McAfee manually." "Red"
}
else {
    # 1. McAfee's own removal engine. -Wait: it takes several minutes.
    #    -PassThru returns the process so we can read its exit code.
    Invoke-Change "Run McAfee's removal tool silently (takes several minutes)" {
        $McprProcess = Start-Process -FilePath $McCleanupExe -ArgumentList $McprArguments `
            -WorkingDirectory $McprFolder -Wait -PassThru -WindowStyle Hidden
        Write-Step "            mccleanup.exe exit code: $($McprProcess.ExitCode)" "DarkGray"
    }

    # 2. Ghost entries: listed in Programs and Features, but the uninstaller
    #    file no longer exists, so the program is really gone. If the
    #    uninstaller DOES still exist, McAfee is really still installed,
    #    so we leave that entry alone (deleting it would only hide McAfee).
    Invoke-Change "Remove leftover McAfee entries (backed up first)" {
        $McAfeeEntries = Get-ItemProperty -Path $UninstallKeys -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "McAfee*" }

        foreach ($Entry in $McAfeeEntries) {
            [string]$UninstallerPath = Get-UninstallerPath -UninstallString $Entry.UninstallString

            # No full path (e.g. "MsiExec.exe /X{...}") means we can't tell
            # whether it's really gone, so play it safe and leave it.
            if (-not $UninstallerPath -or -not [System.IO.Path]::IsPathRooted($UninstallerPath)) {
                Write-Step "            Can't verify, leaving it: $($Entry.DisplayName)" "Yellow"
                continue
            }

            if (Test-Path -LiteralPath $UninstallerPath) {
                Write-Step "            Still installed (uninstaller exists): $($Entry.DisplayName)" "Red"
                continue
            }

            # Convert-Path turns PowerShell's registry path into the
            # HKEY_LOCAL_MACHINE\... form that reg.exe understands.
            [string]$RegPath = Convert-Path -LiteralPath $Entry.PSPath
            [string]$SafeName = $Entry.PSChildName -replace '[^\w\-]', '_'
            [string]$BackupFile = Join-Path $LogFolder "McAfee-backup-$SafeName.reg"

            reg export $RegPath $BackupFile /y | Out-Null
            Remove-Item -LiteralPath $Entry.PSPath -Recurse -Force
            Write-Step "            Removed ghost entry: $($Entry.DisplayName) (backup: $BackupFile)" "DarkGray"
        }
    }

    # 3. Leftover folders, only if no McAfee service is still running.
    #    Deleting files out from under a running service fails anyway.
    Invoke-Change "Delete leftover McAfee folders" {
        $McAfeeServices = Get-Service -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like "*McAfee*" }

        if ($McAfeeServices) {
            Write-Step "            McAfee services still present; folders kept until after a restart." "Yellow"
        }
        else {
            [string[]]$McAfeeFolders = @(
                "C:\Program Files\McAfee",
                "C:\Program Files\Common Files\McAfee",
                "C:\ProgramData\McAfee"
            )
            foreach ($Folder in $McAfeeFolders) {
                if (Test-Path -LiteralPath $Folder) {
                    Remove-Item -LiteralPath $Folder -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Step "            Deleted folder: $Folder" "DarkGray"
                }
            }
        }
    }

    # 4. Final answer.
    if ($Apply) {
        if (Test-McAfeePresent) {
            Write-Step "  McAfee not fully gone yet. RESTART, then run setup again to finish." "Yellow"
        }
        else {
            Write-Step "  McAfee fully removed." "Green"
        }
    }
}

# =====================================================================
# SECTION 6: REMOVE STORE (AppX) APPS, INCLUDING COPILOT
# Two places per app:
#   1. Installed copy: removes it for accounts that already have it.
#   2. Provisioned copy: the template Windows copies into every NEW
#      account. Skip this and the app returns for the next account.
# =====================================================================
Write-Step "`n[Store apps]" "Cyan"

$AllAppx = Get-AppxPackage -AllUsers
$AllProvisioned = Get-AppxProvisionedPackage -Online

foreach ($AppPattern in $AppxRemoveList) {

    $InstalledMatches = $AllAppx | Where-Object { $_.Name -like $AppPattern }
    foreach ($App in $InstalledMatches) {
        [string]$AppName = $App.Name
        if (Test-MatchesAny -Text $AppName -Patterns $HpKeepPatterns) {
            Write-Step "  Keeping (hotkey/driver app): $AppName" "DarkGray"
            continue
        }
        [string]$FullName = $App.PackageFullName
        Invoke-Change "Remove app $AppName" {
            Remove-AppxPackage -Package $FullName -AllUsers -ErrorAction Stop
        }
    }

    $ProvisionedMatches = $AllProvisioned | Where-Object { $_.DisplayName -like $AppPattern }
    foreach ($Prov in $ProvisionedMatches) {
        if (Test-MatchesAny -Text $Prov.DisplayName -Patterns $HpKeepPatterns) {
            continue
        }
        [string]$ProvName = $Prov.PackageName
        Invoke-Change "Deprovision $($Prov.DisplayName) (blocks reinstall for new accounts)" {
            Remove-AppxProvisionedPackage -Online -PackageName $ProvName -ErrorAction Stop | Out-Null
        }
    }
}

# Hide the Copilot button and turn Copilot off by policy, in case
# Windows Update brings it back.
Invoke-Change "Turn off Copilot and hide its taskbar button" {
    Set-RegistryValue -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0
}

# Hide the Teams "Chat" button on the taskbar (0 = hidden).
Invoke-Change "Hide the Teams Chat button on the taskbar" {
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarMn" -Value 0
}

# Stop OneDrive from reinstalling itself for new accounts. Every new
# account copies the "Default" profile, whose Run key launches
# OneDriveSetup. We load that hidden profile, delete the entry, unload it.
Invoke-Change "Stop OneDrive reinstalling for new accounts" {
    reg load "HKU\DefaultProfile" "C:\Users\Default\NTUSER.DAT" | Out-Null
    reg delete "HKU\DefaultProfile\Software\Microsoft\Windows\CurrentVersion\Run" /v "OneDriveSetup" /f 2>$null | Out-Null
    [GC]::Collect()   # release PowerShell's handle on the file before unloading
    reg unload "HKU\DefaultProfile" | Out-Null
}


# =====================================================================
# SECTION 7: MICROSOFT EDGE (efficiency mode + Edge manages RAM)
# Edge reads "policies" from HKLM\SOFTWARE\Policies\Microsoft\Edge.
# Policies work on Windows 11 Home. Side effect: Edge will show
# "Your browser is managed by your organization". That's normal.
# =====================================================================
Write-Step "`n[Microsoft Edge]" "Cyan"

[string]$EdgePolicy = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"

Invoke-Change "Edge: efficiency mode always on" {
    # 0 = AlwaysActive
    Set-RegistryValue -Path $EdgePolicy -Name "EfficiencyMode" -Value 0
}

Invoke-Change "Edge: sleeping tabs on (unused tabs freed from RAM after 5 min)" {
    Set-RegistryValue -Path $EdgePolicy -Name "SleepingTabsEnabled" -Value 1
    Set-RegistryValue -Path $EdgePolicy -Name "SleepingTabsTimeout" -Value 300   # seconds
}

Invoke-Change "Edge: don't run in the background when closed, no startup boost" {
    # Without these, Edge stays loaded in RAM even when no window is open.
    Set-RegistryValue -Path $EdgePolicy -Name "BackgroundModeEnabled" -Value 0
    Set-RegistryValue -Path $EdgePolicy -Name "StartupBoostEnabled" -Value 0
}


# =====================================================================
# SECTION 8: DISABLE STARTUP APPS
# Startup apps live in two places:
#   - "Run" registry keys (HKCU = this user, HKLM = all users)
#   - Startup FOLDERS (shortcuts dropped into a special folder)
# Windows keeps an on/off switch for each in "StartupApproved". A value
# starting with byte 03 = DISABLED. This is exactly what Task Manager's
# Startup tab does, so anything can be turned back on from there.
# =====================================================================
Write-Step "`n[Startup apps]" "Cyan"

[string]$ApprovedBase = "Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved"
[byte[]]$DisabledValue = @(0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)

# Each entry: where the startup items are, how to list their names,
# and which StartupApproved key holds their on/off switch.
$StartupLocations = @(
    @{ Kind = "Registry"; Source = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run";             ApprovedKey = "HKCU:\$ApprovedBase\Run" },
    @{ Kind = "Registry"; Source = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run";             ApprovedKey = "HKLM:\$ApprovedBase\Run" },
    @{ Kind = "Registry"; Source = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"; ApprovedKey = "HKLM:\$ApprovedBase\Run32" },
    @{ Kind = "Folder";   Source = [Environment]::GetFolderPath("Startup");                            ApprovedKey = "HKCU:\$ApprovedBase\StartupFolder" },
    @{ Kind = "Folder";   Source = [Environment]::GetFolderPath("CommonStartup");                      ApprovedKey = "HKLM:\$ApprovedBase\StartupFolder" }
)

foreach ($Location in $StartupLocations) {

    if (-not (Test-Path $Location.Source)) {
        continue
    }

    # Get the names of the startup items in this location.
    [string[]]$EntryNames = @()
    if ($Location.Kind -eq "Registry") {
        # .Property lists the value NAMES inside a registry key.
        $EntryNames = (Get-Item -Path $Location.Source).Property
    }
    else {
        # In a folder, each file is one startup item (desktop.ini isn't).
        $EntryNames = Get-ChildItem -Path $Location.Source -File |
            Where-Object { $_.Name -ne "desktop.ini" } |
            Select-Object -ExpandProperty Name
    }

    foreach ($EntryName in $EntryNames) {
        if (Test-MatchesAny -Text $EntryName -Patterns $StartupKeepPatterns) {
            Write-Step "  Keeping startup item: $EntryName" "DarkGray"
            continue
        }
        [string]$ApprovedKey = $Location.ApprovedKey
        [string]$NameToDisable = $EntryName
        Invoke-Change "Disable startup item '$EntryName'" {
            Set-RegistryValue -Path $ApprovedKey -Name $NameToDisable -Value $DisabledValue -Type "Binary"
        }
    }
}


# =====================================================================
# SECTION 9: VISUAL EFFECTS = "ADJUST FOR BEST PERFORMANCE"
# Same as System Properties > Advanced > Performance > Settings.
# Per-user settings: they apply to the account running this script.
# They take effect after a restart.
# =====================================================================
Write-Step "`n[Visual effects]" "Cyan"

Invoke-Change "Set visual effects to 'Adjust for best performance'" {
    [string]$Desktop = "HKCU:\Control Panel\Desktop"
    [string]$Advanced = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    # 2 = the "Adjust for best performance" radio button
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2

    # UserPreferencesMask is a bit field: each bit is one checkbox in
    # that window (fade menus, shadows, smooth scrolling...). This
    # value has the animation bits switched off.
    [byte[]]$PerformanceMask = @(0x90, 0x12, 0x03, 0x80, 0x10, 0x00, 0x00, 0x00)
    Set-RegistryValue -Path $Desktop -Name "UserPreferencesMask" -Value $PerformanceMask -Type "Binary"

    # The remaining checkboxes each have their own registry value.
    Set-RegistryValue -Path $Desktop -Name "DragFullWindows" -Value "0" -Type "String"                       # show window contents while dragging
    Set-RegistryValue -Path "$Desktop\WindowMetrics" -Name "MinAnimate" -Value "0" -Type "String"            # animate minimize/maximize
    Set-RegistryValue -Path $Advanced -Name "TaskbarAnimations" -Value 0                                     # taskbar animations
    Set-RegistryValue -Path $Advanced -Name "ListviewAlphaSelect" -Value 0                                   # translucent selection box
    Set-RegistryValue -Path $Advanced -Name "ListviewShadow" -Value 0                                        # shadows under icon labels
    Set-RegistryValue -Path $Advanced -Name "IconsOnly" -Value 1                                             # icons instead of thumbnails
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "EnableAeroPeek" -Value 0           # Peek
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "AlwaysHibernateThumbnails" -Value 0 # save taskbar previews
    Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 0

    # Font smoothing: "2" = on, "0" = off (see $KeepFontSmoothing).
    if ($KeepFontSmoothing) {
        Set-RegistryValue -Path $Desktop -Name "FontSmoothing" -Value "2" -Type "String"
    }
    else {
        Set-RegistryValue -Path $Desktop -Name "FontSmoothing" -Value "0" -Type "String"
    }
}


# =====================================================================
# SECTION 10: SCHOOL WALLPAPER
# Three steps:
#   1. Copy the image from the script's folder to ProgramData (a
#      permanent location every account can read).
#   2. Set it for the signed-in account and apply it immediately.
#   3. Set it in the hidden "Default" profile so NEW accounts get it.
# =====================================================================
Write-Step "`n[Wallpaper]" "Cyan"

# $PSScriptRoot = the folder this script file lives in. It's empty if the
# code was pasted into a console instead of run with -File, so fall back
# to the current folder in that case.
[string]$ScriptFolder = $PSScriptRoot
if (-not $ScriptFolder) {
    $ScriptFolder = (Get-Location).Path
}

[string]$WallpaperSource = Join-Path $ScriptFolder $WallpaperFileName
[string]$WallpaperTarget = Join-Path $WallpaperFolder $WallpaperFileName

if (-not (Test-Path $WallpaperSource)) {
    # Checked even in a dry run, so a missing image is caught before -Apply.
    Write-Step "  SKIPPED: '$WallpaperFileName' not found in $ScriptFolder. Put the image next to the script." "Red"
}
else {
    Invoke-Change "Copy wallpaper to $WallpaperTarget" {
        if (-not (Test-Path $WallpaperFolder)) {
            New-Item -Path $WallpaperFolder -ItemType Directory -Force | Out-Null
        }
        # -Force overwrites an older copy, so re-running updates the image.
        Copy-Item -Path $WallpaperSource -Destination $WallpaperTarget -Force -ErrorAction Stop
    }

    Invoke-Change "Set wallpaper for $env:USERNAME (style $WallpaperStyle) and apply it now" {
        # Style first, so it's used when the wallpaper is applied below.
        # Both are text (REG_SZ) values, not numbers.
        Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value $WallpaperStyle -Type "String"
        Set-RegistryValue -Path "HKCU:\Control Panel\Desktop" -Name "TileWallpaper" -Value "0" -Type "String"

        # 0 = "Picture" in Settings (not Solid color, Slideshow, or Spotlight).
        Set-RegistryValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers" -Name "BackgroundType" -Value 0

        # Writes the Wallpaper registry value AND refreshes the desktop.
        Set-DesktopWallpaper -ImagePath $WallpaperTarget
    }

    # Same technique as the OneDrive step in Section 6: load the Default
    # profile's registry file, write to it, unload it. Every account
    # created later starts as a copy of this profile.
    Invoke-Change "Make the wallpaper the default for NEW accounts" {
        reg load "HKU\DefaultProfile" "C:\Users\Default\NTUSER.DAT" | Out-Null
        # reg.exe is a native program: on failure it sets $LASTEXITCODE
        # instead of throwing, so check it and throw ourselves.
        if ($LASTEXITCODE -ne 0) {
            throw "Could not load the Default profile (reg load exit code $LASTEXITCODE)."
        }
        reg add "HKU\DefaultProfile\Control Panel\Desktop" /v "Wallpaper" /t REG_SZ /d "$WallpaperTarget" /f | Out-Null
        reg add "HKU\DefaultProfile\Control Panel\Desktop" /v "WallpaperStyle" /t REG_SZ /d "$WallpaperStyle" /f | Out-Null
        reg add "HKU\DefaultProfile\Control Panel\Desktop" /v "TileWallpaper" /t REG_SZ /d "0" /f | Out-Null
        [GC]::Collect()   # release PowerShell's handle on the file before unloading
        reg unload "HKU\DefaultProfile" | Out-Null
    }
}


# =====================================================================
# SECTION 11: DESKTOP SHORTCUTS
# A .url file is a plain-text "internet shortcut". It opens in the
# default browser (Edge). Saving to the PUBLIC desktop makes the
# shortcuts appear for every account on the laptop.
# =====================================================================
Write-Step "`n[Desktop shortcuts]" "Cyan"

[string]$PublicDesktop = [Environment]::GetFolderPath("CommonDesktopDirectory")

# $ScriptFolder was worked out in the wallpaper section (Section 10).
[string]$IconSourceFolder = Join-Path $ScriptFolder $IconSourceFolderName
[bool]$HaveIconFolder = Test-Path $IconSourceFolder

if ($HaveIconFolder) {
    # Copy every .ico to ProgramData. The shortcuts point at these copies,
    # so the icons survive after the USB stick is removed.
    Invoke-Change "Copy shortcut icons to $IconTargetFolder" {
        if (-not (Test-Path $IconTargetFolder)) {
            New-Item -Path $IconTargetFolder -ItemType Directory -Force | Out-Null
        }
        # -LiteralPath because the folder name has a space; *.ico only.
        Get-ChildItem -LiteralPath $IconSourceFolder -Filter "*.ico" |
            Copy-Item -Destination $IconTargetFolder -Force -ErrorAction Stop
    }
}
else {
    Write-Step "  NOTE: icon folder '$IconSourceFolderName' not found next to the script. Shortcuts will use the default browser icon." "Red"
}

# .Keys gives the shortcut names; $Shortcuts[$Name] gives that shortcut's
# hashtable, and .Url / .Icon read its two values.
foreach ($ShortcutName in $Shortcuts.Keys) {
    [string]$Url = $Shortcuts[$ShortcutName].Url
    [string]$IconName = $Shortcuts[$ShortcutName].Icon
    [string]$FilePath = Join-Path $PublicDesktop "$ShortcutName.url"

    # A .url file is a small text file in INI format. URL= is the site.
    # IconFile= and IconIndex= are optional and set the picture shown.
    [string]$FileContent = "[InternetShortcut]`r`nURL=$Url`r`n"

    # Only point at an icon that actually exists in the source folder;
    # a missing icon would show as a blank page icon.
    [string]$IconSourcePath = Join-Path $IconSourceFolder $IconName
    if ($HaveIconFolder -and (Test-Path -LiteralPath $IconSourcePath)) {
        [string]$IconTargetPath = Join-Path $IconTargetFolder $IconName
        $FileContent += "IconFile=$IconTargetPath`r`nIconIndex=0`r`n"
        [string]$IconNote = "with icon $IconName"
    }
    else {
        [string]$IconNote = "no icon found, default icon"
    }

    Invoke-Change "Create desktop shortcut '$ShortcutName' -> $Url ($IconNote)" {
        Set-Content -Path $FilePath -Value $FileContent -Encoding ASCII
    }
}

# Windows caches icons. If shortcuts were made by an earlier run, the
# desktop may keep showing the old icon until the cache refreshes.
# ie4uinit.exe -show tells Windows to rebuild it now (a restart also works).
Invoke-Change "Refresh the icon cache so the new icons show" {
    Start-Process -FilePath "ie4uinit.exe" -ArgumentList "-show" -Wait -WindowStyle Hidden
}


# =====================================================================
# SECTION 12: AUTOMATIC UPDATES
# Windows 11 Home updates itself automatically by default. This section
# makes sure nothing has turned that off, sets active hours so updates
# don't restart the laptop mid-class, keeps Store apps auto-updating,
# and starts an update check right now.
# =====================================================================
Write-Step "`n[Automatic updates]" "Cyan"

# wuauserv = Windows Update service. Its normal setting is Manual
# (Windows starts it when needed). Disabled would stop all updates.
Invoke-Change "Make sure the Windows Update service isn't disabled" {
    $UpdateService = Get-Service -Name "wuauserv" -ErrorAction Stop
    if ($UpdateService.StartType -eq "Disabled") {
        Set-Service -Name "wuauserv" -StartupType Manual
        Write-Step "            Windows Update was DISABLED; set back to Manual." "Yellow"
    }
}

# Active hours: the same setting as Settings > Windows Update >
# Advanced options > Active hours. SmartActiveHoursState 0 = use the
# hours we set instead of Windows guessing them.
# ${ } around the name is needed here: "$ActiveHoursStart:00" would be
# read as a scope prefix (like $env:), not the variable followed by ":00".
Invoke-Change "Set update active hours to ${ActiveHoursStart}:00 - ${ActiveHoursEnd}:00" {
    [string]$UxSettings = "HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings"
    Set-RegistryValue -Path $UxSettings -Name "SmartActiveHoursState" -Value 0
    Set-RegistryValue -Path $UxSettings -Name "ActiveHoursStart" -Value $ActiveHoursStart
    Set-RegistryValue -Path $UxSettings -Name "ActiveHoursEnd" -Value $ActiveHoursEnd
}

# Microsoft Store policy: AutoDownload 4 = always auto-update Store apps
# (2 would turn it off). Keeps Edge's helpers, Calculator, etc. current.
Invoke-Change "Keep Microsoft Store apps auto-updating" {
    Set-RegistryValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore" -Name "AutoDownload" -Value 4
}

# UsoClient is the Update Session Orchestrator, the program behind the
# "Check for updates" button. StartScan starts a check and returns right
# away; downloads and installs continue in the background.
Invoke-Change "Start a Windows Update check now (runs in the background)" {
    Start-Process -FilePath "UsoClient.exe" -ArgumentList "StartScan" -WindowStyle Hidden
}


# =====================================================================
# SECTION 13: WRAP UP
# =====================================================================
Write-Step "`n=== Finished. Log saved to: $LogFile ===" "Cyan"
if ($Apply) {
    Write-Step "RESTART the laptop now so every change takes effect." "Cyan"
    Write-Step "After restart, check Settings > Apps for anything marked MANUAL above." "Cyan"
}
else {
    Write-Step "Dry run only. Review the yellow lines, then re-run with -Apply." "Cyan"
}

Stop-Transcript | Out-Null