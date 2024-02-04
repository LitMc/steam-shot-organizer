# To use -Verbose and -Debug parameters
[CmdletBinding()]
param (
    [string]$SteamDirectory = 'C:\Program Files (x86)\Steam',
    [string]$Destination = "$PSScriptRoot\links",
    [string]$Source = (Join-Path -Path $SteamDirectory -ChildPath 'userdata\*\760\remote'),
    [string]$Config = "$PSScriptRoot\config.yaml",
    [switch]$OverwriteLink,
    [switch]$OverwriteConfig
)
$Verbose = $PSCmdlet.MyInvocation.BoundParameters['Verbose']
$Debug = $PSCmdlet.MyInvocation.BoundParameters['Debug']

$DefaultConfigYamlText = @'
# Configuration structure
# {Game ID}:
#   title: {Game title}

# Example
# "70":
#   title: Half-Life
# "400":
#   title: Portal

# Write here the ones you would like to define
'@

# Save the current encoding and switch to UTF-8.
# To treat these characters correctly: ™, ひらがな
$PrevEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

# Default parameter values
$Defaults = @{
    SteamDirectory = 'C:\Program Files (x86)\Steam'
    Destination    = "$PSScriptRoot\links"
    Source         = (Join-Path -Path $SteamDirectory -ChildPath 'userdata\*\760\remote')
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

function Get-SanitizedTitle {
    param(
        [string] $Title
    )
    $InvalidCharsRegex = '[{0}]' -f ([System.IO.Path]::GetInvalidFileNameChars() -join '')
    $SanitizedTitle = $Title -replace $InvalidCharsRegex
    if ( $SanitizedTitle -ne $Title ) {
        Write-Warning "Title ""$Title"" contains invalid characters for a file name."
        Write-Warning "Remove invalid characters. Sanitized title: $SanitizedTitle"
    }
    Return $SanitizedTitle
}

# Retrieve game info such as title and banner image URL from Steam Web API
function Get-Game-Info {
    param(
        [string] $Id
    )
    $RequestUri = "https://store.steampowered.com/api/appdetails?appids=$Id"
    Write-Host "Invoke a web request to: $RequestUri"

    # no-cache: Avoid regional restriction (Example: NiGHTS into Dreams)
    $Result = Invoke-WebRequest -Uri $RequestUri -Headers @{'Cache-Control' = 'no-cache' } 
    $IsQuerySuccess = ([string]::Format('."{0}".success', $Id))
    if ( ( $Result.Content | jq $IsQuerySuccess ) -ne 'true' ) {
        Write-Warning ("Received non successful response. Skip processing: $Id")
        Continue
    }
    Write-Host ('Receive a response successfully.')
    if ( $Verbose -or $Debug ) {
        Write-Debug $Result
    }
    Return $Result
}

function Get-SourceScreenshotPath {
    param(
        [string] $Id,
        $GameIdDirectory
    )
    # Skip creating a link if a source directory does not exist
    $SourceScreenshotPath = Join-Path -Path $GameIdDirectory -ChildPath 'screenshots'
    if ( -not ( Test-Path -Path $SourceScreenshotPath ) ) {
        Write-Warning ("Cannot find source screenshots directory: $SourceScreenshotPath")
        Write-Warning ("Skip processing: $Id")
        Continue
    }
    Return $SourceScreenshotPath
}

function Get-ConfigFromYaml {
    param (
        [string]$Config
    )
    try {
        $ParsedConfig = Get-Content -Path $Config -Raw | ConvertFrom-Yaml -Ordered
    } catch {
        Write-Error 'Cannot load config.yaml.'
        Write-Error 'Please check that config.yaml format is valid.'
        Write-Error 'Visit: https://www.yamllint.com/ (or use any other yaml lint tools)'
        Write-Error 'Paste whole texts of config.yaml to textbox and click ''Go''.'
        Exit-With-Error
    }
    
    if ( $null -eq $ParsedConfig ) {
        Write-Host "Detected no user-defined settings in ""$Config""."
        Write-Host 'All game IDs will have their titles resolved by the Steam Web API.'
        $ParsedConfig = @{}
    }
    Return $ParsedConfig
}

function Set-ConfigToYaml {
    param(
        [PSCustomObject]$ParsedConfig
    )
    if ( ( $null -ne $ParsedConfig ) -and ($ParsedConfig.Count -eq 0 ) ) {
        # To avoid writing '{}' to config.yaml when $ParsedConfig is an empty map
        $ParsedConfig = $null
    }
    if ( $OverwriteConfig ) {
        $DefaultConfigYamlText | Set-Content -Path $Config
        ConvertTo-Yaml -Data $ParsedConfig | Add-Content $Config
        Write-Host "Config is successfully written to ""$Config""."
    } else {
        Write-Host "Skipped writing config to ""$Config"". Use -OverwriteConfig if you want to overwrite it."
    }
}

function Get-Game-Title {
    param(
        [string]$Id
    )
    $Result = Get-Game-Info -Id $Id

    # $QueryGameTitle has double quotes to be removed
    $QueryGameTitle = ([string]::Format('."{0}".data.name', $Id))
    # Example: "Portal" -> Portal
    $Title = ($Result.Content | jq $QueryGameTitle) -replace '"'
    Write-Host "Game ID   : $Id"
    Write-Host "Game title: $Title"
    Return $Title
}

# Print parameters to console
Write-Host "[inputs] Steam directory                     : $SteamDirectory"
Write-Host "[inputs] Source screenshots directory        : $Source"
Write-Host "[inputs] Destination symbolic links directory: $Destination"
Write-Host "[inputs] ID:Title map config file            : $Config"

# Load id:title mappings from a config yaml file
$ParsedConfig = Get-ConfigFromYaml -Config $Config

# Check a steam directory exists
if ( -not ( Test-Path -Path $SteamDirectory ) ) {
    Write-Error "Cannot find Steam directory: $SteamDirectory"
    Write-Error "Please confirm the directory ""$SteamDirectory"" can be opened with Explorer"
    Exit-With-Error
}

# Check a steam screenshots directory exists
if ( -not ( Test-Path -Path $Source ) ) {
    Write-Error "Cannot find Steam screenshots directory: $Source"
    if ( $Source -eq $defaults.Source ) {
        Write-Error "Please confirm the Steam directory ""$SteamDirectory"" has ""userdata\{some numbers}\760\remote"" directories in it."
    } else {
        Write-Error "Please confirm the directory ""$Source"" can be opened with Explorer."
    }
    Exit-With-Error
}

$ResolvedSource = Resolve-Path -Path $Source
Write-Host "Actual source screenshots directory: $ResolvedSource"
Write-Host ''
Write-Host 'Start mapping id to game title...'

# GameIdDirectory Example: C:\Program Files (x86)\Steam\userdata\{some numbers}\760\remote\400
foreach ( $GameIdDirectory in Get-ChildItem $ResolvedSource ) {
    Write-Host ''
    Write-Host ('Target: {0}' -f $GameIdDirectory.FullName) -ForegroundColor DarkCyan

    # Id Example: 400
    $Id = ($GameIdDirectory | Select-Object Name).Name

    # Title Example: Portal
    $Title = Get-Game-Title -Id $Id

    # Remove invalid characters for a file name from title
    $SanitizedTitle = Get-SanitizedTitle -Title $Title

    # Get and test SourceScreenshotPath
    $SourceScreenshotPath = Get-SourceScreenshotPath -Id $Id -GameIdDirectory $GameIdDirectory

    # Skip creating a symbolic link if a destination link already exists
    $DestinationLinkPath = Join-Path -Path $Destination -ChildPath $SanitizedTitle
    if ( ( Test-Path -Path $DestinationLinkPath ) ) {
        Write-Warning "A symbolic link ""$DestinationLinkPath"" already exists."
        if ( $OverwriteLink ) {
            Write-Host 'Overwrite a link with a new one.'
            Write-Host "Old source : ""$((Get-Item $DestinationLinkPath).LinkTarget)"""
            Write-Host "New source : ""$SourceScreenshotPath"""
            Write-Host "Destination: ""$DestinationLinkPath"""
        } else {
            Write-Warning ("Skip processing: $Id")
            Continue
        }
    } else {
        Write-Host "Source     : $SourceScreenshotPath"
        Write-Host "Destination: $DestinationLinkPath"
    }

    # Create a symbolic link
    if ( $OverwriteLink ) {
        $LinkResult = New-Item -ItemType SymbolicLink -Path $DestinationLinkPath -Target $SourceScreenshotPath -Force
    } else {
        $LinkResult = New-Item -ItemType SymbolicLink -Path $DestinationLinkPath -Target $SourceScreenshotPath
    }

    if ( $LinkResult ) {
        Write-Host "Create a symbolic link successfully: $DestinationLinkPath" -ForegroundColor DarkGreen
    } else {
        Write-Error "Cannot create a symbolic link: $DestinationLinkPath"
        Write-Error "Please confirm the directory ""$Destination"" can be opened with Explorer."
        Exit-With-Error
    }
}
Write-Host 'Finished mapping game IDs to game titles.'

# Write id:title mappings to a config yaml file
Set-ConfigToYaml -ParsedConfig $ParsedConfig

Exit-With-Success