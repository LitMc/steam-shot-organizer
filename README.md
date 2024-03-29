# steam-shot-organizer
SteamShotOrganizer is a collection of PowerShell scripts for Windows to easily open Steam screenshots folders without an official manager.
It aggregates screenshots folders into a single location while maintains the original files' integrity by using shortcuts.

## Prerequisites (TBD)
Some softwares have to be installed to run scripts.
Since there are no dependency management tools, you need install them manually. I am sorry for that.

### Install dependencies (TBD)

### Clone this repository
```
git clone https://github.com/LitMc/steam-shot-organizer.git
cd steam-shot-organizer
```

## Run
To run scripts, you have to launch a PowerShell console as Administrator because the scripts will modify Steam screenshots folders under a protected system directory.

### Create shortcuts and retrieve game information
```
.\create-shortcuts.ps1
```

### Convert images to icon (\*.ico) files
```
.\convert-to-icons.ps1
```

### Set icons to the shortcuts
```
.\set-icons.ps1
```
> [!CAUTION]
> `set-icons.ps1` modifies system files like `desktop.ini` to customize icons of Steam screenshots folders.
> If you have already modified `desktop.ini` of these folders, they are all overwritten by running `set-icons.ps1`.

### Configuration
You can define game titles and images for shortcuts in `config.yaml`.
By default, they are taken from the Steam Web API or the local Steam library cache,
If any of these are defined in `config.yaml`, the ones in `config.yaml` will take precedence.

- You can use `config.yaml` to create shortcuts for 
  - non-Steam games
  - region exclusive games
    - Web requests to Steam can be rejected

```yaml
# Structure of config.yaml
{Game ID}:
  title: {Game title}
  image: {an image path for an icon}

# Example
"70":
  title: Half-Life
  image: 'path\to\half-life.jpg'
"400":
  title: Portal
  image: 'path\to\portal-banner.png'

# Write here the ones you would like to define
```
