# True North Command: Operation Alpha

A Canadian military training game (Royal Canadian Navy, Canadian Army, RCAF) where you are scored on how well you read the situation, follow orders, and act on your commander's intent. It is not scored on speed. Internal code name: **MI-Alpha**.

Concept bible: https://claude.ai/artifact/EswvGMng9AJf34WQPcTmKk

## Demo: Operation GHOST CONVOY (3D, English and French)

The game is fully 3D: ships, boats and the helicopter are low-poly models built in code, on a sea with waves under depth fog. Halifax harbour has hills, the city, the two Narrows bridges, dockyard cranes and the Chebucto Head lighthouse. Sable Island has dunes and wild horses. Three cameras: **Chase**, **Bridge** (the Officer of the Watch's view) and **Tactical** (from overhead). A small radar stays on screen.

**Mission 1 · Harbour Departure, Halifax**
- Choose Lt(N) Élise Tremblay or Lt(N) Liam MacLeod, Officer of the Watch on the frigate HMCS *Laurentian* (fictional).
- The briefing uses the real CAF orders format (Situation, Mission, Execution, Service support, Command & signal) plus the commander's intent. Then you read the intent back.
- Take the ship out of Bedford Basin through the Narrows (10-knot limit) in fog. Report radar contacts with bearings in red/green, and use correct radio procedure.
- **The Break:** a mayday comes in while you are escorting MV *Port Royal*. Your decision is scored against the Captain's intent.
- **Echo 1942:** at night, you are the helmsman of a darkened corvette in a convoy and must follow every order exactly through the anti-submarine net gate.

**Mission 2 · Sable Island Boarding**
- Search Sable Island Bank and identify every contact by eye or with the CH-148 Cyclone helicopter.
- **The Break:** an officer relays an order to break off that contradicts the Captain's intent. Obey it, ignore it, or verify it through the chain of command.
- Hail the dark trawler on Channel 16, send the boarding party at 5 knots or less, keep close station, then lead *Port Royal* to the rendezvous.

Each mission ends with an **After Action Review**: your Command Rating across Awareness, Discipline, Initiative, Team and Execution, plus the real history behind the mission.

### Controls
| Action | Keyboard | Touch / mouse |
|---|---|---|
| Engine telegraph | W / S | Astern · Stop · Slow · Half · Full · Flank |
| Rudder | A / D | Port 30 · Port 15 · Midships · Stbd 15 · Stbd 30 |
| Radio action | Space | Radio panel buttons |
| Camera | V (Chase / Bridge / Tactical) | View button; drag to look around |
| Zoom | mouse wheel, + / − | Zoom buttons |

## Builds
`.github/workflows/build.yml` runs on every pull request and every push to `main`. It installs Godot 4.3, plays Mission 1, Echo 1942 and Mission 2 headless in English and French (`tests/autoplay.gd`), checks every screen on phone, tablet, PC and Mac sizes (`tests/screens.gd`), then exports:
- **Web**: deployed to GitHub Pages (Settings → Pages → Source: *GitHub Actions*)
- **Windows**: `TrueNorthCommand.exe`, no installer. It updates itself: a newer version is downloaded and swapped in for the next start.
- **Mac**: `TrueNorthCommand-mac.zip` (Apple silicon and Intel)
- **Android**: `TrueNorthCommand.apk`, signed with the game's own key (GitHub secrets `TNC_KEYSTORE_B64`, `TNC_KEYSTORE_PASSWORD`), so new versions install over the old one. Android and Mac show an **Update** button when a new version is out.

On `main` every build becomes Release `v1.0.N` (with `version.json` for the updater and the source code) and refreshes the rolling `latest` downloads.

## Phones, tablets, PC and Mac
The HUD lays itself out for the screen (`_apply_screen` and `_layout` in `scripts/main.gd`): portrait stacks helm, log and radio at the bottom; a phone on its side gets a shorter canvas so buttons stay at least 28 px. `tests/screens.gd` fails the build if anything runs off the screen, panels overlap, or text and buttons get too small.

## ✦ Ask Claude
The ✦ button opens a coach (`scripts/copilot.gd`) that explains orders and the Captain's intent and corrects radio procedure, using what is happening in the mission. It uses the player's own Claude key from console.anthropic.com, kept on the device only.

### Local
```
godot --headless -s tests/autoplay.gd          # smoke test
godot --headless -s tests/screens.gd           # screen check
godot --headless --export-release "Web" build/web/index.html
```

## Project layout
```
main.tscn            single scene; everything is built in code
scripts/main.gd      mission flow, scoring, UI and screen layout, radar, 1942 Echo
scripts/copilot.gd   ✦ Ask Claude coach
scripts/updater.gd   update check and Windows self-update
scripts/world.gd     Halifax Harbour chart and water/land test
scripts/vessel.gd    ships, boats and the player's frigate/corvette
tests/autoplay.gd    headless playthrough used by CI
tests/screens.gd     screen check used by CI
```

All characters, ships (HMCS *Laurentian*, HMCS *Rosedale*, MV *Port Royal*, FV *Lady Hannah*) and the Kestrel Network are fictional. Places, ranks and history are real. CAF insignia are not used.
