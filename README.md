# Keyboard Layout Pulse

An Omarchy Quattro bar widget for switching between configured Hyprland XKB
layouts. The current layout pulses after a change. Press the widget to open a
native Quattro picker, or use the mouse wheel to cycle layouts.

The settings page offers teal (`#2aa198`), purple (`#a77bd8`), blue
(`#3b82f6`), or any custom `#RRGGBB` pulse color.

## Requirements

- Omarchy Quattro
- Hyprland with two or more XKB layouts configured

## Install

```bash
omarchy plugin add \
  https://github.com/ilyaZar/omarchy-keyboard-layout.git --enable
omarchy bar move io.github.ilyazar.keyboard-layout --after omarchy.clock
```

## Remove

```bash
omarchy plugin remove io.github.ilyazar.keyboard-layout --yes
```

The plugin reads keyboard state through `hyprctl`. It does not modify the
Hyprland input configuration.

## Local development

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/io.github.ilyazar.keyboard-layout
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.ilyazar.keyboard-layout --after omarchy.clock
```

## Validate

```bash
omarchy plugin validate .
```

## License

MIT
