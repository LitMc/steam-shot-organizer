# To use -Verbose and -Debug parameters
[CmdletBinding()]
param (
    [string]$SteamDirectory = 'C:\Program Files (x86)\Steam',
    [string]$Destination = "$PSScriptRoot\links",
    [string]$Source = (Join-Path -Path $SteamDirectory -ChildPath 'userdata\*\760\remote'),
    [string]$Config = "$PSScriptRoot\config.yaml",
    [string]$SaveImagesTo = "$PSScriptRoot\images\",
    [switch]$OverwriteLink,
    [switch]$OverwriteConfig,
    [switch]$OverwriteImage
)
$Verbose = $PSCmdlet.MyInvocation.BoundParameters['Verbose']
$Debug = $PSCmdlet.MyInvocation.BoundParameters['Debug']
# This cache directory has asset images for Steam library
$SteamLibaryCache = (Join-Path -Path $SteamDirectory -ChildPath 'appcache\librarycache')

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
# Memoize game information
$GameInfoMemo = @{}
function Get-GameInfo {
    param(
        [string] $Id
    )
    if ( $GameInfoMemo.Contains($Id) ) {
        Write-Host ("Found game information in cache. ID: ""$Id""")
        Return $GameInfoMemo[$Id]
    }
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
    $GameInfoMemo[$Id] = $Result
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

function Write-GameInfo {
    param(
        [string]$Id,
        [string]$Title
    )
    Write-Host 'ID: ' -NoNewline
    Write-Host $Id -ForegroundColor Cyan
    Write-Host 'Title: ' -NoNewline
    Write-Host $Title -ForegroundColor Cyan
}

function Get-GameTitle {
    param(
        [string]$Id
    )
    if ( $ParsedConfig.Contains($Id) -and $ParsedConfig[$Id].Contains('title') ) {
        Return $ParsedConfig[$Id]['title']
    }
    $Result = Get-GameInfo -Id $Id
    # $QueryGameTitle has double quotes to be removed
    $QueryGameTitle = ([string]::Format('."{0}".data.name', $Id))
    # Example: "Portal" -> Portal
    $Title = ($Result.Content | jq $QueryGameTitle) -replace '"'
    if ( -not $ParsedConfig.Contains($Id) ) {
        $ParsedConfig[$Id] = @{}
    }
    $ParsedConfig[$Id]['title'] = $Title
    Return $Title
}

# Retrieve an icon image from user-defined path in config
function Get-ImageFromConfig {
    param(
        [string]$Id
    )
    if ( -not $ParsedConfig.Contains($Id) ) {
        $ParsedConfig[$Id] = @{}
        Return $null
    }
    if ( -not $ParsedConfig[$Id].Contains('image') ) {
        Return $null
    }
 
    Write-Host 'Found an icon image path in config.'
    Write-Host ('Image: {0}' -f $ParsedConfig[$Id]['image'])
    $LibraryImagePath = $ParsedConfig[$Id]['image'].ToString()
    if ( -not ( Test-Path -Path $LibraryImagePath ) ) {
        Write-Error "Cannot find an icon source image at ""$LibraryImagePath""."
        Write-Error "Please confirm ""$LibraryImagePath"" can be opened with Explorer."
        Return $null
    }
    $CopyTo = Join-Path -Path $SaveImagesTo -ChildPath "$Id.jpg"
    if ( ( -not  $OverwriteImage ) -and ( Test-Path-Verbose -Path $CopyTo ) ) {
        Write-Warning "Skipped overwriting ""$CopyTo"" with ""$LibraryImagePath""."
        Write-Warning 'Use -OverwriteImage if you want to overwrite images.'
        Return $CopyTo
    }
    if ( $LibraryImagePath -ne $CopyTo ) {
        Copy-Item $LibraryImagePath -Destination $CopyTo
    }
    Return $CopyTo
}

# Retrieve an icon image from Steam local library cache
function Get-ImageFromSteamLibrary {
    param(
        [string]$Id
    )
    # Almost all games have a 600x900 Portrait image
    # Some titles have filename like '{Game ID}_library_600x900_{Language}.jpg'
    $ImageName = '{0}_library_600x900*.jpg' -f $Id
    $LibraryImagePath = Join-Path $SteamLibaryCache -ChildPath $ImageName
    if ( -not ( Test-Path-Verbose -Path $LibraryImagePath ) ) {
        Return $null
    }
    $CopyTo = Join-Path -Path $SaveImagesTo -ChildPath "$Id.jpg"
    if ( ( -not  $OverwriteImage ) -and ( Test-Path-Verbose -Path $CopyTo ) ) {
        Write-Warning "Skipped overwriting ""$CopyTo"" with ""$LibraryImagePath""."
        Write-Warning 'Use -OverwriteImage if you want to overwrite images.'
        Return $CopyTo
    }
    Copy-Item $LibraryImagePath -Destination $CopyTo
    Return $CopyTo
}

# Retrieve an icon image from Steam Web API
function Get-ImageFromWeb {
    param(
        [string]$Id
    )
    $GameInfo = Get-GameInfo -Id $Id
    $ImageUri = ($GameInfo.Content | jq ('."{0}".data.header_image' -f $Id)) -replace '"'
    $ReturnPath = Join-Path -Path $SaveImagesTo -ChildPath "$Id.jpg"
    
    # Invoke-WebRequest has no return values when -OutFile is enabled
    try {
        Invoke-WebRequest -Uri $ImageUri -Headers @{'Cache-Control' = 'no-cache' } -OutFile $ReturnPath
    } catch {
        Write-Warning $PSItem.Exception.Message
        Write-Warning "Please confirm ""$ImageUri"" can be opened with web browsers."
        Return $null
    }
    Return $ReturnPath
}

function Get-Image {
    param(
        [string]$Id
    )
    $ImagePath = Get-ImageFromConfig -Id $Id
    if ( $null -ne $ImagePath ) {
        Write-Host 'Image defined in config will be used for an icon.'
        Return $ImagePath
    }

    $ImagePath = Get-ImageFromSteamLibrary -Id $Id
    if ( $null -ne $ImagePath ) {
        if ( $OverwriteConfig ) {
            $ParsedConfig[$Id]['image'] = $ImagePath
        }
        Write-Host 'Image in steam library cache will be used for an icon.'
        Return $ImagePath
    }

    $ImagePath = Get-ImageFromWeb -Id $Id
    if ( $null -ne $ImagePath ) {
        if ( $OverwriteConfig ) {
            $ParsedConfig[$Id]['image'] = $ImagePath
        }
        Write-Host 'Image from Steam Web API will be used for an icon.'
        Return $ImagePath
    }
    Return $null
}

function Set-Shortcut {
    param(
        [string] $SourcePath,
        [string] $DestinationPath
    )
    $IsSuccessed = $false
    try {
        $WScriptShell = New-Object -ComObject WScript.Shell
        $Shortcut = $WScriptShell.CreateShortcut($DestinationLinkPath)
        $Shortcut.TargetPath = $SourceScreenshotPath
        $Shortcut.Save()
        $IsSuccessed = $true
    } catch {
        Write-Error $_
    } finally {
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($WScriptShell) | Out-Null
    }
    Return $IsSuccessed
}

# Print parameters to console
Write-Host "[inputs] Steam directory                : $SteamDirectory"
Write-Host "[inputs] Source screenshots directory   : $Source"
Write-Host "[inputs] Destination shortcuts directory: $Destination"
Write-Host "[inputs] ID:Title map config file       : $Config"

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
    Write-Host ('Target: {0}' -f $GameIdDirectory.FullName)

    # Id Example: 400
    $Id = ($GameIdDirectory | Select-Object Name).Name
    # Title Example: Portal
    $Title = Get-GameTitle -Id $Id
    
    Write-GameInfo -Id $Id -Title $Title

    # Get a source icon image path (*.jpg or *.png)
    # When no images in a local directory, then a web request will be invoked to download images
    $ImagePath = Get-Image -Id $Id

    if ( $null -eq $ImagePath ) {
        # No available images for icons
    }

    # Get and test SourceScreenshotPath
    $SourceScreenshotPath = Get-SourceScreenshotPath -Id $Id -GameIdDirectory $GameIdDirectory

    # Skip creating a shortcut if a destination link already exists
    $DestinationLinkPath = Join-Path -Path $Destination -ChildPath "$Id.lnk"
    if ( ( Test-Path -Path $DestinationLinkPath ) ) {
        Write-Warning "A shortcut ""$DestinationLinkPath"" already exists."
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

    # Create a shortcut
    $LinkResult = Set-Shortcut -SourcePath $SourceScreenshotPath -DestinationPath $DestinationLinkPath

    if ( $LinkResult ) {
        # Remove invalid characters for a file name from title
        $SanitizedTitle = Get-SanitizedTitle -Title $Title

        # Rename {Game ID}.lnk to {Game title}.lnk and remove an old one
        $OldShortcut = Join-Path -Path $Destination -ChildPath "$SanitizedTitle.lnk"
        if ( Test-Path -Path $OldShortcut ) {
            Remove-Item $OldShortcut
        }
        Rename-Item (Join-Path -Path $Destination -ChildPath "$Id.lnk") "$SanitizedTitle.lnk"
    } else {
        Write-Error "Cannot create a shortcut: $DestinationLinkPath"
        Write-Error "Please confirm the directory ""$Destination"" can be opened with Explorer."
        Exit-With-Error
    }
    Write-Host "Created a shortcut successfully: $SanitizedTitle.lnk" -ForegroundColor DarkGreen
}
Write-Host 'Finished mapping game IDs to game titles.'

# Write id:title mappings to a config yaml file
Set-ConfigToYaml -ParsedConfig $ParsedConfig

Exit-With-Success