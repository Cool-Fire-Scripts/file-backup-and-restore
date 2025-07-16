# PowerShell USB 3.2 Saturation Backup Script
$username = $env:USERNAME
$sourceRoot = "C:\Users\$username"

# Detect first mounted USB drive
$usb = Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter } | Select-Object -First 1
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
$fetchedFirefoxProfiles = Get-ChildItem "$env:APPDATA\Mozilla\Firefox\Profiles\*.default-release" -Directory
$fetchedFirefoxProfile = $fetchedFirefoxProfiles[0]
$firefoxSplitPath = Split-Path -Path $fetchedFirefoxProfile -Leaf
$firefoxProfiles = @(
    @{ src = "$fetchedFirefoxProfile"; dest = "AppData\Mozilla\Firefox\Profiles\$firefoxSplitPath"}
)


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
} while ($waitCount -ne 10)