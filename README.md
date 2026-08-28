# Omaweather

Current weather in the [Omarchy](https://omarchy.org) bar, with the colored
[v2.wttr.in](https://v2.wttr.in) forecast chart on click.

<p align="center">
  <img src="preview.png" alt="Omaweather bar chip and v2.wttr.in forecast chart">
</p>

The bar shows an emoji and temperature. Click it to open the three-day
temperature graph, precipitation, wind, and moon phase — the same chart you
get from `curl v2.wttr.in`.

No sudo or pkexec is required.

## Install

```sh
omarchy plugin add https://github.com/Gedankenn/omaweather.git --enable
```

The widget lands in the center of the bar by default. Move it if you want:

```sh
omarchy bar move io.github.gedankenn.omaweather --section center
```

## Usage

| Input | Action |
| --- | --- |
| Left click | Open or close the forecast chart |
| Middle click | Refresh |
| Right click | Desktop notification with the current conditions |
| `r` in the panel | Refresh |
| Escape | Close the panel |

## Configure

Per-widget settings live on the bar entry (config UI or `omarchy bar set`):

| key | default | meaning |
| --- | --- | --- |
| `location` | empty | City name or `lat,lon`. Empty uses IP geolocation. |
| `refreshMinutes` | `15` | How often to refetch from wttr.in |

```sh
omarchy bar set io.github.gedankenn.omaweather location "Pato Branco"
omarchy bar set io.github.gedankenn.omaweather refreshMinutes 20
```

The plugin does not overwrite user configuration. Removing it only drops its
bar entry.

## External services

Forecast data is fetched over HTTPS from [wttr.in](https://github.com/chubin/wttr.in)
with `curl`. Nothing is piped to a shell.

## Remove

```sh
omarchy plugin remove io.github.gedankenn.omaweather
```

## License

MIT. See [LICENSE](LICENSE).
