# PowerShell USB 3.2 Saturation Backup Script
$username = $env:USERNAME
$sourceRoot = "C:\Users\$username"

# Detect first mounted USB drive
$usb = Get-Volume | Where-Object { $_.DriveType -eq 'Removable' -and $_.DriveLetter } | Select-Object -First 1
if (-not $usb) { Write-Error "No USB drive found!"; exit 1 }

$destRoot = "$($usb.DriveLetter):\UserBackup_$username"
New-Item -Path $destRoot -ItemType Directory -Force | Out-Null

# List of folders to backup: [ Source Folder, Destination Subfolder ]
$targets = @(
    @{ src = "$sourceRoot\Desktop"; dest = "Desktop" },
    @{ src = "$sourceRoot\Documents"; dest = "Documents" },
    @{ src = "$sourceRoot\Downloads"; dest = "Downloads" },
    @{ src = "$sourceRoot\Pictures"; dest = "Pictures" },
    @{ src = "$sourceRoot\Videos"; dest = "Videos" },
    @{ src = "$sourceRoot\Music"; dest = "Music" },
    @{ src = "$sourceRoot\Favorites"; dest = "Favorites" },
    @{ src = "$env:APPDATA\Mozilla\Firefox\Profiles"; dest = "AppData\Firefox" },
    @{ src = "$env:LOCALAPPDATA\Google\Chrome\User Data"; dest = "AppData\Chrome" },
    @{ src = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"; dest = "AppData\Edge" }
)

# Robocopy options
$robocopyFlags = "/MIR /Z /XA:H /W:1 /R:1 /MT:32 /NFL /NDL /NP"

# Backup each folder in parallel
$jobs = @()
foreach ($target in $targets) {
    $src = $target.src
    $dest = Join-Path $destRoot $target.dest

    if (-not (Test-Path $src)) {
        Write-Host "Skipping missing folder: $src"
        continue
    }

    $args = @(
        "`"$src`"",
        "`"$dest`"",
        $robocopyFlags
    )

    # Start robocopy as a background job
    $jobs += Start-Job -ScriptBlock {
        param($a)
        robocopy.exe @a | Out-Null
    } -ArgumentList ($args)
}

Write-Host "Running parallel robocopy jobs to saturate USB 3.2 connection..."

# Wait for jobs to complete
$jobs | Wait-Job | ForEach-Object {
    $jobOutput = Receive-Job $_
    Remove-Job $_
}

Write-Host "Backup complete. You may now eject your USB drive."