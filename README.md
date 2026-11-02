# Ethernet for Omarchy

An Omarchy bar widget for wired connections. It appears only while a cable is
plugged in and puts the parts of `nmtui` you use every day one click away:
which profile is up, what IP you got, switching between saved profiles, and
flipping a profile between DHCP and a static address.

Built for laptops that hop between many wired networks (plant floors, PLC
subnets, lab benches) where each network has its own saved profile.

## Features

- Bar icon shows up when the kernel reports carrier on a wired port and hides
  when the cable comes out. Dimmed while no profile is active.
- Live link details: address, gateway, DNS, method, interface, MAC, speed.
  Click a value to copy it.
- Profile switcher with a filter by name or address. Active profile first.
- Inline editor for DHCP / static IPv4 (address, gateway, DNS) on any profile,
  plus creating new profiles. New profiles have autoconnect off, so a site
  profile never grabs the cable on its own somewhere else.
- `nmtui` one key away for everything else (routes, VLANs, 802.1X, deletes).

## Requirements

- NetworkManager (`nmcli`, `nmtui`)
- `wl-copy` for the copy actions

## Install

```bash
omarchy plugin add https://github.com/alde103/omarchy-ethernet.git --enable --yes
```

Or clone it into `~/.config/omarchy/plugins/alde103.ethernet/`, then run
`omarchy-shell shell rescanPlugins` and `omarchy plugin enable alde103.ethernet`.

## Mouse

- Left click: open the panel
- Right click: connect / disconnect the cable

## Keys inside the panel

| Key | Action |
| --- | --- |
| `j` / `k` / arrows | Move through profiles |
| `enter` / `space` | Activate the selected profile |
| `/` | Filter profiles (`enter` or `↓` jumps into the results) |
| `e` | Edit the selected profile (or the active one) |
| `n` | New profile |
| `d` | Connect / disconnect |
| `c` | Copy the current IP |
| `t` | Open `nmtui` |
| `r` | Refresh |
| `esc` | Close the editor, then the panel |

## Settings

Set with `omarchy bar set alde103.ethernet <key> <value> --json`.

| Key | Default | Meaning |
| --- | --- | --- |
| `showAddress` | `false` | Show the IP next to the bar icon |
| `alwaysShow` | `false` | Keep the icon visible without a cable |
| `refreshIntervalSec` | `3` | How often to check for a cable |

## Helper script

All NetworkManager calls live in [`ethernet`](ethernet), which also works on
its own:

```bash
./ethernet status
./ethernet profiles
./ethernet set <uuid> manual 192.168.1.50/24 192.168.1.1 "1.1.1.1, 8.8.8.8"
./ethernet new "Bench" auto
```

Input is validated before anything reaches `nmcli`, so a typo never leaves a
profile half-changed.
