# Student Laptop Setup Script

A PowerShell script that automates the setup of student laptops running Windows 11 Home.

The laptops it targets are entry-level machines (low-end CPU, 4 GB RAM), so the script focuses on
stripping out software students don't need and tuning Windows for performance, then adds
shortcuts to the web apps students actually use.

## What it does

- **Removes bloatware**: OEM utilities, trial antivirus, Microsoft 365 desktop apps, OneDrive,
  Copilot, Teams, and other preinstalled Store apps (students use the web versions)
- **Tunes for performance**: disables startup apps, sets visual effects to "best performance",
  and enables Edge efficiency mode and sleeping tabs
- **Adds desktop shortcuts** with icons for the school's learning platform and Microsoft 365 web apps
- **Applies settings**: time zone, region, automatic time sync, wallpaper, and automatic updates
- **Dry-run by default**: previews every change before anything is applied, and logs each run

## Requirements

- Windows 11 Home (tested on HP laptops)
- Administrator rights
- Windows PowerShell 5.1 (built into Windows)

## Setup

1. Copy `src/site-config.example.psd1` to `src/site-config.psd1` and fill in your organization's URLs.
2. Optional: add `src/wallpaper.png` and a home-page icon (`school-home.ico`) to the icons folder.
   These files are kept out of the repo on purpose.

## Usage

Copy the `src` folder to a USB drive, then on the laptop:

| Step | File | What it does |
|---|---|---|
| Preview | `testing/1-Preview.bat` | Shows what would change, changes nothing |
| Run | `src/2-RUN-SETUP.bat` | Applies all changes (prompts for admin) |

Restart the laptop when the script finishes. Logs are saved to `C:\ProgramData\StudentLaptopSetup`.

## Project structure

```
src/
  BWRM.ps1                      Main script
  2-RUN-SETUP.bat               One-click launcher
  site-config.example.psd1      Template for organization-specific settings
  Student_Laptop_Icons_Pack 2/  Shortcut icons
testing/
  1-Preview.bat                 Dry-run launcher
```

## Notes

Test on one spare laptop before rolling out. The script creates a System Restore point before
making changes.
