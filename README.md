# RUblocks

RUblocks is a Windows desktop 3D sandbox prototype built with Godot 4. This repository keeps the source editable rather than hiding the game inside an EXE.

## Included in this milestone

- Blue startup/loading screen and a dark main menu.
- Login/register screen with rotating, falling red 3D cubes over a black background.
- 3D test place, WASD/arrow movement, jump, chat and Escape menu.
- Player list, settings, leave button, and reset controlled by the place author's reset setting.
- Place editor: add cubes, edit name/colour/scale/collision, set spawn, add a background/cover image, save locally and publish/update using the Worker API.
- Visual rule palette with **144 prebuilt event/action combinations**.
- Script-text panel for notes/prototypes. Arbitrary GDScript entered there is not executed.
- Cloudflare Worker source, D1 schema, Durable Objects room class and an export preset.
- GitHub Actions workflow that exports a Windows executable when the build succeeds.

## Download the Windows EXE

1. Open the **Actions** tab in this repository.
2. Open the latest **Build Windows EXE** workflow run.
3. If it finishes successfully, download the artifact named **RUblocks-Windows-EXE**. It contains RUblocks.exe.

The first workflow run can fail if the latest upstream Godot release changes its asset names. If it fails, open the failed step and share its log.

## Run locally in Godot

Install Godot 4 and its export templates, then open project.godot in Godot. Press F6/F5 to run the prototype. To export manually, select the Windows Desktop preset.

## Server setup

The client uses https://rublocks.boberbuset132013.workers.dev as its API base. Register/login and cloud publishing require a working Worker with D1 binding DB; online chat requires Durable Objects binding ROOMS. See cloudflare/README.md.

## Current prototype limits

- A client EXE is not committed as a binary; GitHub Actions must build it first.
- Online chat/room events need the Worker and Durable Object bindings deployed correctly.
- Player movement/state is not yet authoritative server simulation. After the matching Worker build is deployed, a place-update notice tells connected clients to leave to the menu; this still needs an end-to-end multiplayer test.
- Background/cover images are saved locally. To share images between users, server-side file upload/storage still needs to be added.
- Rule catalogue contains 144 ready-made combinations. Basic actions run in the prototype, but events such as health, death, and objective completion still need gameplay systems to trigger them.
