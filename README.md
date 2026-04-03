# 7d2d-easy-honey

A lightweight XML-only modlet for **7 Days to Die v2.6** that makes honey significantly easier to obtain throughout the game.

---

## Features

| Source | Vanilla Chance | Modded Chance |
|---|---|---|
| Tree Stump (landscape) - Harvest | ~20 % | **45 %** |
| Tree Stump (landscape) - Destroy | ~20 % | **25 %** |
| Tree Stump (POI) - Harvest | ~40 % | **55 %** |
| Tree Stump (POI) - Destroy | ~40 % | **35 %** |
| Medicine Cabinet loot group | low | **18 %** |
| Kitchen Cupboard loot group | very low/none | **7 %** |
| Junk / Trash Shelves loot group | none | **5 %** |
| Garbage / Fast-Food Trash loot group | none | **3 %** |

---

## Mod Structure

```
Mods/
└── EasyHoney/
    ├── ModInfo.xml          ← Mod metadata (name, version, author)
    └── Config/
        ├── blocks.xml       ← XPath patches for tree-stump harvest/destroy drops
        └── loot.xml         ← XPath patches for loot container groups
```

---

## Installation

1. Download or clone this repository.
2. Copy the **`Mods/EasyHoney`** folder into your game's `Mods` directory:
   - **Windows (Steam):** `C:\Program Files (x86)\Steam\steamapps\common\7 Days To Die\Mods\`
   - **Linux (Steam):** `~/.steam/steam/steamapps/common/7 Days To Die/Mods/`
   - **Dedicated Server:** `<server_root>/Mods/`
3. Start the game (or restart the server). The modlet will be loaded automatically.

> **Note:** Create the `Mods` folder if it does not already exist.

---

## Compatibility

- **Game version:** 7 Days to Die **v2.6** (Alpha 21+)
- **Multiplayer / Dedicated Server:** ✅ Fully compatible (server-side mod)
- **Other mods:** Uses XPath patching — does not overwrite any vanilla file,
  so it works alongside most other modlets.

---

## How It Works

The mod uses **XPath-based XML patching** (the standard 7DTD modlet system) to modify
the game's `loot.xml` and `blocks.xml` files at runtime without replacing them:

- **`Config/blocks.xml`** — Appends `foodHoney` drops to `treeStump` and
   `treeStumpPOI` (harvest + destroy) only when no honey drop exists yet.
- **`Config/loot.xml`** — Appends `foodHoney` to `groupMedicineCabinet`,
   `groupCupboard`, `groupJunk`, `groupGarbage`, and `groupFastFoodGarbage`.

All XPath expressions use safe `[not(...)]` guards to avoid duplicate entries when
the game already includes honey in a group.

---

## Manual In-Game Test Steps

1. Load a new game (or use an existing save).
2. Find a tree stump in the wild and use an axe on it — you should receive honey
   more often than vanilla, but still not every time.
3. Loot a Medicine Cabinet in any house or hospital — honey should appear regularly.
4. Loot a Kitchen Cabinet — honey should occasionally appear.
5. Search a Trash Can or fast-food trash bin — honey should rarely appear.

---

## License

MIT License — see [LICENSE](LICENSE) for details.