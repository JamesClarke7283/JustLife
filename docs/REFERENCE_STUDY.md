# JustLife reference study

Research milestone: 7 September 2026. Characters in JustLife are called **Lifelets**.

The browser archive is at /home/impulse/Downloads/The Sims 4 References. It contains **435 distinct image files by SHA-256**, of which **347 meet a screenshot-size threshold of 250 × 140 pixels**. This includes cropped interface panels, tutorial comparisons and title composites; it is not a claim of 347 full-screen gameplay captures. The remaining images are mostly trait, aspiration and skill icons. There are 29 full-resolution 1920 × 1080 interface screenshots, six initial official EA screenshots/thumbnails, 33 additional topic collections, and 39 topic contact sheets. Initial low-resolution browser thumbnails are retained separately and excluded from these counts.

All remote image acquisition used the in-app browser's pageAssets.list and pageAssets.bundle on observed page assets. The local organizer copies those downloads, records source pages and hashes, and produces contact sheets. The archive_manifest.json records each archived path, URL, dimensions and hash; source_pages.json groups the additional collections. Images are research material, not JustLife assets. The game's models, textures, icons, names and interface presentation are original work.

This milestone maps the major base-game flow and main system families. It does **not** exhaust every interaction, current patch, expansion or catalog item. The precise evidence and gaps are in GAME_COVERAGE_MAP.md.

## Character creation and art

The character occupies the open center, large enough to inspect shape and clothing. Controls follow the subject: body, face/hair/clothing categories, then thumbnails and swatches. Identity and personality form a distinct information group. Household portraits keep the active person obvious. The [interface capture set](https://interfaceingame.com/games/the-sims-4/) shows face detail, eyebrows, full-body clothing, shoes, hats, walk style, traits and move-in. Pet paint and clothing are Cats & Dogs content.

Preserve the process in JustLife: identify a Lifelet, give them a recognizable silhouette and palette, choose personality and a long-term aim, add household members, then choose a home. Meaningful differences between people require more than material recolors. Close-up editing demands better anatomy and surface continuity than the live camera. Identity is intentionally chosen rather than inferred from appearance. [EA gender, romance and attraction guide](https://help.ea.com/en/articles/the-sims/the-sims-4/gender-romance-attraction-guide/).

The reference characters have stylized human proportions, clear cheek/jaw/nose/lip forms, eyes integrated into faces, hair sections with directional detail, and structured clothing. Posture, head direction and hand contact sell activity. Cooking shows hands holding bowls and utensils; children bend over homework; families sit at shared tables; conversations change facial and hand poses. [EA screenshot examples](https://www.ea.com/games/the-sims/the-sims-4/news/screenshot-tips-sims), [children references](https://www.carls-sims-4-guide.com/parenting/children.php).

Lifelets need continuous face/joint surfaces, distinct hair silhouettes, believable hems/collars, and convincing whole-body gestures. Silhouette and object contact matter more than hidden triangles. Neutral faces cannot communicate every mood through a recolored HUD label. Original wordless voices should vary by interaction. Animation and sound need playthrough review; still images cannot establish timing.

## Live mode

The playfield dominates. Persistent information stays at its edges: active portrait and mood lower left, household switching nearby, clock/speed bottom, needs/progression right. Context choices stay visually associated with the clicked person or object. Conversation status, progress and notices explain consequences without permanently obscuring rooms. [Interface examples](https://interfaceingame.com/games/the-sims-4/), [relationships](https://www.carls-sims-4-guide.com/relationships/), [career progression](https://www.carls-sims-4-guide.com/careers/tips.php).

The loop is visible cause and effect: a need or aim creates intent; an object/person offers choices; the character routes and performs an action; mood, needs, skills, relationships or money change. Queue, pause and speed controls make this manageable across a household. A faithful implementation shows actions in the world. Instantly changing a number represents only a small part of that system.

## Build and buy

Build mode treats rooms as editable volumes. Images show wall drawing, room selection, move/rotate handles, dimensions/cost, foundations, stairs, roofs, trim, fencing and pools. Roof handles alter pitch, height and overhangs. Room movement preserves contents. Floor/ceiling distinctions and cutaway walls make levels intelligible. [Walls and rooms](https://www.carls-sims-4-guide.com/tutorials/building/houses.php), [roofs](https://www.carls-sims-4-guide.com/tutorials/building/roofs.php), [stairs and basements](https://www.carls-sims-4-guide.com/tutorials/building/stairs-basements.php).

The catalog needs recognizable thumbnails, price/function information, categories, filters and swatches. Placement needs a valid/invalid preview, rotation and cancellation. A furniture menu is not equivalent to building. The home needs coherent materials: wall thickness, baseboards, frames, consistent prop scale, softened edges, varied furniture silhouettes and intentional layouts. [Landscaping and pools](https://www.carls-sims-4-guide.com/tutorials/building/decorating-landscaping.php), [easel catalog example](https://www.carls-sims-4-guide.com/skills/painting/).

## Progression and household life

Progression is layered: skills advance through activities, careers have schedules/performance/requirements, aspirations expose goals/rewards. Relationships persist beyond a single chat, with friendship and romance distinct. Family life changes the objects and care routines required across life stages. The archive includes pregnancy/newborns, infant care, toddlers, children, aging and death. Early guides are historical: the infant supplement prevents relying on outdated newborn-to-child progression. [Careers](https://www.carls-sims-4-guide.com/careers/), [romance](https://www.carls-sims-4-guide.com/relationships/romance.php), [infant care](https://simscommunity.info/2023/03/15/sims-4-infant-care-guide/).

World management is a separate flow: world, lot, affordability and furnishing choice, then household entry. Management supports transfers/splits/rotation. The phone accesses services, delivery, travel and social arrangements. Neighborhood Stories configures unplayed-household changes. These provide long-term context that one isolated house cannot demonstrate. [Moving households](https://www.carls-sims-4-guide.com/tutorials/moving-sims.php), [phone](https://simscommunity.info/2022/11/07/the-sims-4-beginners-guide-to-your-sims-phone/), [Neighborhood Stories](https://www.ggrecon.com/guides/sims4-neighbourhood-stories/).

## Implementation review priorities

1. Verify the whole first-session loop in the actual game: creator, home choice, live interactions, household switching, building, save/reload.
2. Fix clipping, unreadable controls and failed actions before expanding option counts. Players must predict clicks and recognize success.
3. Judge Lifelets close-up and at the live camera, including eye corners, garment seams, sitting/lying alignment, walking and object contact.
4. Preserve breadth honestly in the coverage map. A polished small slice can have good presentation and still fall short of the full requested scope.

The independent critic uses QUALITY_RUBRIC.md. The latest Lifelet sculpture scored **6/10 for character visuals only**, up from 4 and 5.5 after concrete improvements. Game flow, animation, sound and reliability require separate evidence.
