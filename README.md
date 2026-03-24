# ElementalDPS

`ElementalDPS` is a simple one-button priority addon for Elemental Shaman on Turtle WoW.

It is built for a macro-spam playstyle and requires SuperWoW.

## Features

- Keeps your `Flame Shock` up
- Uses `Molten Blast` in the refresh window
- Maintains your chosen shield
- Uses `Chain Lightning` on the second `Clearcasting` charge
- Falls back to `Lightning Bolt`
- Optional `Lightning Bolt` downranking at low mana
- In-game config window
- Minimap button

## Install

1. Copy the `ElementalDPS` folder into your `Interface\\AddOns` folder.
2. Restart the game.
3. Enable the addon on the character select screen.

## Macro

Create a macro with:

```lua
/edps dps
```

Spam that macro in combat.

## Commands

- `/edps dps` runs the next action
- `/edps status` prints current addon state
- `/edps config` opens the config window
- `/edps debug` toggles debug output
- `/edps reset` resets settings

`/srh` also works as an alias.

## Minimap Button

- Left-click: open config
- Right-click: print help
- Drag: move the button

## Notes

- SuperWoW is required
- This addon is made for Turtle WoW
