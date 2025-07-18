# Help Desk File Backup Script
# Copyright (c) 2025 Arthur Taft
$username = $env:USERNAME
$sourceRoot = "C:\Users\$username"


function Show-DriveMenu {
    param (
        $systemDrives 
    )
    $driveNum = 1
    Write-Host "=============== System Drives ============="
    foreach ($drive in $systemDrives) {
        Write-Host "[$driveNum] $($drive.DriveLetter):    -   $($drive.FileSystemLabel)"
        $driveNum++
    }
}

function Get-OneDriveFolders {
    param (
        $folder
    )


}


# Get all mounted drives
$systemDrives = Get-Volume | Where-Object { $_.DriveLetter }

# Present drive menu, have user select backup drive
do {
    Show-DriveMenu($systemDrives)
    $selectedDrive = (Read-Host "Which drive would you like to back up to?") -as [int]
    if ($selectedDrive -is [int]) {
        $usb = $systemDrives[$selectedDrive - 1]
        $selected = $true
    } elseif ($selectedDrive -eq "q") {
        exit 1
    } else {
        Write-Host "Input must be a number!"
    }
} until ($selected -eq $true)

if (-not $usb) { Write-Error "No USB drive found!"; exit 1 }

$destRoot = "$($usb.DriveLetter):\$username"
New-Item -Path $destRoot -ItemType Directory -Force | Out-Null

# Check for chrome profiles
$chromeProfileCheck = Test-Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Profile 1"

$chromeProfiles = @()

# If a user has one chrome profile, it's likely that they have more...
# Iterate over chrome profiles until there are none left
if ($chromeProfileCheck -eq $true) {
    $i = 1
    do {
        if ($i -ne 1) {
            $chromeProfiles += @{ src = "$chromeProfile"; dest = "Chrome Profile $i" }
        }
        $chromeProfile = Join-Path -Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Profile " -ChildPath "$i"
        $chromeProfileCheck = Test-Path "$chromeProfile"
    } while ($chromeProfileCheck -eq $true)
}

# Check for Edge Profiles
$edgeProfileCheck = Test-Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Profile 1"

$edgeProfiles = @()

# If a user has one edge profile, it's likely that they have more...
# Iterate over edge profiles until there are none left
if ($edgeProfileCheck -eq $true) {
    $j = 1
    do {
        if ($j -ne 1) {
            $edgeProfiles += @{ src = "$edgeProfile"; dest = "Edge Profile $j" }
        }
        $edgeProfile = Join-Path -Path "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Profile " -ChildPath "$j"
        $edgeProfileCheck = Test-Path "$edgeProfile"
    } while ($edgeProfileCheck -eq $true)
}

# Check for firefox Profiles
$firefoxProfileCheck = Test-Path "$usbRoot\AppData\Mozilla\Firefox\Profiles\*.default-release"

if ($firefoxProfileCheck -eq $true) {
    $fetchedFirefoxProfiles = Get-ChildItem "$usbRoot\AppData\Mozilla\Firefox\Profiles\*.default-release" -Directory
    $fetchedFirefoxProfile = $fetchedFirefoxProfiles[0]
    $firefoxSplitPath = Split-Path -Path $fetchedFirefoxProfile -Leaf
    $firefoxProfiles = @(
        @{ src = "$fetchedFirefoxProfile"; dest = "$env:APPDATA\Mozilla\Firefox\Profiles\$firefoxSplitPath"}
    )
}

# Check for OneDrive paths
$oneDriveDesktopCheck = Test-Path "$env:OneDrive\Desktop\*"

$oneDriveDesktop = @()

if ($oneDriveDesktopCheck -eq $true) {
    $oneDriveDesktop += @{ src = "$env:OneDrive\Desktop"; dest = "Desktop" }
}

$oneDriveDocumentsCheck = Test-Path "$env:OneDrive\Documents\*"

$oneDriveDocuments = @()

if ($oneDriveDocumentsCheck -eq $true) {
    $oneDriveDocuments += @{ src = "$env:OneDrive\Documents"; dest = "Documents" }
}

$oneDriveDownloadsCheck = Test-Path "$env:OneDrive\Downloads\*"

$oneDriveDownloads = @()

if ($oneDriveDownloadsCheck -eq $true) {
    $oneDriveDownloads += @{ src = "$env:OneDrive\Downloads"; dest = "Downloads" }
}

$oneDrivePicturesCheck = Test-Path "$env:OneDrive\Pictures\*"

$oneDrivePictures = @()

if ($oneDrivePicturesCheck -eq $true) {
    $oneDrivePictures += @{ src = "$env:OneDrive\Pictures"; dest = "Pictures" }
}



# List of folders to backup: [ Source Folder, Destination Subfolder ]
$targets = @(
    @{ src = "$sourceRoot\Desktop"; dest = "Desktop" },
    @{ src = "$sourceRoot\Documents"; dest = "Documents" },
    @{ src = "$sourceRoot\Downloads"; dest = "Downloads" },
    @{ src = "$sourceRoot\Pictures"; dest = "Pictures" },
    @{ src = "$sourceRoot\Videos"; dest = "Videos" },
    @{ src = "$sourceRoot\Music"; dest = "Music" }
)

$targets += $chromeProfiles

$targets += $edgeProfiles

$targets += $firefoxProfiles

# Get number of threads to use in copy operation
$threads = (Get-CimInstance -ClassName Win32_Processor).NumberOfLogicalProcessors

# Robocopy options
# - /MIR Mirrors directory tree
# - /Z Copy in restartable mode (if file copy is interrupted, robocopy can resume without issue)
# - /XA:H Does not copy hidden files
# - /W:1 Seconds to wait between retries
# - /R:1 Number of retries on failed copies
# - /MT:$threads Number of threads to use while copying
$robocopyFlags = @(
    "/MIR",
    "/XA:H",
    "/W:1",
    "/R:1",
    "/Z",
    "/MT:$threads"
) 

# Confirm before backing up data

$val = 0

while ($val -ne 1) {
    Write-Host "The backup drive selected is: $($usb.DriveLetter): $($usb.FileSystemLabel)"
    $confirmation = Read-Host "Do you want to begin the backup operation? (y/n)"

    if ($confirmation -eq "y") {
        $val++
    } elseif ($confirmation -eq "n") {
        exit 1
    } else {
        Write-Host "Response must be y/n!"
    }
}

# Backup each folder in parallel

foreach ($t in $targets) {
    if (-not (Test-Path $t.src)) {
        Write-Host "Skipping (not found): $($t.src)"; continue
    }
    $dst = Join-Path $destRoot $t.dest
    New-Item -ItemType Directory -Path $dst -Force | Out-Null
    robocopy.exe $t.src $dst $robocopyFlags
}

Write-Host "Backup complete. You may now eject your USB drive."
Write-Host "Press any key to continue"
$waitCount = 0
do {
    if ([Console]::KeyAvailable) {
        $keyInfo = [Console]::ReadKey($true)
        break
    }
    Write-Host '.' -NoNewline
    Start-Sleep -Seconds 6
    $waitCount++
} until ($waitCount -eq 10)