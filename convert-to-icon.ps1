param (
    [string]$InputDirectory = (Join-Path $PSScriptRoot -ChildPath 'icon_source_images'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot -ChildPath 'icons'),
    [string]$Config = "$PSScriptRoot\config.yaml",
    [switch]$OverwriteIcon
)

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

if ( -not ( Test-Path-Verbose -Path $InputDirectory ) ) {
    Exit-With-Error
}
if ( -not ( Test-Path-Verbose -Path $OutputDirectory ) ) {
    Exit-With-Error
}

foreach ( $ImageFile in Get-ChildItem $InputDirectory ) {
    $ImageFileItem = (Get-Item -Path $ImageFile)
    if ( $ImageFileItem.Extension -eq 'md') {
        Continue
    }
    $Id = $ImageFileItem.BaseName
    $IconName = "$Id.ico"
    $InputFrom = $ImageFileItem.FullName
    $OutputTo = Join-Path $OutputDirectory -ChildPath $IconName
    if ( ( -not $OverwriteIcon ) -and ( Test-Path-Verbose -Path $OutputTo ) ) {
        Write-Warning "Skipped converting ""$InputFrom"" to ""$OutputTo"". It already exists."
        Write-Warning 'Use -OverwriteIcon if you want to overwrite icons.'
        Continue
    }
    magick $InputFrom -resize 256x256 -background transparent -gravity center -extent 256x256 $OutputTo
    Write-Host "Finished converting: $InputFrom"
}

Write-Host 'Finished converting images to *.ico files.'
