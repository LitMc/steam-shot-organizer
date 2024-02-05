param(
    [string]$SteamDirectory = 'C:\Program Files (x86)\Steam',
    [string]$IconDirectory = (Join-Path $PSScriptRoot -ChildPath 'icons'),
    [switch]$Restore
)
# Save the current encoding and switch to UTF-8.
# To treat these characters correctly: ™, ひらがな
$PrevEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$Defaults = @{
    SteamDirectory = 'C:\Program Files (x86)\Steam'
    # Default desktop.ini for a Steam screenshots folder
    IconSettings   = @'
[.ShellClassInfo]
IconResource=.\thumb.ico,0
IconFile=.\thumb.ico
IconIndex=0
[ViewState]
Mode=
Mode=
Vid=
'@
}

function Exit-With-Error {
    # Restore the previous encoding.
    [Console]::OutputEncoding = $PrevEncoding
    exit 2
}

function Exit-With-Success {
    # Restore the previous encoding.
    [Console]::OutputEncoding = $PrevEncoding
    exit 0
}

# Test a path and print some messages
function Test-Path-Verbose {
    param(
        $Path
    )
    if ( -not ( Test-Path -Path $Path ) ) {
        Write-Warning "Cannot find an icon source image at ""$Path""."
        Write-Warning "Please confirm ""$Path"" can be opened with Explorer."
        Return $false
    }
    Return $true
}

Write-Host "Steam directory   : $SteamDirectory"
Write-Host "Icon directory    : $IconDirectory"
Write-Host ('Running to restore: {0}' -f ($null -ne $RestoreDeafult))

# Check a steam directory exists
if ( -not ( Test-Path-Verbose -Path $SteamDirectory ) ) {
    Exit-With-Error
}

# Check a icon directory exists
if ( -not ( Test-Path-Verbose -Path $IconDirectory ) ) {
    Exit-With-Error
}

# Check a steam screenshots directory exists
$ScreenshotParentDirectory = Join-Path -Path $SteamDirectory -ChildPath 'userdata\*\760\remote'
if ( -not ( Test-Path -Path $ScreenshotParentDirectory ) ) {
    Write-Error "Cannot find Steam screenshots directory: $ScreenshotParentDirectory"
    if ( $SteamDirectory -eq $Defaults.SteamDirectory ) {
        Write-Error "Please confirm the Steam directory ''$SteamDirectory"" has ''userdata\ { some numbers }\760\remote"" directories in it."
    } else {
        Write-Error "Please confirm the directory ''$ScreenshotParentDirectory"" can be opened with Explorer."
    }
    Exit-With-Error
}

foreach ( $GameIdDirectory in Get-ChildItem ( Resolve-Path -Path $ScreenshotParentDirectory ) ) {
    $Id = ($GameIdDirectory | Select-Object Name).Name
    $IconPath = Join-Path $IconDirectory -ChildPath "$Id.ico"
    # 760\remote\{Game ID}\screenshots\desktop.ini
    $DesktopIniPath = Join-Path -Path $GameIdDirectory.FullName -ChildPath 'screenshots\desktop.ini'
    # Customized desktop.ini
    $IconSettings = @"
[.ShellClassInfo]
IconResource=$IconPath,0
IconFile=$IconPath
IconIndex=0
[ViewState]
Mode=
Mode=
Vid=
"@

    # Create desktop.ini if it does not exist
    if ( -not ( Test-Path -Path $DesktopIniPath ) ) {
        New-Item -Path $DesktopIniPath -ItemType File -Force
    }

    # Modify desktop.ini
    if ( $Restore ) {
        $Defaults.IconSettings | Set-Content $DesktopIniPath -Force
    } else {
        $IconSettings | Set-Content $DesktopIniPath -Force
    }

    # To show custom icons, target folder has to be system directory
    Attrib +S $GameIdDirectory.FullName
    # Add system and hide attributes to desktop.ini
    Attrib +S +H $DesktopIniPath

    Write-Host "Finished modifying ""$DesktopIniPath""."
}
Write-Host 'Finished modifying desktop.ini of all screenshots folders.'

$Prompt = @'
To apply the changes, you must restart explorer.exe or your computer.
Caution: When Explorer is restarted, all open file and folder windows will be closed.
         Save all working data before restarting.

Do you want to restart explorer.exe? (y/N)
'@
$Answer = Read-Host $Prompt

if ( $Answer -in @('Y', 'y') ) {
    # Restart explorer.exe to apply changes
    Stop-Process -Name explorer -Force
    Start-Process explorer
}

Write-Host 'Done'
