# 🐉 Dungeon Crawler — x86 Assembly (MASM32)

A complete, turn-based **dungeon crawler written entirely in 32-bit MASM assembly** using the **Irvine32** library. Explore 10 levels of mazes, fight goblins and dragons, collect loot, unlock vaults, spend gold in a shop, and survive the shifting maze of the final level — all in a Windows console.

Built as a semester project for the **Computer Organization & Assembly Language (COAL)** course.

<!-- Add a screenshot: put it in a docs/ folder and uncomment the next line
![Gameplay](docs/gameplay.png)
-->

---

## ✨ Features

- **10 levels** of increasing difficulty — monsters get +10 % HP and +1 damage for every level
- **Turn-based combat** against **goblins** and **dragons** (attack, drink a potion, or try to run)
- **Run = dodge:** 50 % chance to slip past the monster and land 3 tiles away
- **Locked vaults** — find keys 🔑 to open doors 🚪 guarding weapons, armor and potions
- **Shop** — spend gold on permanent Health, Attack and Resistance upgrades (levels 1–10)
- **Smart enemies** — monsters chase you along the shortest path (breadth-first search)
- **Fog of war** — you only see nearby tiles; explored areas are remembered
- **Level 10: the shifting maze** — every **10 seconds** the whole maze (and the exit) is replaced by one of 25 preloaded maps
- **Emoji graphics** with solid colored wall blocks (toggle back to colored letters any time)
- **Sound effects**, **save / load**, and a persistent **high score**
- **50 pre-generated, verified maps** (every one is guaranteed solvable)

---

## 🎮 Controls

| Key | Action |
|---|---|
| `W` `A` `S` `D` | Move |
| `I` | Inventory (drink a potion) |
| `B` | Open the shop |
| `V` | Save game |
| `L` | Load game |
| `F` | Toggle fog of war |
| `M` | Toggle sound |
| `E` | Toggle emoji / colored letters |
| `Q` | Quit |

In combat: `A` attack · `P` potion · `R` run.

---

## 🗺️ Legend

| Emoji | Letter mode | Meaning |
|:---:|:---:|---|
| 🧙 | `@` | You |
| 👺 | `M` | Goblin |
| 🐉 | `D` | Dragon |
| 💰 | `$` | Gold |
| 🧪 | `P` | Healing potion |
| 🏹 | `W` | Weapon (+3 attack) |
| 🧥 | `A` | Armor (monsters hit 2 less) |
| 🔑 | `K` | Key |
| 🚪 | `L` | Locked door (needs a key) |
| 🏁 | `E` | Exit |
| brown block | `#` | Wall |

---

## 🏆 How to win

Clear a level by **reaching the exit 🏁** or **defeating every monster**. Each level you clear gives **+25 gold** and **+50 HP**, then opens the shop. Beat level 10 to win — your score is based on gold, kills, remaining HP and the level you reached.

### 🛒 Shop

| Upgrade | Effect per level | Cost of the next level |
|---|---|---|
| ❤️ Health | +10 max HP (100 → 110 → 120 …) | 50 + 25 × (level − 1) |
| ⚔️ Attack | +2 damage | 60 + 30 × (level − 1) |
| 🛡️ Resistance | +1 damage blocked | 60 + 30 × (level − 1) |

---

## ⬇️ Play it now (no build needed)

1. Download **`DungeonCrawler.exe`** from the [`bin/`](bin/DungeonCrawler.exe) folder, or from the [Releases page](https://github.com/M-sohaib-Hafeez/Dungeon-Crawler-Assembly-level-game-/releases).
2. Run it from **Windows Terminal**: open the folder with the `.exe`, right-click an empty spot → **Open in Terminal**, then type `.\DungeonCrawler.exe`. (On Windows 11, double-clicking the file usually opens it in Windows Terminal as well.)
3. If the emoji look broken (older console window), press **`E`** in the game to switch to colored letters.

> **Windows SmartScreen** may say *"Windows protected your PC"* because the program isn't code-signed. Click **More info → Run anyway**.
> The game creates `savegame.dat` and `highscore.dat` next to the `.exe`.

---

## 🛠️ Requirements

- **Windows** (the game uses the Win32 console, `Beep`, and Unicode output)
- **Visual Studio** with the *Desktop development with C++* workload (includes MASM)
- **Irvine32 library** — Kip Irvine's library from the book *Assembly Language for x86 Processors* (the project is configured for `C:\Irvine`)
- **Windows Terminal** (recommended) — needed to display the emoji. In the old console window, press `E` to switch to colored letters.

---

## ▶️ Build & run

1. Install the Irvine32 library and note its folder (default in this project: `C:\Irvine`).
2. Open **`Coal-Project-Final.slnx`** in Visual Studio.
3. Check *Project → Properties* (all configurations, **Win32**):
   - **Microsoft Macro Assembler → General → Include Paths:** your Irvine folder
   - **Linker → General → Additional Library Directories:** your Irvine folder
   - **Linker → Input → Additional Dependencies:** `irvine32.lib;kernel32.lib;user32.lib`
   - **Linker → System → SubSystem:** `Console`
4. **Only `main.asm` is assembled.** Every other `.asm` file is pulled in with `INCLUDE`, so each of them must be set to *Excluded From Build = Yes* (right-click the file → Properties).
5. Press **Ctrl + F5** (or build and run `Debug\Coal-Project-Final.exe` inside Windows Terminal).
6. For a distributable build, switch the toolbar from **Debug** to **Release** (platform **x86 / Win32**) and choose *Build → Rebuild Solution*. The program is written for 32-bit, so always use Win32.

> `savegame.dat` and `highscore.dat` are created in the game's working directory.

---

## 📁 Project structure

```
Dungeon-Crawler-Assembly-level-game-/
├── README.md
├── .gitignore
├── Coal-Project-Final.slnx             ← Visual Studio solution
├── bin/
│   └── DungeonCrawler.exe              ← ready-to-play Windows build (Release, 32-bit)
└── DungeonCrawler/                 ← the Visual Studio project
    ├── Coal-Project-Final.vcxproj
    ├── Coal-Project-Final.vcxproj.filters
    ├── main.asm        ← shared variables, game loop, input handling
    ├── map.asm         ← map loading, fog of war, colored blocks + emoji drawing
    ├── player.asm      ← movement, pickups, keys & doors, run/dodge
    ├── combat.asm      ← turn-based combat and monster scaling
    ├── enemy.asm       ← enemy AI (BFS chase), win check, score
    ├── shop.asm        ← shop and upgrade logic
    ├── shift.asm       ← level 10: shifting maze and countdown timer
    ├── ui.asm          ← HUD, messages, inventory, sound, end screens
    ├── save.asm        ← save / load game and high-score file
    ├── leveldata.asm   ← the 50 pre-generated maps (generated file)
    └── genmaps.py      ← Python script that generates and verifies leveldata.asm
```

Only `main.asm` is assembled; the other `.asm` files are included by it (see *Build & run*). Files created while playing (`savegame.dat`, `highscore.dat`) and Visual Studio's build folders (`Debug/`, `Release/`) are not part of the repository.

The program is split into modules with the `INCLUDE` method, so each part can be worked on separately. Every procedure documents its inputs, outputs and the registers it uses in a comment above it.

---

## 🧩 How the maps are made

`genmaps.py` builds all 50 maps and **proves each one is winnable** before writing `leveldata.asm`:

- mazes are carved, then dead ends are turned into loops so there is never a single long road
- locked vaults, keys, monsters and items are placed by rule
- a solver replays the game's real key-and-door rules to confirm every tile is reachable and the exit can always be reached
- each level also guarantees a small number of unavoidable fights, while leaving the rest avoidable

To regenerate: `python genmaps.py` (run it in the project folder with the `.asm` files).

---

## 👥 Credits

| | |
|---|---|
| **Muhammad Sohaib Hafeez** — game design & development | [@M-sohaib-Hafeez](https://github.com/M-sohaib-Hafeez) |
| **Dua Sohail** — testing, bug fixes & game features | [@Dua-Sohail](https://github.com/Dua-Sohail) |

**Dua Sohail** led user-side testing and QA, identified and fixed bugs, recommended code and gameplay improvements, and contributed key game features to enhance overall functionality and user experience. Thank you!

---

## 📜 License

This project is licensed under the [MIT License](LICENSE).
