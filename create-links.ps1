param (
    [string]$SteamDirectory = "C:\Program Files (x86)\Steam",
    [string]$Destination = "$PSScriptRoot\links",
    [string]$Source = (Join-Path -Path $SteamDirectory -ChildPath "userdata\*\760\remote")
)

# Save the current encoding and switch to UTF-8.
# To treat these characters correctly: ™, ひらがな
$PrevEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

# Default parameter values
$Defaults = @{
    SteamDirectory = "C:\Program Files (x86)\Steam"
    Destination    = "$PSScriptRoot\links"
    Source         = (Join-Path -Path $SteamDirectory -ChildPath "userdata\*\760\remote")
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

# Print parameters to console
Write-Host "[inputs] Steam directory                     : $SteamDirectory"
Write-Host "[inputs] Source screenshots directory        : $Source"
Write-Host "[inputs] Destination symbolic links directory: $Destination"

# Check steam directory exists
$ResolvedSteamDirectory = Resolve-Path -Path $SteamDirectory
if ( $null -eq $ResolvedSteamDirectory ) {
    Write-Error "Cannot find Steam directory: $SteamDirectory"
    Write-Error "Please confirm the directory $SteamDirectory can be opened with Explorer"
    Exit-With-Error
}

# Check steam screenshots directory exists
$ResolvedSource = Resolve-Path -Path $Source
if ( $null -eq $ResolvedSource ) {
    Write-Error "Cannot find Steam screenshots directory: $Source"
    if ( $Source -eq $defaults.Source ) {
        Write-Error "Please confirm Steam directory '$SteamDirectory' has 'userdata\{some numbers}\760\remote' directories in it."
    }
    else {
        Write-Error "Please confirm the directory $Source can be opened with Explorer."
    }
    Exit-With-Error
}
Write-Host "Actual source screenshots directory: $ResolvedSource"
Write-Host ""
Write-Host "Start mapping id to game title"
# Example: C:\Program Files (x86)\Steam\userdata\{some numbers}\760\remote\400
foreach ( $GameIdDirectory in Get-ChildItem $ResolvedSource ) {
    Write-Host ""
    Write-Host ("Target: {0}" -f $GameIdDirectory.FullName) -ForegroundColor DarkCyan

    # Example: 400
    $Id = ($GameIdDirectory | Select-Object Name).Name
    $RequestUri = "https://store.steampowered.com/api/appdetails?appids=$Id"
    Write-Host "Invoke web request to: $RequestUri"

    # no-cache: Avoid regional restriction (Example: NiGHTS into Dreams)
    $Result = Invoke-WebRequest -Uri $RequestUri -Headers @{"Cache-Control"="no-cache"} 
    $QueryIsSuccess = ([string]::Format(".""{0}"".success", $Id))
    if ( ( $Result.Content | jq $QueryIsSuccess ) -ne "true" ) {
        Write-Warning ("Received non successful response. Skip processing: $Id")
        Continue
    }
    Write-Host ("Receive response successfully. ")
    
    $Result
    $QueryGameTitle = ([string]::Format(".""{0}"".data.name", $Id))
    # .{ID}.data.name element has double quote to be removed
    # Example: "Portal" -> Portal
    $Title = ($Result.Content | jq $QueryGameTitle) -replace """"
    Write-Host "Game ID   : $Id"
    Write-Host "Game title: $Title"

    # Remove invalid characters for a file name from title
    $InvalidCharsRegex = "[{0}]" -f ([System.IO.Path]::GetInvalidFileNameChars() -join '')
    $SanitizedTitle = $Title -replace $InvalidCharsRegex
    if ( $SanitizedTitle -ne $Title ) {
        Write-Warning "Title $Title contains invalid characters for a file name."
        Write-Warning "Remove invalid characters for a file name. Sanitized title: $SanitizedTitle"
    }

    # Create symbolic link
    # Skip creating symbolic link if a source directory does not exist
    $SourceScreenshotPath = Join-Path -Path $GameIdDirectory -ChildPath "screenshots"
    if ( -not ( Test-Path -Path $SourceScreenshotPath ) ) {
        Write-Warning ("Cannot find source screenshots directory: $SourceScreenshotPath")
        Write-Warning ("Skip processing: $Id")
        Continue
    }

    $DestinationLinkPath = Join-Path -Path $Destination -ChildPath $SanitizedTitle
    # Skip creating symbolic link if a destination link already exists
    if ( ( Test-Path -Path $DestinationLinkPath ) ) {
        Write-Warning "Symbolic link $DestinationLinkPath is already exists."
        Write-Warning ("Skip processing: $Id")
        Continue
    }
    Write-Host "Source     : $SourceScreenshotPath"
    Write-Host "Destination: $DestinationLinkPath"  

    if ( New-Item -ItemType SymbolicLink -Path $DestinationLinkPath -Target $SourceScreenshotPath ) {
        Write-Host "Create symbolic link successfully: $DestinationLinkPath" -ForegroundColor DarkGreen
    }
    else {
        Write-Error "Cannot create symbolic link: $DestinationLinkPath"
        Write-Error "Please confirm the directory $Destination can be opened with Explorer."
        Exit-With-Error
    }
}
Write-Host "Finish mapping game IDs to game titles"
Exit-With-Success