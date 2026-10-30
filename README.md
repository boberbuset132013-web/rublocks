# RUblocks

RUblocks is a Windows desktop 3D sandbox prototype built with Godot 4. This repository keeps the source editable rather than hiding the game inside an EXE.

## Included in this milestone

- Blue startup/loading screen and a dark main menu.
- Custom white **R** on a red square app/executable icon.
- Login/register screen with rotating, falling red 3D cubes over a black background.
- 3D test place, WASD/arrow movement, jump, chat and Escape menu.
- Player list, settings, leave button, and reset controlled by the place author's reset setting.
- Character wardrobe with rotatable 3D preview, clothing colour presets, hat toggle and local save.
- Scene Explorer `+` menu with 20 object types: primitives, platforms, spawn, tools, ore, tree, crate, door, button and lamp.
- Object editor with position, rotation, size, collision, pickupable items, colour and imported image textures.
- Five-slot inventory, item pickup, pickaxe/ore, axe/tree and hammer/crate resource loops.
- Exactly **100 visual event/action rules** and a small safe RUscript command interpreter for optional scripting.
- Cloudflare Worker source, D1 schema, Durable Objects room class and an export preset.
- GitHub Actions workflow that exports a Windows executable when the build succeeds.

## Download the Windows installer

1. Open the [latest Build Windows EXE run](https://github.com/boberbuset132013-web/rublocks/actions/workflows/build-windows.yml).
2. Open the newest completed run and scroll to **Artifacts**.
3. Download **RUblocks-Setup-Installer**. Run `RUblocks-Setup.exe`; it installs the game into your user Programs folder and creates a Start menu shortcut plus a desktop shortcut by default.
4. For the portable application file, download **RUblocks-Windows-EXE** instead.

The workflow validates GDScript, starts the project headlessly to catch startup errors, and exports the Windows EXE only if those checks pass.

## Run locally in Godot

Install Godot 4 and its export templates, then open project.godot in Godot. Press F6/F5 to run the prototype. To export manually, select the Windows Desktop preset.

## Server setup

The client uses https://rublocks.boberbuset132013.workers.dev as its API base. Register/login and cloud publishing require a working Worker with D1 binding DB; online chat requires Durable Objects binding ROOMS. See cloudflare/README.md.

## Current prototype limits

- The setup EXE is produced by GitHub Actions after the application export job succeeds.
- Online chat/room events need the Worker and Durable Object bindings deployed correctly.
- Player movement/state is not yet authoritative server simulation. After the matching Worker build is deployed, a place-update notice tells connected clients to leave to the menu; this still needs an end-to-end multiplayer test.
- Background/cover images are saved locally. To share images between users, server-side file upload/storage still needs to be added.
- Some of the 100 visual rule events are framework hooks and still need their gameplay systems (for example a full health/death/objective system). RUscript is a constrained command language, not a general-purpose GDScript runtime.
- Imported textures are currently stored locally with the project. Shared image upload has not been connected to Cloudflare.
- Multiplayer still requires the Worker/D1/Durable Objects configuration and an end-to-end test. Player movement is not yet authoritative server simulation.
