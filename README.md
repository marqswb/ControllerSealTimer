# Controller Seal Timer

WoW Forever addon. When you cast a paladin seal it starts its own 30 second clock and draws the seconds left on the controller button that currently shows that seal.

It does not read the buff. Combat hiding aura data does not matter. Holding LT, RT, or both follows the seal onto whichever button is showing it. Judgement does not cancel the timer, because on Forever Judgement does not consume the seal.

A `/reload`, a death, or logging in clears the clock, because the cast that started it was not seen. Cast the seal again.

## Install

Quit the game, then put this folder here (the folder name and the `.toc` name must match):

```
World of Warcraft\_forever_\Interface\AddOns\ControllerSealTimer\
```

The Battle.net / Steam install is usually:

```
C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\ControllerSealTimer\
```

That folder must contain `ControllerSealTimer.toc` and `ControllerSealTimer.lua` directly, not one directory deeper.

From the `AddOns` folder:

```
git clone https://github.com/marqswb/ControllerSealTimer.git
```

Start the game fully after the first copy. `/reload` is not enough the first time an addon is added. In the character list, AddOns, enable **Controller Seal Timer**.

## Try it

1. Turn on the controller layout and put a spell on a face button or the D-pad.
2. `/cst test` paints a countdown on the first visible controller button that has a spell.
3. `/cst test Seal of Righteousness` paints it only on the button showing that spell. The seal has to already be on a controller button.
4. `/cst debug` lists every visible controller button and the spell on it. If this says 0 buttons, the gamepad bars were not found.
5. Cast Seal of Righteousness (or any other seal). The number on its icon counts down from 30. Under 5 seconds it turns red.

## Commands

| Command | What it does |
| --- | --- |
| `/cst` | Seconds left, and how many controller buttons were found |
| `/cst test` | Fake timer on the first visible controller spell, so you can check placement |
| `/cst test Seal of Righteousness` | Fake timer matched to that spell name |
| `/cst debug` | List visible controller buttons and their spells |
| `/cst clear` | Drop the current timer |
| `/cst duration 30` | Seconds to count after each cast. Saved. |
| `/cst add Seal of Fury` | Also time a spell the built-in seal list missed. Saved. |
| `/cst remove Seal of Fury` | Stop tracking that extra name |

Only one timer runs. Casting a different seal replaces it.

Built-in names are anything starting with `Seal of` (plus the same word in German, French, Spanish, Portuguese, Italian, Russian, Polish, and Hungarian) and any spell whose name contains 圣印 / 聖印. Other client languages need `/cst add` with the spell name exactly as the client shows it.
