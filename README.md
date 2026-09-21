# Omaweather

<p align="center">
  <strong><a href="https://open-meteo.com">Open-Meteo</a> weather, living in your Omarchy bar.</strong><br>
  Emoji and temperature up top. A native three-day graph on click.
</p>

<p align="center">
  <img src="preview.png" width="480" alt="Omaweather in the Omarchy bar: emoji and temperature on the chip, and a colored three-day temperature graph with rain bars and condition icons in the popup">
</p>

<p align="center">
  <a href="https://omarchy.org"><img src="https://img.shields.io/badge/Omarchy-Quattro-111111?style=flat-square" alt="Omarchy Quattro"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-e6c35c?style=flat-square" alt="MIT license"></a>
  <a href="https://open-meteo.com"><img src="https://img.shields.io/badge/data-open--meteo-87ff00?style=flat-square" alt="Open-Meteo"></a>
</p>

A real vector graph drawn inside the shell — a temperature curve colored from cold blue to hot red, rain bars, condition icons, and the day's sunrise and sunset — in your bar font and theme colors.

No sudo or pkexec is required.

## Install

```sh
omarchy plugin add https://github.com/Gedankenn/omaweather.git --enable
```

It lands in the center of the bar, next to the clock. Move it anywhere:

```sh
omarchy bar move io.github.gedankenn.omaweather --section right
```

## What you get

| In the bar | In the popup |
| --- | --- |
| Weather emoji + temperature | Current conditions, feels-like, wind, humidity |
| Tooltip with wind and humidity | Three-day temperature curve with a cold-to-hot gradient |
| Refreshes every 15 minutes | Rain bars, condition icons, sunrise and sunset |

## Usage

| Input | Action |
| :---: | --- |
| Left click | Open or close the forecast |
| Click the city name | Search and pick a city |
| Enter | Same city search, while the panel is open |
| Empty search | Back to the default location |
| Middle click | Refresh now |
| Right click | Desktop notification with current conditions |
| `r` | Refresh while the panel is open |
| Escape | Close the search, or the panel |

## Configure

The simple way: open the popup, click the city name, type, pick a result. That stores the name plus coordinates so the next fetch hits the right place.

Settings also live on the widget entry — the Omarchy config UI, or:

```sh
omarchy bar set io.github.gedankenn.omaweather location "Pato Branco"
omarchy bar set io.github.gedankenn.omaweather refreshMinutes 20
```

| Key | Default | Meaning |
| --- | --- | --- |
| `location` | empty | City name or `lat,lon`. Empty falls back to the Omarchy `weather.json` location, then to Pato Branco. |
| `refreshMinutes` | `15` | How often to refetch. Minimum 1. |

The plugin does not overwrite user configuration. Removing it only drops its bar entry.

## Data

Everything — the bar chip, the current-conditions summary, and the three-day graph — comes from [Open-Meteo](https://open-meteo.com) over HTTPS, the same keyless source the Second Coming theme uses. One request returns the current readings, 72 hours of hourly data, and three days of daily highs, lows, rain chance, sunrise, and sunset. It is fetched with `curl`, and the download size is capped before it reaches the shell (`head -c`, plus `--max-filesize`). Remote fields are clipped and treated as plain text. Metric units.

Needs a network connection. If Open-Meteo is slow or down, the last good reading stays on the bar and the plugin retries.

## Remove

```sh
omarchy plugin remove io.github.gedankenn.omaweather
```

## License

[MIT](LICENSE) © Fabio Slika Stella
