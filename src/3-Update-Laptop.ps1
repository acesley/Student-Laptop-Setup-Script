param(
    [switch]$Apply
)

# =====================================================================
# Update-Laptop.ps1
# Installs all pending Windows updates (security, quality, and the
# drivers Windows Update recommends) using the built-in Windows Update
# API, the same engine as Settings > Windows Update.
#
#   Without -Apply: only LISTS what's missing (safe preview).
#   With -Apply:    downloads and installs everything.
#
# Run it, restart when told, and run it again until it says
# "fully up to date". New laptops usually need 2-3 rounds.
# =====================================================================

[string]$LogFolder = "C:\ProgramData\StudentLaptopSetup"


# ---------------------------------------------------------------------
# Helper: colored output (same style as the main script)
# ---------------------------------------------------------------------
function Write-Step {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}


# ---------------------------------------------------------------------
# Safety: must be admin, start a log
# ---------------------------------------------------------------------
[Security.Principal.WindowsPrincipal]$CurrentUser = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)
[bool]$IsAdmin = $CurrentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Step "ERROR: Run this as administrator." "Red"
    exit 1
}

if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory | Out-Null
}
[string]$TimeStamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
[string]$LogFile = Join-Path $LogFolder "updates_$TimeStamp.log"
Start-Transcript -Path $LogFile | Out-Null

if ($Apply) {
    Write-Step "=== WINDOWS UPDATE on $env:COMPUTERNAME (installing) ===" "Cyan"
}
else {
    Write-Step "=== WINDOWS UPDATE on $env:COMPUTERNAME (preview only, nothing installs) ===" "Cyan"
}


# ---------------------------------------------------------------------
# Step 0: is a restart from a previous round still pending?
# Installing more updates before restarting often fails, so stop here.
# Microsoft.Update.SystemInfo is another built-in Windows Update object.
# ---------------------------------------------------------------------
$SystemInfo = New-Object -ComObject Microsoft.Update.SystemInfo
if ($SystemInfo.RebootRequired) {
    Write-Step "`nA RESTART is pending from earlier updates." "Yellow"
    Write-Step "Restart the laptop, then run this again." "Yellow"
    Stop-Transcript | Out-Null
    exit 0
}


# ---------------------------------------------------------------------
# Step 1: SEARCH for what's missing
# ---------------------------------------------------------------------
Write-Step "`n[Searching for updates - this can take a few minutes and look frozen]" "Cyan"

# $Session is the connection to Windows Update. Every other step
# (searcher, downloader, installer) is created from it.
$Session = New-Object -ComObject Microsoft.Update.Session
$Searcher = $Session.CreateUpdateSearcher()

try {
    # IsInstalled=0 : not installed yet.  IsHidden=0 : not hidden by a user.
    $SearchResult = $Searcher.Search("IsInstalled=0 and IsHidden=0")
}
catch {
    # Most common cause: no internet connection.
    Write-Step "ERROR: Update search failed. Check the internet connection." "Red"
    Write-Step "Details: $($_.Exception.Message)" "Red"
    Stop-Transcript | Out-Null
    exit 1
}


# ---------------------------------------------------------------------
# Step 2: BUILD THE BASKET (UpdateColl) of updates to install
# The downloader/installer only accept this special list type, not a
# normal PowerShell array, so we fill one up item by item.
# ---------------------------------------------------------------------
$UpdatesToInstall = New-Object -ComObject Microsoft.Update.UpdateColl

foreach ($Update in $SearchResult.Updates) {

    # BrowseOnly = optional update (often optional drivers). Windows
    # wouldn't install these on its own, so we skip them too.
    if ($Update.BrowseOnly) {
        Write-Step "  Skipping optional: $($Update.Title)" "DarkGray"
        continue
    }

    # Some updates need their license accepted or the install fails.
    if (-not $Update.EulaAccepted) {
        $Update.AcceptEula()
    }

    # .Add returns the item's position number; Out-Null hides it.
    $UpdatesToInstall.Add($Update) | Out-Null
    Write-Step "  Found: $($Update.Title)" "Yellow"
}

[int]$UpdateCount = $UpdatesToInstall.Count

if ($UpdateCount -eq 0) {
    Write-Step "`nFULLY UP TO DATE. Nothing left to install." "Green"
    Stop-Transcript | Out-Null
    exit 0
}

Write-Step "`n$UpdateCount update(s) to install." "Cyan"

if (-not $Apply) {
    Write-Step "Preview only. Run 3-Update-Laptop.bat to install them." "Cyan"
    Stop-Transcript | Out-Null
    exit 0
}


# ---------------------------------------------------------------------
# Step 3: DOWNLOAD
# ---------------------------------------------------------------------
Write-Step "`n[Downloading - this is usually the slowest part]" "Cyan"

$Downloader = $Session.CreateUpdateDownloader()
$Downloader.Updates = $UpdatesToInstall

try {
    $Downloader.Download() | Out-Null
}
catch {
    Write-Step "ERROR: Download failed: $($_.Exception.Message)" "Red"
    Stop-Transcript | Out-Null
    exit 1
}

# Only install what actually finished downloading.
$DownloadedUpdates = New-Object -ComObject Microsoft.Update.UpdateColl
foreach ($Update in $UpdatesToInstall) {
    if ($Update.IsDownloaded) {
        $DownloadedUpdates.Add($Update) | Out-Null
    }
    else {
        Write-Step "  Did not download: $($Update.Title)" "Red"
    }
}

if ($DownloadedUpdates.Count -eq 0) {
    Write-Step "Nothing downloaded successfully. Restart and try again." "Red"
    Stop-Transcript | Out-Null
    exit 1
}


# ---------------------------------------------------------------------
# Step 4: INSTALL
# ---------------------------------------------------------------------
Write-Step "`n[Installing $($DownloadedUpdates.Count) update(s) - don't turn the laptop off]" "Cyan"

$Installer = $Session.CreateUpdateInstaller()
$Installer.Updates = $DownloadedUpdates

try {
    $InstallResult = $Installer.Install()
}
catch {
    Write-Step "ERROR: Install failed: $($_.Exception.Message)" "Red"
    Stop-Transcript | Out-Null
    exit 1
}


# ---------------------------------------------------------------------
# Step 5: REPORT each update's result
# ResultCode numbers come from Windows Update's own list.
# ---------------------------------------------------------------------
$ResultNames = @{
    2 = "Installed"
    3 = "Installed with errors"
    4 = "FAILED"
    5 = "Aborted"
}

Write-Step "`n[Results]" "Cyan"
for ([int]$Index = 0; $Index -lt $DownloadedUpdates.Count; $Index++) {
    [string]$Title = $DownloadedUpdates.Item($Index).Title
    [int]$Code = $InstallResult.GetUpdateResult($Index).ResultCode

    [string]$Status = $ResultNames[$Code]
    if (-not $Status) {
        $Status = "Unknown result ($Code)"
    }

    [string]$Color = "Green"
    if ($Code -ne 2) {
        $Color = "Red"
    }
    Write-Step "  $Status : $Title" $Color
}


# ---------------------------------------------------------------------
# Step 6: WHAT NEXT
# ---------------------------------------------------------------------
Write-Step "`n=== Log saved to: $LogFile ===" "Cyan"
if ($InstallResult.RebootRequired) {
    Write-Step "RESTART the laptop, then run 3-Update-Laptop.bat again." "Yellow"
    Write-Step "Repeat until it says FULLY UP TO DATE." "Yellow"
}
else {
    Write-Step "Done. Run it once more to confirm nothing new appeared." "Green"
}

Stop-Transcript | Out-Null
