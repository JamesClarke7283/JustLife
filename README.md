# JustLife

An original Godot life simulation with Lifelet creation, a shared household, home design, neighborhood visits and stories that continue across days.

Open `project.godot` in Godot 4.7.2, allow the assets to import, then run the main scene. To create a Linux build, use `python tools/export_linux.py` with matching Godot export templates installed; then open `dist/JustLife/JustLife.x86_64`. Build outputs are local and are not committed. A separately downloaded build runs through `JustLife.x86_64` directly. The Linux build uses Vulkan/Forward+; the verified desktop has an NVIDIA RTX 5090. Other graphics hardware has not yet been qualified.

## Playing

Start with **New game**, create up to 8 Lifelets, choose their age, looks, faces, outfits, personality and aspirations, then find a home. Child, teen, young adult, adult and elder stages have matching character models; children need a teen or adult housemate. Connections lets a household begin as housemates, siblings, partners, parents and children. Parents must be adults in an older age stage during creation. **My Lifelet → Family tree** shows the household’s generations; choose a portrait card’s name to read connections from that person’s perspective. Click furniture or a person to choose an activity. Each Lifelet walks to their destination before beginning. The household shares money and time, while each person has their own needs, skills, relationships and queue. Select a household chip to take control of another person.

Children and teens have a **School** panel. Do homework and attend three-hour online classes at a desk on weekdays, starting between 08:00 and 14:00. Homework prepares the next attended class; absences affect grades. School records follow a Lifelet into later age stages. **My Lifelet → Celebrate a birthday** advances one stage after a confirmed §30 activity. **Esc → Life settings** changes lifespan or pauses automatic birthdays for the household. Elders currently stay in their final stage.

At a desk, **Do homework together…** lets a child or teen learn with a trusted household adult. Both walk into position, share progress, and gain friendship and learning when they finish. The helper builds Parenting skill. Canceling from either participant ends the shared activity; saving preserves unfinished work. The HUD identifies the partner, and skill bars show progress toward the next level.

**Explore** opens Juniper Gardens, The Reading Room and Common Ground Studio. Travel takes 15 in-game minutes and brings the household together. **Stories** presents opportunities and personal memories as the days pass. Adult relationships can become partnerships and commitments once mutual friendship and romance requirements are met; breakups have lasting relationship effects. **Build & buy** at home places, rotates, moves and sells furnishings, builds rooms/walls, opens doorways and changes floors.

- Right-drag or Q/E: orbit. Mouse wheel: zoom. WASD/arrows: pan.
- Space: pause. 1/2/3: normal/fast/very fast time.
- B: Build & buy. R: rotate a furnishing. Escape: cancel placement or close a panel/pause.
- F5: quick-save the current named life; creates its first named save when needed.
- F9: open the saved-life picker.

The pause menu opens **Save this life**, with Save as new and confirmed overwrite. The main menu and pause menu open the save picker. **Delete save…** shows the selected name and requires **Delete permanently**; **Keep save** cancels. Deleting a file preserves other saves and the currently open household. Returning to the main menu preserves the current in-memory life; quitting without saving does not.

On Linux, saves normally live at `~/.local/share/godot/app_userdata/JustLife/saves/`, or under the configured XDG data directory. The earlier single-household `justlife_save.json` format remains readable as an Original household entry. Current saves preserve home changes, all household members, queues, paid activity progress, money, time, skills, relationships, stories, age settings/history, school records, directed family connections and the venue being visited.

## Development and verification

`python tools/export_linux.py` imports and builds an isolated release snapshot, removing development MCP autoload/plugin configuration from the exported game while retaining the source editor setup. Matching Godot export templates must be installed. The artifact includes its build manifest and font/engine licenses.

`python tests/run_playthrough.py --suite home` or `--suite neighborhood` runs actual rendered gameplay in isolated copies and userdata, then restarts the game to verify persistence. Dedicated simulation, actor, build and menu tests are in `tests/`. Concise critic reviews are committed in `docs/REVIEWS/`. Screenshots and raw traces are local evidence in `art/screenshots/` or the temporary paths printed by the test runner.

See [the source-tree guide](docs/SOURCE_TREE.md) for the maintained artwork, development tools and local-only artifacts. Godot import settings (`.import`) and resource IDs (`.uid`) remain versioned so fresh checkouts retain the same assets and references.

This is an actively developed game, and the 10/10 target remains open. Current scope does not yet include babies/toddlers, birth/adoption, broader parenting systems, shared meals, death/inheritance, off-household or deceased relatives, step-family labels, stairs/roofs, pets, or the expansive furnishing and occupation catalogs of a commercial life simulation. The latest full-scope independent review is **7.2/10**. The care/v19 build repairs the previous shared-bed starvation: all eight Lifelets kept completing activities across the repeated seven-day fixture, with distinct waiting positions and occupied-object priority preserved through saving. It also includes shared homework and clearer coaching. School/work responsibilities still require direction, autonomous social choices remain repetitive, and character/catalogue depth is unfinished. See `docs/REVIEWS/iteration_10_final.md`; the earlier 6.7/10 failure remains documented in `iteration_09_autonomy.md`. Production characters remain the reviewed v18 assets; the hair study is unpromoted. The game does not yet claim feature parity with The Sims 4.

See `CREDITS.md` for original asset provenance and third-party font/engine notices.
