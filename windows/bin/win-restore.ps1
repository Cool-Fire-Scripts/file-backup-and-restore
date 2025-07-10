# PowerShell User Data Restore Script (USB → New Machine)
$username = $env:USERNAME
$userRoot = "C:\Users\$username"

# Detect first mounted USB drive
$usb = Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter } | Select-Object -First 1
if (-not $usb) { Write-Error "No USB drive found!"; exit 1 }

$usbRoot = "$($usb.DriveLetter):\$username"

# List of folders to restore
$targets = @(
    @{ src = "Desktop"; dest = "$userRoot\Desktop" },
    @{ src = "Documents"; dest = "$userRoot\Documents" },
    @{ src = "Downloads"; dest = "$userRoot\Downloads" },
    @{ src = "Pictures"; dest = "$userRoot\Pictures" },
    @{ src = "Videos"; dest = "$userRoot\Videos" },
    @{ src = "Music"; dest = "$userRoot\Music" },
    @{ src = "AppData\Firefox"; dest = "$env:APPDATA\Mozilla\Firefox\Profiles" },
    @{ src = "AppData\Chrome"; dest = "$env:LOCALAPPDATA\Google\Chrome\User Data" },
    @{ src = "AppData\Edge"; dest = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" }
)

# Get logical processor count to saturate USB
$threads = (Get-WmiObject Win32_Processor).NumberOfLogicalProcessors

# Robocopy options
# - /MIR Mirrors directory tree
# - /Z Copy in restartable mode (if file copy is interrupted, robocopy can resume without issue)
# - /XA:H Does not copy hidden files
# - /W:1 Seconds to wait between retries
# - /R:1 Number of retries on failed copies
# - /MT:$threads Number of threads to use while copying
# - /NFL Do not log file names
# - /NDL Do not log directory names
# Robocopy flags
$robocopyFlags = "/MIR /Z /XA:H /W:1 /R:1 /MT:$threads /NFL /NDL"

# Confirm before backing up data

$val = 0

while ($val -ne 1) {
    Write-Host = "The backup drive selected is: $($usb.DriveLetter)$($usb.FileSystemLabel)"
    $confirmation = Read-Host "Do you want to begin the backup operation? (y/n)"

    if ($confirmation -eq "y") {
        $val++
    } elseif ($confirmation -eq "n") {
        exit 1
    } else {
        Write-Host "Response must be y/n!"
    }
}

# Restore each folder
$jobs = @()
foreach ($target in $targets) {
    $src = Join-Path $usbRoot $target.src
    $dest = $target.dest

    if (-not (Test-Path $src)) {
        Write-Host "Skipping missing folder on USB: $src"
        continue
    }

    # Ensure destination folder exists
    New-Item -Path $dest -ItemType Directory -Force | Out-Null

    $args = @(
        "`"$src`"",
        "`"$dest`"",
        $robocopyFlags
    )

    # Run robocopy in parallel
    $jobs += Start-Job -ScriptBlock {
        param($a)
        robocopy.exe @a | Out-Null
    } -ArgumentList ($args)
}

Write-Host "Restoring user data to $userRoot ..."

# Wait for jobs to finish
$jobs | Wait-Job | ForEach-Object {
    Receive-Job $_ | Out-Null
    Remove-Job $_
}

Write-Host "Restore complete. User data has been restored to the new machine."