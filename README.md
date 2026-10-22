# True North Command: Operation Alpha

A Canadian military training game (Royal Canadian Navy, Canadian Army, RCAF) where you are scored on how well you read the situation, follow orders, and act on your commander's intent. It is not scored on speed. Internal code name: **MI-Alpha**.

Concept bible: https://claude.ai/artifact/EswvGMng9AJf34WQPcTmKk

## Demo: Operation GHOST CONVOY, Mission 1 "Harbour Departure, Halifax"

- Choose Lt(N) Élise Tremblay or Lt(N) Liam MacLeod, Officer of the Watch on the frigate HMCS *Laurentian* (fictional).
- The briefing uses the real CAF orders format (Situation, Mission, Execution, Service support, Command & signal) plus the commander's intent. Then you read the intent back.
- Take the ship out of Bedford Basin through the Narrows (10-knot limit) in fog. Report radar contacts with bearings in red/green, and use correct radio procedure.
- **The Break:** a mayday comes in while you are escorting MV *Port Royal*. Your decision is scored against the Captain's intent.
- **After Action Review:** your Command Rating across Awareness, Discipline, Initiative, Team and Execution.
- **Echo 1942:** you are the corvette helmsman in a blacked-out convoy and must follow every order exactly.

### Controls
| Action | Keyboard | Touch / mouse |
|---|---|---|
| Engine telegraph | W / S | Astern · Stop · Slow · Half · Full · Flank |
| Rudder | A / D | Port 30 · Port 15 · Midships · Stbd 15 · Stbd 30 |
| Radio action | Space | Radio panel buttons |
| Zoom | mouse wheel, + / − | Zoom buttons |

## Builds
`.github/workflows/build.yml` runs on every push to `main`. It installs Godot 4.3, runs the headless smoke test (`tests/autoplay.gd` plays the whole mission), then exports:
- **Web**: deployed to GitHub Pages (Settings → Pages → Source: *GitHub Actions*)
- **Windows**: `TrueNorthCommand.exe` (workflow artifact; attached to a Release when you push a `v*` tag)
- **Android**: `TrueNorthCommand.apk`, signed with a debug key, for sideloading. Use a real upload key before any Play Store release.

### Local
```
godot --headless -s tests/autoplay.gd          # smoke test
godot --headless --export-release "Web" build/web/index.html
```

## Project layout
```
main.tscn            single scene; everything is built in code
scripts/main.gd      mission flow, scoring, UI, radar, 1942 Echo
scripts/world.gd     Halifax Harbour chart and water/land test
scripts/vessel.gd    ships, boats and the player's frigate/corvette
tests/autoplay.gd    headless playthrough used by CI
```

All characters, ships (HMCS *Laurentian*, HMCS *Rosedale*, MV *Port Royal*, FV *Lady Hannah*) and the Kestrel Network are fictional. Places, ranks and history are real. CAF insignia are not used.
