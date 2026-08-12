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
- Open **Settings** to choose a fixed color preset. Select **Custom** to enter
  your own `#RRGGBB` pulse color.
- The settings page shows the active layout shortcut in plain language. Use
  its gear button to open the owning line in `~/.config/hypr/input.lua` with
  `nvim`.
- Select **Edit keyboard layouts** to open Omarchy's Hyprland input file.

The included colors are:

- Teal: `#2aa198`
- Purple: `#a77bd8`
- Blue: `#3b82f6`
- Nord yellow: `#ebcb8b`

Each preset row shows its color. Presets cannot be edited. The custom field
accepts exactly six-digit hex colors such as `#2aa191`. Apply saves the custom
color in `~/.config/omarchy/shell.json` and closes the menu.

The shortcut display reads Hyprland's effective XKB `grp:*` option. Its label
comes from the installed XKB rules and uses friendly names such as `Super`
instead of `Win`. The plugin does not change or rewrite `input.lua`.

## Remove

```bash
omarchy plugin remove io.github.ilyazar.keyboard-layout --yes
```

## License

MIT
