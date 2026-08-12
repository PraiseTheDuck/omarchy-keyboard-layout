# Keyboard Layout Pulse

A keyboard-layout picker for the Omarchy Quattro bar. The current layout
pulses after a change.

## Install

```bash
omarchy plugin add \
  https://github.com/ilyaZar/omarchy-keyboard-layout.git --enable
```

The plugin declares that it is a replacement for Omarchy's built-in
`omarchy.keyboard-layout` widget. Enabling it swaps the existing bar entry to
this plugin while preserving that entry's position and settings. Disabling or
removing the plugin restores the built-in widget in the same place.

This only replaces the bar widget. It does not replace or rewrite your
Hyprland keyboard configuration. The available languages continue to come
from `~/.config/hypr/input.lua`, and the plugin reads the effective list from
Hyprland.

## Use and customize

- Click the layout label to choose a configured language.
- Scroll over the label to cycle languages.
- Open **Settings** to choose teal, purple, blue, or enter a custom
  `#RRGGBB` pulse color.
- Select **Edit keyboard layouts** to open Omarchy's Hyprland input file.

The included colors are:

- Teal: `#2aa198`
- Purple: `#a77bd8`
- Blue: `#3b82f6`

Apply saves the selected color in `~/.config/omarchy/shell.json` and closes
the menu.

## Remove

```bash
omarchy plugin remove io.github.ilyazar.keyboard-layout --yes
```

## License

MIT
