# Finesse for Omarchy

An [Omarchy](https://omarchy.org) bar widget for
[Finesse](https://github.com/CoffeeCC/finesse), the Jellyfin web client.

- **Click** the bar icon to see Continue Watching from your Jellyfin server,
  with artwork, progress, and time left.
- **Click a title** (or press `Enter`) to resume it in Finesse, which opens as
  its own app window. **Right-click** a title to open its details page instead.
- **Middle-click** the icon to open Finesse. **Right-click** it to refresh.
- Use `↑`/`↓` or `j`/`k` to move through the list and `Esc` to close it.

## Install

```bash
omarchy plugin add https://github.com/CoffeeCC/omarchy-finesse.git --enable
```

You'll be asked where to put the widget in the bar. It goes on the right by
default.

## Configure

Open the widget's settings from the bar editor, or edit its entry under
`bar.layout` in `~/.config/omarchy/shell.json`:

| Setting          | What it is                                                                          |
| ---------------- | ----------------------------------------------------------------------------------- |
| `finesseUrl`     | Where Finesse is served, e.g. `https://media.example.com/finesse`                   |
| `jellyfinUrl`    | Your Jellyfin server. Leave it blank if Jellyfin is at the same origin as Finesse.  |
| `apiKey`         | A Jellyfin API key (Dashboard → API Keys)                                           |
| `userName`       | Whose Continue Watching to show. Blank means the first enabled user.                |
| `maxItems`       | How many titles to list (1–12, default 6)                                           |
| `refreshMinutes` | How often to refresh the list (default 5)                                           |

Example:

```json
{ "id": "coffeecc.finesse", "finesseUrl": "https://media.example.com/finesse",
  "apiKey": "…", "userName": "alice" }
```

> The API key is stored in plain text in `shell.json`, like every other widget
> setting. It can read your whole library, so don't post your `shell.json`
> anywhere.

## Add Finesse to the app launcher (optional)

To launch Finesse from `SUPER + SPACE` like any other app, run:

```bash
~/.config/omarchy/plugins/coffeecc.finesse/bin/finesse-webapp-install
```

It reads `finesseUrl` from the widget's settings. You can also pass the URL as
an argument.

To add Finesse to the Omarchy menu as well, put this in
`~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"finesse": {"icon":"󰷝","label":"Finesse","action":"omarchy-launch-webapp 'https://media.example.com/finesse'"},
```

## Requirements

- Omarchy with the Quickshell plugin system (`omarchy plugin` commands)
- A Chromium-based browser, which Omarchy web apps need
- `curl`, which is already installed on Omarchy

## Development

The data logic lives in `Model.js` and has no QML dependencies. To test it:

```bash
node --test tests/*.test.mjs
```

Before publishing a change, run `omarchy plugin validate .`.

## Uninstall

```bash
omarchy plugin remove coffeecc.finesse
```

## License

MIT
