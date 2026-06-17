# Just Life — A Sims Clone

## Overview

Just Life is a 3D life simulation game inspired by The Sims, built with Bevy (Rust). Players create and control simulated people ("Sims") who live in houses, pursue careers, form relationships, and try to satisfy their needs. The game uses low-poly 3D primitives with AI-generated textures, compiles to WASM for browser play, and features autonomy-driven AI, build/buy mode, needs systems, social interactions, careers, and more.

**Tech Stack:** Bevy 0.15+ (Rust ECS game engine), wgpu renderer, WASM export, MCP image generation for textures

---

## Phase 1: Project Setup & Build Pipeline

- [x] **1.1** Initialize Rust project with Bevy
  - Run `cargo init --name just-life`
  - Add `bevy` dependency to `Cargo.toml` (latest stable version, with dynamic_linking for dev)
  - Add `bevy` features for 3D rendering, WASM support
  - Create `.cargo/config.toml` with dev optimizations for faster iteration

- [x] **1.2** Configure WASM build target
  - Add `wasm32-unknown-unknown` target via `rustup`
  - Create `Cargo.toml` profile for WASM release (opt-level = "s", lto = true)
  - Add `wasm-bindgen` dependency for WASM interop
  - Create `build-wasm.sh` script that builds for WASM and generates glue JS
  - Create `index.html` with canvas and WASM loader for browser testing
  - Add `web-sys` and `wasm-bindgen-futures` dependencies

- [x] **1.3** Set up project directory structure
  - Create `src/` with `main.rs`, `lib.rs`
  - Create module structure: `src/core/`, `src/sim/`, `src/world/`, `src/ui/`, `src/interaction/`, `src/career/`, `src/social/`, `src/audio/`, `src/assets/`, `src/wasm/`
  - Create `assets/` directory with subdirs: `textures/`, `models/`, `fonts/`, `sounds/`, `music/`
  - Create `assets/textures/` placeholder for generated textures

- [x] **1.4** Configure linting and formatting
  - Add `rustfmt.toml` with project formatting rules
  - Add `clippy.toml` with lint configuration
  - Ensure `cargo clippy` and `cargo fmt` pass on initial scaffold

- [x] **1.5** Create minimal Bevy app skeleton
  - `main.rs`: spawn 3D camera, default lighting, and a ground plane
  - Verify it runs natively with `cargo run`
  - Verify it builds for WASM with `build-wasm.sh`
  - Take browser screenshot to confirm WASM pipeline works

- [x] **1.6** Set up hot-reload and dev workflow
  - Configure Bevy asset hot-reload for dev iterations
  - Document dev workflow in AGENTS.md (build command, test command, WASM deploy)
  - Test that asset changes are reflected without restart

## Phase 2: Core ECS Architecture

- [x] **2.1** Define core Bevy plugins
  - Create `CorePlugin` — registers all resources, events, and core systems
  - Create `SimPlugin` — registers sim-related components and systems
  - Create `WorldPlugin` — registers world/lot components and systems
  - Create `InteractionPlugin` — registers interaction/pie-menu systems
  - Create `UIPlugin` — registers UI components and systems
  - Create `AudioPlugin` — registers audio systems
  - Create `CareerPlugin` — registers career systems
  - Create `SocialPlugin` — registers relationship/social systems
  - Create `BuildModePlugin` — registers build/buy mode systems
  - Create `TimePlugin` — registers time/speed control systems

- [x] **2.2** Define core resources
  - `GameTime` resource — tracks in-game time (days, hours, minutes), speed multiplier
  - `GameSpeed` enum — Pause, Normal (1x), Fast (2x), Ultra (4x)
  - `GameState` enum — MainMenu, LiveMode, BuildMode, BuyMode, CreateASim, Loading
  - `MoneyResource` — global economy tracker (for debugging/balance)
  - `GameConfig` — configurable constants (needs decay rates, salary amounts, etc.)
  - `SelectionResource` — currently selected sim/entity

- [x] **2.3** Define core events
  - `NeedChangeEvent` — fired when a sim's need level changes significantly
  - `InteractionEvent` — fired when a sim starts/completes an interaction
  - `TimeTickEvent` — fired each game-time tick for periodic updates
  - `SocialEvent` — fired on social interaction (conversation, romance, conflict)
  - `CareerEvent` — fired on promotion, demotion, firing, hiring
  - `BuildModeEvent` — fired when objects are placed, moved, deleted
  - `SimSpawnEvent` — fired when a new sim is created
  - `SimDeathEvent` — fired when a sim dies

- [x] **2.4** Define core component traits and markers
  - `Interactable` marker component — marks entities that sims can interact with
  - `SimControlled` marker — marks the currently player-controlled sim
  - `Named` component — entity has a display name
  - `Describable` component — entity has a description text
  - `Sellable` component — entity has a monetary value (for buy mode)
  - `RouteTo` component — pathfinding target position
  - `Occupied` marker — object is currently being used by a sim

## Phase 3: 3D Rendering & Camera

- [x] **3.1** Implement isometric-style camera system
  - Create `CameraRig` entity with `Camera3d` and orthographic/perspective projection
  - Set default camera angle (45-degree downward, rotated 45-degrees horizontally — classic isometric)
  - Allow smooth camera rotation around Y axis (quarter-turn snaps)
  - Allow camera zoom (scroll wheel) with min/max bounds
  - Allow camera pan (middle-mouse drag or WASD keys)

- [x] **3.2** Implement camera follow mode
  - Camera follows selected sim with smooth lerp
  - Toggle between free-camera and follow-camera with key press
  - Camera offset maintains isometric angle while tracking

- [x] **3.3** Create ground plane and grid system
  - Generate a large ground plane mesh (green/terrain texture)
  - Implement grid overlay (toggle-able) showing buildable cells
  - Grid cells are 1x1 world unit, matching build mode tile system
  - Grid boundary markers for lot edges

- [x] **3.4** Generate procedural 3D primitives for objects
  - Create a `MeshGenerator` utility that produces common shapes: cubes, cylinders, spheres, cones, planes
  - Each shape can be scaled, rotated, and combined for furniture/objects
  - Create a `ShapeLibrary` resource caching commonly used meshes

- [x] **3.5** Generate textures using MCP image gen tool
  - Generate wall texture (interior plaster, exterior brick)
  - Generate floor texture (hardwood, tile, carpet)
  - Generate roof texture (shingles)
  - Generate grass/terrain texture
  - Generate furniture textures (wood grain, fabric, metal)
  - Generate sim skin/clothing textures
  - Generate UI element textures (buttons, panels, icons)
  - Generate skybox/environment texture
  - Save all generated textures to `assets/textures/`

- [x] **3.6** Apply textures to procedural primitives
  - Create `TexturedPrimitive` component bundle: mesh handle + material handle
  - Implement texture tiling and UV mapping for floor/wall planes
  - Create material library with PBR-like properties (metallic, roughness)
  - Test rendered primitives with textures in viewport

- [x] **3.7** Implement lighting system
  - Add directional light (sun) with time-of-day color changes
  - Add ambient light
  - Add point lights for indoor lighting (lamps, ceiling lights)
  - Implement shadow mapping for directional light
  - Create toggle for day/night lighting

- [x] **3.8** Implement wall rendering and cutaway
  - Walls render as thin boxes with interior/exterior materials
  - Implement wall height (standard 3m) and thickness
  - Implement wall cutaway: walls nearest to camera become transparent when camera is inside a room
  - Implement wall toggle: show full walls, cutaway walls, walls down

## Phase 4: Sim Entity System

- [x] **4.1** Define Sim component bundle
  - `SimBundle` — aggregates all sim components into a spawnable bundle
  - `SimId` — unique identifier for each sim
  - `SimName` — first name, last name
  - `SimAge` — age in days, life stage (baby, toddler, child, teen, adult, elder)
  - `SimGender` — male/female/custom
  - `SimTraits` — collection of personality traits (max 5)
  - `SimAppearance` — visual properties (skin tone, hair style, clothing)
  - `SimVoice` — pitch and tone parameters for simlish sounds

- [x] **4.2** Implement Needs system
  - Define `Needs` component with 6 core needs:
    - `hunger: f32` (0-100)
    - `energy: f32` (0-100)
    - `social: f32` (0-100)
    - `fun: f32` (0-100)
    - `hygiene: f32` (0-100)
    - `bladder: f32` (0-100)
  - Each need decays over time at configurable rates (per `GameConfig`)
  - Need decay rates modified by traits (e.g., "Active" trait slows energy decay)
  - Need decay pauses during certain interactions (e.g., sleeping pauses all decay)
  - Needs below threshold trigger moodlets and autonomy pushes

- [x] **4.3** Implement Moodlet system
  - Define `Moodlet` struct: name, description, mood impact, duration, source
  - Define `Mood` enum: Happy, Fine, Tense, Sad, Angry, Embarrassed, Energized, Flirty, Focused, Uncomfortable
  - `ActiveMoodlets` component: list of current moodlets on a sim
  - Calculate dominant mood from moodlet totals
  - Mood affects behavior weights (angry sims more likely to fight, sad sims seek comfort)
  - Visual indicator above sim head showing current mood icon

- [x] **4.4** Implement Traits system
  - Define `Trait` enum with personality traits:
    - Active, Lazy, Cheerful, Gloomy, Creative, Genius, Neat, Slob, Outgoing, Introvert
    - Romantic, Unflirty, Ambitious, Good, Evil, Self-Assured, Self-Deprecating
    - Foodie, Glutton, Hot-Headed, Calm, Family-Oriented, Loner, Social Butterfly
  - Each trait modifies need decay rates, autonomy weights, and social interaction outcomes
  - Trait conflicts (e.g., Neat + Slob) are prevented during sim creation
  - Trait descriptions and effects stored in `TraitDatabase` resource

- [x] **4.5** Implement Sim appearance and rendering
  - Create `SimBody` as a combination of scaled primitives (capsule body, sphere head, cylinder limbs)
  - Generate sim skin textures via MCP image gen (different skin tones)
  - Generate clothing textures (tops, bottoms, shoes)
  - Implement `SimAppearance` component that references mesh/texture handles
  - Spawn sim entity with visual representation in 3D world
  - Implement sim height variation by age stage

- [x] **4.6** Implement Sim animation system
  - Create `AnimationState` component: Idle, Walking, Running, Sitting, Sleeping, Talking, Eating, Cooking, Working, Playing, UsingObject, Socializing
  - Create `AnimationTimer` resource for frame timing
  - Implement simple procedural animation: bob walk cycle, idle sway, head look
  - Implement transition between animation states based on sim actions
  - Create animation blending system for smooth transitions

- [x] **4.7** Implement Sim movement and pathfinding
  - Create `MoveTo` component with target position and movement speed
  - Implement `MovementSystem`: lerp sim position toward `MoveTo` target
  - Implement basic A* pathfinding on grid
  - Add obstacle avoidance (other sims, placed objects block path)
  - Implement collision with walls and objects (navmesh-lite or grid-based)
  - Sims walk at configurable speed (affected by energy level)
  - Running when urgency is high (very low need)

## Phase 5: World & Lot System

- [x] **5.1** Define Lot component and structure
  - `Lot` component: position, dimensions (width, depth), name, owner, value
  - `LotBoundary` component: visual outline of lot edges
  - Multiple lots per neighborhood map
  - Lot selection in world view (click to enter lot)

- [x] **5.2** Implement Wall system
  - `Wall` component: start position, end position, height, thickness, material
  - Walls snap to grid (1-unit increments)
  - Walls have two sides (interior, exterior) with different textures
  - Wall rendering with door/window cutout support
  - Wall deletion in build mode

- [x] **5.3** Implement Door and Window system
  - `Door` component: position, rotation, locked state, connected rooms
  - `Window` component: position, rotation, wall segment reference
  - Doors enable pathfinding between rooms
  - Windows let light through (affect lighting)
  - Place door/window in wall segments during build mode

- [x] **5.4** Implement Room/Floor system
  - `Room` component: enclosed space defined by walls, floor material
  - Auto-detect rooms from wall layout (flood fill algorithm)
  - Each room has a floor with selectable material/texture
  - Room properties: name, area, indoor flag
  - Multiple floor levels (ground, second story) — future phase

- [x] **5.5** Implement Furniture/Object catalog
  - Define `CatalogItem` struct: name, category, subcategory, price, description, mesh, dimensions
  - Categories: Comfort, Surfaces, Plumbing, Electronics, Appliances, Lighting, Decorative, Outdoor, Kids, Dining, Bedroom, Bathroom, Kitchen, Office, Fitness, Party
  - Create `CatalogDatabase` resource loaded from RON data file
  - Each catalog item maps to a procedural 3D primitive combination
  - Generate preview textures for catalog items via MCP image gen

- [x] **5.6** Implement placed objects
  - `PlacedObject` component: catalog item reference, position, rotation, condition
  - Objects occupy grid cells based on their size (1x1, 2x1, 2x2, etc.)
  - Objects can be interacted with (define interaction set per object type)
  - Object state machine: clean/dirty, broken/fixed, on/off
  - Objects have a monetary value that depreciates over time

- [x] **5.7** Create initial object definitions
  - **Bed** (single, double) — satisfies energy need
  - **Fridge** — supplies food, satisfies hunger
  - **Stove/Oven** — cook food, satisfies hunger
  - **Toilet** — satisfies bladder need
  - **Shower/Bathtub** — satisfies hygiene need
  - **Sofa/Couch** — satisfies comfort, fun (if TV nearby)
  - **TV** — satisfies fun need
  - **Computer** — satisfies fun, enables work
  - **Bookshelf** — satisfies fun, skill building
  - **Dining Table + Chair** — required for eating meals
  - **Desk + Chair** — required for working from home
  - **Lamp** — provides light
  - **Mirror** — satisfies hygiene, confidence moodlet
  - **Phone** — enables social interactions
  - **Trash Can** — cleaning interaction target
  - **Sink** — hygiene, cleaning dishes

- [x] **5.8** Implement terrain and outdoor
  - Ground texture variations (grass, dirt, concrete, pool tile)
  - Terrain painting tool for build mode (paint ground cells)
  - Trees and bushes as placed outdoor objects
  - Driveway and sidewalk placement
  - Pool (future phase — placeholder in catalog)

- [x] **5.9** Implement neighborhood/world map
  - `Neighborhood` resource: list of lots, roads, community spaces
  - Overhead neighborhood view showing all lots
  - Click lot to enter it (load lot entities)
  - Community lots (park, gym, library, bar) — future phase

## Phase 6: Build/Buy Mode

- [x] **6.1** Implement build mode state machine
  - Transition from `LiveMode` to `BuildMode` on button press or key
  - Freeze sim simulation while in build mode
  - Show grid overlay in build mode
  - Show build mode toolbar UI
  - Transition back to `LiveMode` on exit

- [x] **6.2** Implement wall building tool
  - Click and drag to place wall segments on grid
  - Wall segments snap to grid lines
  - Preview wall placement (ghost/wireframe) before confirming
  - Delete walls by clicking existing wall segments
  - Wall validation: can't place walls that overlap objects

- [x] **6.3** Implement room tool
  - Click-drag rectangle to create a room (auto-generates walls + floor)
  - Room tool auto-places floor material
  - Room validation: minimum size, no overlap
  - Delete room removes walls and floor

- [x] **6.4** Implement buy mode catalog UI
  - Categorized catalog browser (by room type or function)
  - Search/filter catalog items
  - Sort by price, name, need satisfaction
  - Item preview (3D rendered thumbnail or procedural)
  - Show item stats: price, needs satisfied, size

- [x] **6.5** Implement object placement tool
  - Select item from catalog, place on grid
  - Ghost preview at cursor position (green = valid, red = invalid)
  - Rotation with R key (90-degree increments)
  - Snap to grid with optional fine positioning (hold Alt for free placement)
  - Validation: can't overlap walls or other objects
  - Deduct money from household funds on placement

- [x] **6.6** Implement object deletion/selling
  - Click object in buy mode to select for deletion
  - Confirm deletion with click
  - Refund percentage of original price (depreciation)
  - Remove entity from world on deletion

- [x] **6.7** Implement floor/wall material picker
  - Material categories for floors: wood, tile, carpet, stone, concrete
  - Material categories for walls: paint, wallpaper, brick, stone, paneling
  - Click existing floor/wall to repaint with selected material
  - Material cost deducted from household funds
  - Generate material textures via MCP image gen

- [x] **6.8** Implement undo/redo for build mode
  - Maintain undo stack of build/buy actions
  - Ctrl+Z to undo last action (restore walls/objects, refund money)
  - Ctrl+Y to redo undone action
  - Clear undo stack on build mode exit

## Phase 7: AI & Autonomy System

- [x] **7.1** Implement Sim AI decision engine
  - Create `AutonomySystem` that runs each game tick for idle sims
  - Evaluate current needs and find highest-priority unsatisfied need
  - Need priority = (100 - current_value) * weight_from_traits
  - Generate list of possible interactions that satisfy the top need
  - Score each interaction: effectiveness * proximity * trait_modifier
  - Select highest-scoring interaction and push to sim's action queue

- [x] **7.2** Implement interaction queue system
  - `InteractionQueue` component: ordered list of pending interactions
  - Player can queue multiple interactions (click multiple objects/interactions)
  - Autonomy can queue interactions for uncontrolled sims
  - Interactions execute sequentially; sim walks to object, then performs action
  - Cancel queued interactions on new player command or critical need override

- [x] **7.3** Define interaction system
  - `Interaction` struct: name, duration, needs_effects, required_object, animation_state
  - Interactions are defined per object type (bed → "Sleep", "Nap"; fridge → "Get Snack", "Cook Meal")
  - Some interactions require multiple objects (cook meal → fridge + stove + counter)
  - Multi-sim interactions: "Chat", "Hug", "Fight", "Flirt"
  - Interactions can give moodlets on completion

- [x] **7.4** Implement interaction execution
  - `ActiveInteraction` component: currently executing interaction, start time, duration
  - System tracks progress through interaction duration
  - Need effects applied over time (e.g., energy increases during sleep)
  - Fun effects applied (e.g., fun increases while watching TV)
  - Social effects for multi-sim interactions
  - Skill gains for skill-building interactions
  - Interaction completion triggers cleanup and processes next in queue

- [x] **7.5** Implement routing/transition system
  - When sim selects an interaction, create `RouteTo` component pointing to target object
  - Pathfinding system moves sim toward target
  - On arrival, transition from `RouteTo` to `ActiveInteraction`
  - If path is blocked, sim waves hand and cancels interaction (classic Sims behavior)
  - Route cancellation visual: frustrated animation + thought bubble

- [ ] **7.6** Implement need-based autonomy modifiers
  - Desperation behaviors: very low needs override all other actions
  - Energy collapse: sim passes out on the floor
  - Hunger collapse: sim begs for food, eventually faints
  - Bladder failure: sim has an accident (hygiene drops, embarrassment moodlet)
  - Social isolation: sim talks to self, seeks any social interaction
  - Fun deprivation: sim becomes tense, seeks any fun activity

- [ ] **7.7** Implement sim death system
  - If hunger reaches 0, sim dies of starvation (after grace period)
  - If energy reaches 0, sim collapses but doesn't die immediately
  - Death by emotional extremes (e.g., anger heart attack for elders) — future
  - Death creates `SimDeathEvent`, tombstone/urn placed on lot
  - Other sims react with grief moodlet
  - Dead sims are removed from active simulation

- [ ] **7.8** Implement sim schedule/routine AI
  - Sims follow approximate daily routines based on traits and career
  - Employed sims wake up before work, eat breakfast, go to work
  - Sims with Neat trait autonomously clean
  - Sims with Active trait autonomously exercise
  - Schedule system modulates autonomy weights by time of day

## Phase 8: Interaction & Social System

- [ ] **8.1** Implement radial/pie menu system
  - Click on sim or object → show radial menu of available interactions
  - Pie menu segments: 4-8 options around cursor
  - Hover segment to highlight, click to select
  - Categories expand into sub-menus (e.g., "Friendly" → "Chat", "Joke", "Hug")
  - Pie menu styled with The Sims aesthetic (clean, colorful icons)

- [ ] **8.2** Define social interaction catalog
  - **Friendly**: Chat, Joke, Compliment, Hug, Ask About Day, Be Funny, Console
  - **Romantic**: Flirt, Compliment Appearance, Hold Hands, Kiss, Propose, Break Up
  - **Mean**: Insult, Argue, Fight, Slap, Steal, Spread Rumor
  - **Funny**: Tell Joke, Funny Story, Prank, Silly Face
  - **Special**: Teach, Advise, Mentor, Ask for Loan, Propose Activity

- [ ] **8.3** Implement relationship tracker
  - `Relationships` component: HashMap of (target_sim_id → RelationshipData)
  - `RelationshipData` struct: friendship_score (0-100), romance_score (0-100), known_traits, sentiment
  - Relationships are directional (A→B and B→A tracked independently)
  - Relationship levels: Stranger, Acquaintance, Friend, Good Friend, Best Friend, Romantic Interest, Partner, Spouse, Enemy, Nemesis
  - Relationship milestones unlock new interactions (e.g., "Propose" only at high romance)

- [ ] **8.4** Implement conversation system
  - Two sims in proximity can initiate a conversation
  - Conversations have a context (friendly, romantic, tense, etc.)
  - Each interaction within conversation modifies relationship scores
  - Conversation quality affected by compatibility (trait matching)
  - Conversation can turn from friendly to romantic or tense based on interactions
  - Visual: speech bubbles with icons, thought bubbles with mood indicators

- [ ] **8.5** Implement moodlet-based social effects
  - Happy sims have more successful social interactions
  - Angry sims may start arguments autonomously
  - Sad sims receive comfort interactions
  - Flirty sims initiate romantic interactions
  - Embarrassed sims avoid social contact
  - Mood affects conversation outcome multipliers

- [ ] **8.6** Implement sentiment system
  - Sentiments are long-term relationship modifiers from significant events
  - Positive sentiments: "Grateful" (sim A helped sim B), "Close" (spent quality time)
  - Negative sentiments: "Betrayed" (caught cheating), "Furious" (had a fight)
  - Sentiments decay over time but affect behavior while active
  - Sentiments are tracked per-relationship (not global)

- [ ] **8.7** Implement group social dynamics
  - Multiple sims can be in a conversation simultaneously
  - Group conversations: one sim speaks, others react
  - Exclusion mechanic: sims can be left out of group activities
  - Group activities: "Dance Together", "Tell Group Story", "Play Game"
  - Party/social event system — future phase

## Phase 9: Career & Economy

- [ ] **9.1** Implement household money system
  - `HouseholdFunds` resource: current money amount
  - Money earned from careers (hourly salary)
  - Money spent on buying objects, bills, food
  - Bills arrive periodically (based on lot value and consumption)
  - Money display in UI with K/M formatting for large amounts
  - Bankruptcy: if money goes negative, repo man takes objects

- [ ] **9.2** Define career track system
  - Each career has levels (1-10) with title, salary, hours, and requirements
  - Career tracks:
    - **Tech**: QA Tester → Code Reviewer → Developer → Senior Dev → CTO
    - **Culinary**: Dishwasher → Prep Cook → Chef → Sous Chef → Executive Chef
    - **Entertainment**: Street Performer → Actor → Celebrity → Superstar
    - **Business**: Intern → Analyst → Manager → Director → CEO
    - **Athletic**: Water Person → Personal Trainer → Coach → Champion
    - **Creative**: Freelancer → Designer → Art Director → Master Artist
    - **Medical**: Intern → Nurse → Doctor → Surgeon → Chief of Medicine
    - **Criminal**: Pickpocket → Thief → Con Artist → Mastermind
  - Career data loaded from RON config file

- [ ] **9.3** Implement job performance system
  - `JobPerformance` component: daily performance score (0-100)
  - Performance affected by: mood at work, skills, relationships with coworkers
  - High performance → promotion; low performance → demotion
  - Performance displayed in career panel UI
  - Performance decays each day if sim misses work

- [ ] **9.4** Implement work schedule system
  - Sims leave for work at scheduled time (teleport off-lot)
  - Work hours vary by career level
  - Sim returns home after shift
  - Overtime option: work extra hours for bonus pay but energy/hunger drain
  - Days off: weekends or career-specific off days
  - Vacation days: accumulated PTO

- [ ] **9.5** Implement skills system
  - Skills: Cooking, Handiness, Charisma, Fitness, Logic, Creativity, Gardening, Fishing, Programming
  - `Skills` component: HashMap<SkillType, SkillLevel> where level is 0-10
  - Skill gains from interactions: cooking → Cooking skill, programming → Logic skill
  - Skills unlock career promotions
  - Skills improve interaction effectiveness (better meals, faster repairs)
  - Visual skill bar in sim info panel

- [ ] **9.6** Implement bills and expenses
  - Weekly bills calculated from: lot value, electricity usage, water usage
  - Bills delivered as notification
  - Pay bills through mailbox or phone interaction
  - Unpaid bills → repossession of items after deadline
  - Optional: online shopping for groceries (auto-delivery)

- [ ] **9.7** Implement freelance/odd jobs
  - Sims can pick up gig work from phone/computer
  - Gig types: programming, painting, writing, repair, delivery
  - Gigs have a deadline and pay amount
  - Completing gigs gives money and skill experience
  - Some gigs are recurring (daily/weekly)

## Phase 10: UI System

- [ ] **10.1** Implement main menu
  - Title screen with "Just Life" logo (generate logo via MCP image gen)
  - Buttons: New Game, Load Game, Options, Quit
  - Background: slow-pan 3D scene or animated neighborhood
  - Options menu: resolution, volume, controls, language

- [ ] **10.2** Implement HUD overlay
  - Bottom panel: needs bars (6 horizontal bars for current needs)
  - Bottom-left: sim portrait with mood indicator
  - Bottom-center: interaction queue display (upcoming actions)
  - Top-right: time display (day, hour, minute), speed controls (pause, 1x, 2x, 4x)
  - Top-left: household funds display
  - Mini-map in corner showing lot layout

- [ ] **10.3** Implement needs bar UI
  - 6 colored bars matching need type:
    - Hunger (green), Energy (yellow), Social (purple), Fun (pink), Hygiene (teal), Bladder (blue)
  - Bar fills/shrinks with smooth animation
  - Critical need (below 25) bar flashes red
  - Hovering over a bar shows exact number and what affects it
  - Clicking a need bar highlights all objects that satisfy that need

- [ ] **10.4** Implement sim info panel
  - Open sim panel by clicking sim portrait or double-clicking sim
  - Shows: name, age, gender, traits, career, aspiration
  - Shows: all 6 needs with exact values
  - Shows: all skills with level bars
  - Shows: relationships summary
  - Shows: moodlets list
  - Tab interface: Needs, Skills, Relationships, Career, Inventory

- [ ] **10.5** Implement pie menu interaction UI
  - Radial menu appears on right-click or tap on sim/object
  - Center shows the object/sim name
  - Segments show available interactions with icons
  - Hover segment shows description
  - Multi-level menus (category → specific action)
  - Menu closes on outside click or Escape
  - Disabled interactions grayed out with tooltip explaining why

- [ ] **10.6** Implement build mode UI toolbar
  - Left sidebar: tool categories (Wall, Floor, Door, Window, Staircase)
  - Bottom panel: selected tool options (wall style, floor material)
  - Right sidebar: catalog browser when in buy mode
  - Top bar: current mode indicator, household funds, undo/redo buttons
  - Confirmation dialogs for expensive purchases

- [ ] **10.7** Implement notifications/toast system
  - Toast notifications appear top-right and auto-dismiss after 5 seconds
  - Notification types: info (blue), success (green), warning (yellow), error (red)
  - Notifications for: bills due, promotion, sim mood event, relationship milestone
  - Notification history accessible from icon
  - Sound effect on notification

- [ ] **10.8** Implement Create-A-Sim UI
  - CAS screen: full-body view of sim in 3D
  - Name input fields
  - Gender selector
  - Age stage selector (young adult default)
  - Appearance customization: skin tone, hair style, hair color, clothing
  - Trait selection: pick 3 traits from trait list (conflicts disabled)
  - Aspiration selection: life goal that gives bonus moodlets
  - Voice pitch slider
  - Randomize button for all fields
  - "Done" creates sim and places on lot

- [ ] **10.9** Implement time control UI
  - Speed buttons: pause, play (1x), fast (2x), ultra (4x)
  - Keyboard shortcuts: 1/2/3 for speed, 0 for pause, Space for toggle
  - Visual indicator of current speed
  - Pause dims the screen slightly
  - Ultra speed auto-engages during sleep (skip to morning)

- [ ] **10.10** Implement tooltip system
  - Hovering over any UI element shows a tooltip after 500ms
  - Tooltips explain what the element does
  - Tooltips for objects show: name, needs satisfied, price, current state
  - Tooltips for sims show: name, mood, current action

## Phase 11: Audio & Polish

- [ ] **11.1** Implement audio system
  - Load audio files via Bevy asset system
  - Background music: main menu theme, build mode music, live mode ambient music
  - Generate ambient music tracks or use royalty-free
  - Volume control in options menu
  - Fade music between game states

- [ ] **11.2** Implement sound effects
  - UI sounds: click, hover, notification, error
  - Sim sounds: footsteps, door open/close, object interactions
  - Build mode sounds: wall place, object place, delete, error
  - Ambient sounds: birds, traffic, rain, clock ticking
  - Simlish-style vocalizations for sim speech (generate or use placeholder beeps)

- [ ] **11.3** Implement visual feedback and particles
  - Thought bubbles above sims (show current want/need as icon)
  - Speech bubbles during conversation (show interaction icon)
  - Need failure visual effects (puddle for bladder, zzz for energy, etc.)
  - Sparkle/glow effect for positive moodlets
  - Red tint/particles for negative moodlets
  - Money +/- floating text when money changes

- [ ] **11.4** Implement save/load system
  - Serialize game state to RON (Rusty Object Notation) format
  - Save: all sim states, world state, relationships, inventory, career, time
  - Save file stored locally (browser: localStorage; native: filesystem)
  - Load: deserialize and reconstruct all entities and resources
  - Auto-save every 10 in-game minutes
  - Multiple save slots (3 minimum)
  - Save slot display: neighborhood name, sim names, play time, screenshot

- [ ] **11.5** Implement game settings
  - Graphics: resolution, fullscreen/windowed, quality presets (low/medium/high)
  - Audio: master volume, music volume, SFX volume, ambient volume
  - Gameplay: autonomy level (full/high/low/off), sim aging speed, needs decay rate
  - Controls: key bindings display and remapping
  - Camera: invert Y, rotation speed, zoom speed
  - Settings persisted to config file

- [ ] **11.6** Implement localization framework
  - All UI strings loaded from locale files (English default)
  - RON or JSON locale files in `assets/locales/`
  - Locale key system: `ui.needs.hunger`, `interactions.bed.sleep`, etc.
  - Language selector in options
  - Framework ready for community translations

- [ ] **11.7** Performance optimization
  - Implement spatial partitioning for interaction range checks (grid-based)
  - LOD system for distant objects (simplify mesh, reduce draw calls)
  - Batch render similar objects (instanced rendering)
  - Limit active sim AI evaluations per frame (spread across frames)
  - Profile WASM build size and optimize with wasm-opt
  - Reduce texture sizes for WASM build (compressed textures)
  - Target 60 FPS on mid-range hardware, 30 FPS minimum on WASM

## Phase 12: WASM Export & Browser Deployment

- [ ] **12.1** Finalize WASM build pipeline
  - Ensure `Cargo.toml` has proper WASM release profile
  - Configure `wasm-bindgen` to generate JS glue code
  - Create `build-wasm.sh` that: builds for wasm32-unknown-unknown, runs wasm-bindgen, runs wasm-opt
  - Minimize WASM binary size (strip debug info, optimize with wasm-opt -Oz)
  - Create `just-life.js` and `just-life.wasm` output

- [ ] **12.2** Create browser shell
  - Create `web/index.html` with full-screen canvas
  - Create `web/index.js` with WASM loader and resize handler
  - Create `web/styles.css` with body margin removal and canvas styling
  - Handle browser tab focus/blur for pause/resume
  - Handle window resize events
  - Test on Chrome, Firefox, Safari

- [ ] **12.3** Implement browser-specific adaptations
  - Asset loading: all assets bundled or fetched from server
  - Input: map mouse/touch events to Bevy input system
  - Right-click handling for pie menu (prevent context menu)
  - Touch: long press for pie menu, pinch to zoom, two-finger pan
  - Keyboard: handle browser key events without conflicts
  - Sound: require user interaction to start audio (browser autoplay policy)

- [ ] **12.4** Set up deployment
  - Create GitHub Actions workflow for automated WASM builds on push
  - Deploy WASM build to GitHub Pages or itch.io
  - Configure proper MIME types for .wasm files
  - Add service worker for offline caching of assets
  - Test deployed build in browser

- [ ] **12.5** Browser testing and screenshots
  - Load WASM build in browser
  - Take screenshot of: main menu, Create-A-Sim, live mode, build mode, buy mode
  - Test all interactive features in browser
  - Verify performance metrics in browser (FPS, memory)
  - Fix any browser-specific rendering bugs
  - Document known browser limitations

- [ ] **12.6** Create demo/prototype content
  - Pre-built starter house with basic furniture
  - Pre-made sim household (2-3 sims with varied traits)
  - Tutorial hints for first-time players
  - Seed the neighborhood with 1 community lot
  - Ensure all core gameplay loops work in 15-minute play session

## Phase 13: Cooking & Food System

- [ ] **13.1** Define food and recipe data model
  - `Recipe` struct: name, required_ingredients, required_appliances, cooking_skill_required, cooking_time, hunger_satisfaction, quality_levels
  - `FoodItem` struct: name, spoil_timer, hunger_satisfaction, quality, price
  - `Ingredient` enum: RawVegetable, RawMeat, RawFish, Egg, Flour, Sugar, Spice, Dairy
  - Recipe data stored in RON config file (`assets/data/recipes.ron`)
  - Recipes range from simple (cereal, salad) to complex (gourmet lobster)

- [ ] **13.2** Implement fridge and food storage
  - Fridge stores up to N food items (inventory slots)
  - Fridge has a spoilage timer for perishable items
  - Sims can "Get Snack" from fridge (quick, low hunger satisfaction)
  - Sims can "Get Ingredient" to start cooking a recipe
  - Auto-restock option: fridge replenishes basic ingredients for a cost

- [ ] **13.3** Implement cooking interaction chain
  - Cooking a meal is a multi-step interaction chain:
    1. Sim selects recipe from fridge/stove menu
    2. Sim gets ingredients from fridge (walk to fridge)
    3. Sim prepares food at counter (prep step)
    4. Sim cooks food at stove/oven (cook step)
    5. Sim serves food (places on table/counter)
  - Each step requires the correct appliance nearby
  - Cooking skill affects meal quality and time
  - Fire risk if sim has low cooking skill and leaves stove unattended

- [ ] **13.4** Implement meal quality system
  - Meal quality levels: Poor, Normal, Good, Excellent, Perfect
  - Quality determined by: cooking skill, ingredients, sim mood, appliance quality
  - Higher quality meals satisfy more hunger and give moodlets
  - Poor quality meals can give negative moodlets ("Terrible Meal")
  - Burnt food if sim is interrupted during cooking step

- [ ] **13.5** Implement eating and dining
  - Sims eat at a table if one is available (otherwise standing)
  - Eating duration: 15-30 in-game minutes depending on meal
  - Social eating: sims at the same table get a "Meal Together" moodlet
  - Eating satisfies hunger need over the duration
  - Cooking skill improves faster when cooking at home vs getting snacks

- [ ] **13.6** Implement hunger decay and starvation
  - Hunger decays at base rate modified by traits (Glutton decays faster)
  - Hunger decay slows during sleep
  - Very low hunger: "Ravenous" moodlet, sim autonomously seeks food
  - Zero hunger: sim collapses, death after extended period
  - Quick meals available from fridge (no cooking required, low satisfaction)

- [ ] **13.7** Implement grocery shopping
  - Order groceries via phone or computer
  - Grocery delivery: items appear in fridge after delay
  - Grocery cost deducted from household funds
  - Ingredient quality affects meal quality
  - Community garden: grow own ingredients (future phase)

## Phase 14: Aging & Life Stages

- [ ] **14.1** Implement life stage system
  - `LifeStage` enum: Baby, Toddler, Child, Teen, YoungAdult, Adult, Elder
  - Each stage has different: walk speed, need decay rates, available interactions, height, appearance
  - Life stage transitions triggered by age timers (configurable in GameConfig)
  - Age bar displayed in sim info panel
  - Aging can be paused in settings

- [ ] **14.2** Implement baby stage
  - Babies are immobile objects that other sims must care for
  - Baby interactions: Feed, Change Diaper, Cuddle, Talk To, Put To Sleep
  - Babies have 3 needs: Hunger, Energy, Social
  - Neglected babies cry (noise that wakes nearby sims)
  - Babies auto-transition to Toddler after configurable time

- [ ] **14.3** Implement toddler stage
  - Toddlers can walk slowly, play with toys, talk (limited interactions)
  - Toddler interactions: Play, Teach to Talk, Teach to Walk, Potty Train, Feed
  - Toddlers have 5 needs: Hunger, Energy, Social, Fun, Hygiene
  - Toddler skill gains: Movement, Communication, Imagination, Thinking
  - Toddlers auto-transition to Child after configurable time

- [ ] **14.4** Implement child and teen stages
  - Children can: attend school (off-lot), do homework, play with toys, make friends
  - Children cannot: cook, use certain objects, have romantic interactions
  - Teens can: have romantic relationships (teen-only), get part-time jobs, attend high school
  - Teens cannot: have adult careers, drink, live alone
  - School performance tracked similar to job performance

- [ ] **14.5** Implement elder stage
  - Elders have slower walk speed and faster energy decay
  - Elders can retire from career (receive pension)
  - Higher death chance from extreme emotions or very low needs
  - Elders gain bonus moodlets from family interactions ("Proud Grandparent")
  - Elders can mentor younger sims in skills

- [ ] **14.6** Implement aging UI
  - Age progress bar in sim info panel
  - Birthday notification when sim ages up
  - Birthday celebration event (optional party)
  - Age transition visual: sim appearance changes height/face
  - "Age Up" button in CAS for quick testing

- [ ] **14.7** Implement genetics and family trees
  - `FamilyTree` resource: tracks parent-child and sibling relationships
  - Children inherit traits from parents (weighted random selection)
  - Children inherit appearance features (skin tone blend, hair color from parents)
  - Family members get special moodlets ("Family Visit", "Family Meal")
  - Sibling interactions: "Tease", "Teach", "Play With"

## Phase 15: Aspirations & Whims System

- [ ] **15.1** Define aspiration data model
  - `Aspiration` struct: name, description, category, milestone_list
  - `AspirationCategory` enum: Knowledge, Family, Creativity, Romance, Fortune, Popularity, Nature, Food
  - Each aspiration has 4 milestones (like Sims 2)
  - Milestones are specific goals: "Reach Cooking Skill Level 5", "Marry a Sim", "Earn §50,000"
  - Aspiration data stored in RON config file

- [ ] **15.2** Implement aspiration tracking
  - `ActiveAspiration` component: selected aspiration, current milestone index, progress
  - Progress tracked automatically based on game events (skill gains, money earned, etc.)
  - Milestone completion gives aspiration points and a moodlet
  - Completing all milestones completes the aspiration (big reward moodlet)
  - Aspiration can be changed mid-game (with penalty to progress)

- [ ] **15.3** Implement whims system
  - `Whim` struct: description, condition, reward_points, timeout
  - Whims are short-term goals inspired by current mood and situation
  - Examples: "Talk to someone" (social need high), "Cook a meal" (creative mood), "Flirt with sim" (flirty mood)
  - 3 active whims at a time, displayed in sim panel
  - Whims time out after in-game hours, replaced by new ones
  - Completing a whim gives aspiration points

- [ ] **15.4** Implement aspiration point rewards
  - Aspiration points earned from whims and milestones
  - Reward store: spend points on permanent benefits
  - Rewards: "Never Weary" (energy decays slower), "Steel Bladder" (bladder decays slower), "Connections" (career boost)
  - Rewards are per-sim, not per-household
  - Reward data stored in RON config file

- [ ] **15.5** Implement lifetime happiness tracker
  - Lifetime happiness score: total aspiration points earned over sim's lifetime
  - Displayed on sim info panel as a bar
  - Higher lifetime happiness unlocks exclusive reward store items
  - Lifetime happiness persists through age transitions

## Phase 16: Environment & Weather

- [ ] **16.1** Implement time-of-day cycle
  - `TimeOfDay` system: cycle through dawn, morning, afternoon, evening, dusk, night
  - Lighting color changes per time-of-day (warm morning, blue night)
  - Sun direction rotates through the day
  - Sky color transitions smoothly between phases
  - In-game time scale: configurable (default: 1 real second = 1 in-game minute)

- [ ] **16.2** Implement weather system
  - `Weather` enum: Clear, Cloudy, Rain, Storm, Snow, HeatWave, Fog
  - Weather changes based on random + seasonal patterns
  - Visual effects: rain particles, snow particles, fog overlay, lightning flash
  - Rain: puddle particles on ground, sims run indoors (autonomous)
  - Snow: ground turns white, sims get "Cold" moodlet without warm clothing
  - Heat wave: sims get "Overheated" moodlet, energy decays faster
  - Storm: lightning visual, power outage chance, "Scared" moodlet for some traits

- [ ] **16.3** Implement season system
  - `Season` enum: Spring, Summer, Fall, Winter
  - Seasons cycle on a configurable timer
  - Each season has different: weather probabilities, daylight hours, tree colors
  - Spring: flowers bloom, rain frequent
  - Summer: hot weather, long days, pool season
  - Fall: leaves change color, harvest time
  - Winter: snow, short days, holiday events

- [ ] **16.4** Implement environmental moodlets
  - "Nicely Decorated" moodlet from high-value furnishings in the room
  - "Dirty Environment" moodlet from trash, dirty dishes, unwashed sims
  - "Beautiful Lot" moodlet from outdoor decorations and landscaping
  - "Spooky" moodlet from dark rooms at night
  - "Cozy" moodlet from fireplace + comfortable seating
  - Room score calculated from: value of objects, cleanliness, lighting, decoration

- [ ] **16.5** Implement temperature and comfort
  - `Temperature` component: indoor vs outdoor, affected by season and weather
  - Sims get "Too Hot" or "Too Cold" moodlets based on temperature
  - HVAC objects (thermostat, fireplace) adjust indoor temperature
  - Sims autonomously change into weather-appropriate outfits
  - Seasonal clothing: winter coat, summer shorts, raincoat

- [ ] **16.6** Implement day/night visual effects
  - Night: ambient light reduces, indoor lights become prominent
  - Street lights turn on at dusk, off at dawn
  - Windows glow at night (interior light visible from outside)
  - Stars in sky at night
  - Moon phase system (purely visual, cosmetic)

## Phase 17: Multi-Sim Household Management

- [ ] **17.1** Implement household system
  - `Household` resource: list of sim IDs, shared funds, lot ownership
  - Household panel: switch between household members
  - Max household size: 8 sims (configurable)
  - Add/remove sims from household via move-in/move-out interactions
  - Merge households when sims marry or move in together

- [ ] **17.2** Implement household funds sharing
  - All sims in household share money pool
  - Any sim can spend from household funds
  - Career income adds to household funds
  - Bills are per-household, not per-sim
  - "Transfer Funds" interaction for giving money to other households

- [ ] **17.3** Implement sim switching
  - Click on any household sim to select and control them
  - Unselected sims continue autonomously (free will)
  - Autonomy level configurable: Full, High, Low, Off
  - "Focus" mode: camera follows selected sim
  - "Overview" mode: see all household sim portraits with status

- [ ] **17.4** Implement household management UI
  - Household portrait panel showing all members
  - Click portrait to select sim
  - Sim status indicators on portraits (needs bar summary, mood icon)
  - Right-click portrait for quick actions: "Go Here", "Call", "Check Needs"
  - "Household Finances" sub-panel showing income/expenses

- [ ] **17.5** Implement moving and lot transfer
  - "Move Out" interaction: sim leaves household to create new one
  - "Move In" interaction: sim joins another household
  - "Evict" interaction: kick sim out of household (they become homeless/NPC)
  - Moving sim takes a portion of household funds
  - Moved sims retain their relationships, skills, career

- [ ] **17.6** Implement NPC sims
  - NPC (non-player character) sims that live in the neighborhood
  - NPCs have homes, careers, and full need simulation
  - NPCs visit the player's lot autonomously or when invited
  - NPC story progression: they can marry, have children, get promoted
  - NPC generation: new sims created when needed to fill careers and roles
  - Townie pool: sims without homes that wander community lots

## Phase 18: Events & Situations

- [ ] **18.1** Implement social events system
  - `SocialEvent` struct: type, host, guests, start_time, duration, location
  - Event types: House Party, Birthday, Wedding, Funeral, Dinner Party, Dance Party
  - Sims can invite guests via phone
  - Event goals: "Have 5 guests arrive", "Serve food", "Dance for 2 hours"
  - Event score: bronze, silver, gold based on goals completed
  - Event rewards: moodlets, aspiration points, items

- [ ] **18.2** Implement party mechanics
  - Party starts when scheduled time arrives
  - Guests arrive autonomously (or not, based on relationship)
  - Party activities: "Dance", "Toast", "Blow Out Candles", "Make Toast"
  - Party moodlet: "Having a Party" for host and guests
  - Party can be crashed by sims with mean traits
  - Party ends after duration, host gets results screen

- [ ] **18.3** Implement holiday system
  - `Holiday` struct: name, date, traditions, moodlet
  - Example holidays: New Year (midnight toast), Love Day (romantic moodlet), Harvestfest (cooking moodlet)
  - Holidays can be created/customized by player
  - Holiday traditions: specific interactions that give bonus moodlets
  - Decorations for holidays (auto-place or manual)
  - Holidays appear as notifications on the day

- [ ] **18.4** Implement fire and emergency system
  - Fire can start from: cooking accidents (low skill), faulty electronics, lightning
  - Fire spreads to adjacent objects over time
  - Sims react to fire: panic, run away, or try to extinguish
  - "Call Fire Department" interaction on phone
  - Firefighter NPC arrives and extinguishes fire
  - Burned objects are destroyed and must be replaced
  - Burglary event: rare nighttime break-in, sim can call police

- [ ] **18.5** Implement chance cards and random events
  - Random popup events during career, school, or daily life
  - Chance card format: situation description + 2-3 choices
  - Choices have weighted outcomes (good result, bad result, neutral)
  - Example: "A coworker is taking credit for your work. Do you: Confront them? Report to boss? Let it go?"
  - Career-specific chance cards during work hours
  - Random life events: "Found §50 on the ground", "Power outage", "Celebrity sighting"

- [ ] **18.6** Implement goal and achievement system
  - `Achievement` struct: name, description, condition, icon, reward
  - In-game achievements: "First Kiss", "Max Out a Skill", "Earn §100,000", "Throw a Gold Party"
  - Achievements tracked globally across all save files
  - Achievement popup notification with sound effect
  - Achievement progress displayed in achievement panel
  - Hidden achievements: conditions not shown until completed

## Phase 19: Modding & Data-Driven Config

- [ ] **19.1** Create RON data file for careers
  - `assets/data/careers.ron`: all career tracks, levels, salaries, hours, requirements
  - Each level has: title, salary, work_days, work_hours, performance_requirements
  - Promotion requirements: skill levels, friend count, performance threshold
  - RON format supports easy editing by modders

- [ ] **19.2** Create RON data file for objects/catalog
  - `assets/data/catalog.ron`: all furniture/object definitions
  - Each item has: name, category, price, description, dimensions, needs_satisfied, interactions
  - Objects reference procedural mesh combinations (no external 3D model dependency)
  - Catalog organized by room type and function

- [ ] **19.3** Create RON data file for interactions
  - `assets/data/interactions.ron`: all interaction definitions
  - Each interaction has: name, duration, needs_effects, required_object, required_skill, mood_effects
  - Multi-step interactions (cooking chain) defined as interaction sequences
  - Social interactions include relationship requirements and effects

- [ ] **19.4** Create RON data file for traits and aspirations
  - `assets/data/traits.ron`: all trait definitions, conflicts, effects
  - `assets/data/aspirations.ron`: all aspirations, milestones, rewards
  - Trait effects defined as modifiers: need_decay_multiplier, autonomy_weight_override, social_outcome_modifier
  - Aspiration milestones reference game events by ID

- [ ] **19.5** Create RON data file for locale/strings
  - `assets/locales/en.ron`: English string database
  - All UI text, interaction names, object names, trait descriptions stored as locale keys
  - Nested structure: `ui.panel.needs.hunger`, `objects.bed.name`, `traits.active.description`
  - Locale keys referenced by code, resolved at runtime

- [ ] **19.6** Implement hot-reload for data files
  - Watch `assets/data/` directory for changes during development
  - On file change, reload the corresponding data without restart
  - Validate RON files on load (schema checking)
  - Log warnings for invalid data entries
  - Fallback to default values if data file is missing

- [ ] **19.7** Implement mod loading system
  - Define mod folder structure: `mods/<mod_name>/data/`, `mods/<mod_name>/textures/`, `mods/<mod_name>/locales/`
  - Mod data files override base game data by key
  - Mod textures override base game textures by filename
  - Mod discovery: scan `mods/` folder on startup
  - Mod enable/disable toggle in options menu
  - Mod load order for conflict resolution

- [ ] **19.8** Create configuration system
  - `GameConfig` resource loaded from `assets/data/config.ron`
  - Configurable values: need decay rates, salary multipliers, aging speed, autonomy level defaults
  - Difficulty presets: Easy, Normal, Hard (modify config values)
  - Custom difficulty: player can tweak individual settings
  - Config changes apply immediately (hot-reload in dev mode)

- [ ] **19.9** Implement debug/cheat console
  - Toggle console with backtick/tilde key
  - Commands: `money <amount>`, `needs.max`, `needs.min`, `skill.<name> <level>`, `career.promote`, `time.set <hour>`
  - Commands for testing: `spawn.sim`, `spawn.object <name>`, `teleport`, `debug.ai <on/off>`
  - Console only available in dev mode (not in release builds)
  - Console history and auto-complete

## Phase 20: Testing, Balance & Polish

- [ ] **20.1** Write unit tests for core systems
  - Test Needs system: decay rates, trait modifiers, threshold triggers
  - Test Moodlet system: mood calculation, moodlet stacking, timeout
  - Test Trait system: conflict detection, effect application
  - Test Relationship system: score changes, level transitions, sentiment application
  - Test Career system: promotion/demotion logic, salary calculation
  - Test Skill system: skill gains, level caps, trait modifiers

- [ ] **20.2** Write integration tests for gameplay loops
  - Test: sim wakes up → eats → goes to work → returns → socializes → sleeps (full day cycle)
  - Test: build mode → place walls, doors, furniture → switch to live mode → sim navigates
  - Test: create sim in CAS → place on lot → needs decay → autonomy satisfies needs
  - Test: two sims meet → social interactions → relationship develops → romantic interactions
  - Test: buy lot → build house → furnish → sim lives autonomously for 3 in-game days

- [ ] **20.3** Balance need decay rates
  - Tune decay rates so sims need to eat 2-3 times per in-game day
  - Energy should last ~16 hours awake before sim needs sleep
  - Social should decay slowly unless sim is an extrovert trait
  - Fun should require active engagement (not just standing around)
  - Hygiene should decay from exercise and work interactions
  - Bladder should fill up ~3 times per day
  - All rates configurable in `config.ron`

- [ ] **20.4** Balance economy and pricing
  - Starting funds: §20,000 (enough for small house + basic furniture)
  - Entry-level salary: §250/day (enough to cover bills + food)
  - Bills should be ~10-15% of household value per week
  - Object prices: bed §300-§3000, fridge §500-§5000, TV §400-§4000
  - Food cost: snack §5, home-cooked meal §15, gourmet §50
  - Career promotions should feel rewarding (2x salary jump per level)

- [ ] **20.5** Balance relationship and social systems
  - Friendship gains: ~2 points per positive interaction
  - Friendship losses: ~5 points per negative interaction (asymmetry like real life)
  - Romance gains: ~3 points per romantic interaction (requires existing friendship)
  - Relationship decay: -1 point per day of no contact (slower for close relationships)
  - Milestone thresholds: Acquaintance (20), Friend (40), Good Friend (60), Best Friend (80)

- [ ] **20.6** Implement tutorial/onboarding
  - First-time player tutorial: guided through basic controls
  - Tutorial steps: move camera, select sim, queue interaction, open needs panel, build mode basics
  - Tutorial hints appear contextually (first time entering build mode, first time a need is low)
  - Tutorial can be skipped or replayed from settings
  - Tooltip system explains new features as they unlock

- [ ] **20.7** Optimize for WASM performance
  - Profile WASM build: identify top CPU consumers
  - Optimize pathfinding: limit search radius, cache paths
  - Optimize AI: spread autonomy evaluations across multiple frames
  - Optimize rendering: frustum culling, LOD, instanced rendering for repeated objects
  - Reduce WASM binary size: strip debug info, wasm-opt -Oz, tree-shake unused features
  - Target: 30+ FPS on mid-range laptop in Chrome
  - Memory: target <500MB RAM in browser

- [ ] **20.8** Final content and polish
  - Create 3 pre-built starter houses (small, medium, large)
  - Create 5 pre-made sim households with diverse traits and relationships
  - Add 10+ community lot templates (park, gym, library, bar, cafe)
  - Ensure all UI elements have hover states, click feedback, and tooltips
  - Add loading screen with progress bar and "Just Life" branding
  - Add credits screen
  - Final WASM build and browser deployment test

## Phase 21: Inventory & Object Interaction Details

- [ ] **21.1** Implement sim personal inventory
  - `Inventory` component on each sim: list of `InventorySlot` items
  - `InventorySlot` struct: item_id, quantity, condition
  - Inventory capacity limit (configurable, default: 20 slots)
  - Items: phone, keys, wallet, books, tools, food servings, collectibles
  - Drag-and-drop UI for inventory management
  - Stack identical items in one slot (quantity tracking)

- [ ] **21.2** Implement household shared storage
  - Household storage chests/boxes placed as furniture objects
  - Shared storage accessible by all household members
  - Storage capacity based on furniture type (small chest: 10, large wardrobe: 40)
  - Transfer items between personal inventory and shared storage
  - Auto-sort button for organizing storage

- [ ] **21.3** Implement object condition and repair system
  - `Condition` component on placed objects: 0-100 durability
  - Objects degrade over time with use (faster with low-quality objects)
  - Breaking point: object stops functioning, shows broken visual (sparks, cracks)
  - "Repair" interaction: requires Handiness skill, takes time based on skill level
  - Low Handiness skill can fail repair, making object worse
  - High Handiness skill can upgrade objects (improve durability, add features)

- [ ] **21.4** Implement object upgrade system
  - `Upgrades` component on objects: list of applied upgrades
  - Upgrade examples: "Self-Cleaning" (toilet), "Instant" (stove), "Unbreakable" (electronics)
  - Upgrades require Handiness skill level + specific parts
  - Parts acquired from "Salvage" interaction on broken objects or purchased
  - Upgraded objects have visual indicator (sparkle)
  - Upgrades stored in object's component, persist through save/load

- [ ] **21.5** Implement food and drink interaction chains
  - Fridge: "Get Snack", "Get Drink", "Get Ingredient", "Get Leftovers"
  - Stove: "Cook Meal" (opens recipe menu), "Cook Breakfast", "Cook Dinner"
  - Microwave: "Heat Leftovers", "Make Microwave Meal"
  - Coffee Maker: "Make Coffee" (energy boost), "Make Espresso"
  - Bar: "Make Drink" (fun boost), "Make Fancy Cocktail" (requires Mixology skill)
  - Grill: "Grill Meat", "Grill Veggie Burger", "Grill Hot Dog"

- [ ] **21.6** Implement hygiene and bathroom interactions
  - Toilet: "Use Toilet" (bladder), "Potty Train" (for toddlers)
  - Shower: "Take Shower" (hygiene), "Take Bath" (hygiene + comfort), "Sing in Shower" (fun)
  - Sink: "Wash Hands" (hygiene small), "Brush Teeth" (hygiene + confidence moodlet)
  - Mirror: "Admire Self" (confidence moodlet), "Practice Speech" (charisma skill)
  - Dirty objects: "Clean" interaction on dirty dishes, dirty counters, grimy tub

- [ ] **21.7** Implement sleep and energy interactions
  - Bed: "Sleep" (full energy recovery, 6-8 hours), "Nap" (partial, 1-2 hours), "Relax" (comfort, fun)
  - Couch: "Nap" (partial energy, less comfortable), "Watch TV" (fun), "Sit" (comfort)
  - Coffee: "Drink Coffee" (temporary energy boost, "Buzzed" moodlet, crash later)
  - Energy drink: "Drink Energy Juice" (bigger boost, bigger crash)
  - Alarm clock: "Set Alarm" → sim wakes up at set time automatically

- [ ] **21.8** Implement skill-building object interactions
  - Bookshelf: "Read Skill Book" (gain skill XP for specific skill), "Read for Fun" (fun)
  - Easel: "Paint" (creativity skill), "Paint from Reference" (higher quality with skill)
  - Guitar/Piano: "Practice" (creativity skill), "Play Song" (fun for listeners)
  - Treadmill/Weights: "Work Out" (fitness skill), "Jog" (fitness + energy drain)
  - Chess Table: "Play Chess" (logic skill), "Practice Alone" (logic, less fun)
  - Computer: "Program" (logic/programming skill), "Write" (creativity skill)
  - Stove: "Cook" (cooking skill), "Experiment" (cooking skill, risk of fire at low level)

- [ ] **21.9** Implement collectibles system
  - Collectible types: Rocks, Frogs, Fish, Plants, Fossils, Metals, Crystals, Postcards
  - Collectibles found by: digging in dirt mounds, fishing at water, harvesting plants, exploring
  - `CollectionTracker` resource: tracks which collectibles the household has found
  - Collections panel: shows progress toward completing each set
  - Completing a collection gives aspiration points and a moodlet
  - Collectibles can be displayed on shelves or sold for money
  - Rare collectibles have higher value

- [ ] **21.10** Implement gardening system
  - Plant interactions: "Plant" (place seed in garden spot), "Water", "Weed", "Harvest"
  - Plant growth stages: Seed → Sprout → Mature → Harvestable
  - Growth time varies per plant (1-7 in-game days)
  - Plants need watering every day or they wilt
  - Quality of harvest depends on Gardening skill and plant care
  - Harvested plants can be eaten raw, cooked, or sold
  - Seasonal plants: some only grow in certain seasons

- [ ] **21.11** Implement fishing system
  - Fish at water spots (pond, ocean, river)
  - Fishing interaction: cast line, wait, reel in (mini-game or automatic)
  - Fish type depends on location, time of day, and bait used
  - Fishing skill affects catch rate and fish quality
  - Caught fish can be: cooked, mounted on wall, sold, or kept in inventory
  - Fish rarity: Common, Uncommon, Rare, Legendary

- [ ] **21.12** Implement phone and computer interactions
  - Phone: "Call Sim" (social), "Text" (social, less effective), "Order Groceries", "Call Services"
  - Phone: "Take Photo" (photography skill), "Browse Web" (fun), "Play Mobile Game" (fun)
  - Computer: "Work from Home" (career), "Browse Web" (fun), "Program" (skill), "Write" (skill)
  - Computer: "Order Items" (buy mode delivery), "Video Call" (social), "Play Video Games" (fun)
  - Computer: "Find Job" (career), "Check Email" (career events), "Stream" (fun)
  - Phone/Computer can access the catalog for remote ordering (delivered to mailbox)

## Phase 22: Construction & Architecture Details

- [ ] **22.1** Implement staircase and multi-level building
  - Staircase object: connects ground floor to second floor
  - Second floor rendering: same system as ground floor, elevated Y position
  - Sims path up/down stairs seamlessly
  - Floor selection UI: toggle between floors in build mode
  - Support for up to 3 floors (ground + 2 stories)
  - Elevator object for elders/disabled (future phase)

- [ ] **22.2** Implement roof system
  - Roof types: flat, gable, hip, shed
  - Auto-roof generation: detect wall outlines, generate appropriate roof shape
  - Manual roof placement: click and drag roof sections
  - Roof color/texture selection
  - Roofs hide when inside a room (wall cutaway applies to roofs)
  - Roof overhang affects interior lighting

- [ ] **22.3** Implement pool and outdoor structures
  - Pool tool: dig rectangle, set depth, add ladder and diving board
  - Pool interactions: "Swim" (fun, energy drain), "Swim Laps" (fitness skill), "Play in Pool" (fun)
  - Pool maintenance: "Clean Pool" (hygiene affects pool quality)
  - Deck and patio objects: outdoor seating, grill, fire pit, hot tub
  - Fence tool: place fences around property, pool safety fence

- [ ] **22.4** Implement terrain manipulation
  - Raise/lower terrain for hills and basements
  - Flatten tool: level terrain to a set height
  - Terrain height affects sim movement (sims walk up/down slopes)
  - Water features: place pond or stream at terrain low points
  - Terrain painting: paint different ground textures (grass, sand, dirt, snow)
  - Foundation tool: raise entire lot foundation for elevated floors

- [ ] **22.5** Implement basement construction
  - Basement tool: dig down from ground level
  - Basements are 1 level below ground, same wall system
  - Stairs connecting basement to ground floor
  - Limited natural light in basements (affects mood)
  - Basement can flood if plumbing breaks (future phase)

- [ ] **22.6** Implement deck and porch building
  - Deck objects: raised platform attached to house
  - Porch: covered area at front/back door
  - Railing: auto-place on deck edges and porches
  - Deck supports visible from underneath
  - Deck staining/painting: change deck color in build mode

- [ ] **22.7** Implement room auto-detection and room score
  - Flood-fill algorithm to detect enclosed rooms from wall layout
  - Each detected room gets a `Room` component with: walls, floor, area, objects inside
  - Room score: calculated from value of objects, cleanliness, lighting, decoration
  - Room score affects sim mood: high score = positive moodlet, low score = negative
  - Room score displayed in build mode (tooltip on room)
  - Outdoor areas have a separate "lot score"

- [ ] **22.8** Implement wall style and paint system
  - Wall style categories: plain paint, patterned wallpaper, brick, stone, wood paneling, tile
  - Each wall face (interior/exterior) can have independent style
  - Wall trim and molding: baseboard, crown molding, wainscoting
  - Half-wall and divider wall options (shorter, no room enclosure)
  - Generate wall textures via MCP image gen tool

## Phase 23: Emotion & Mood Deep Dive

- [ ] **23.1** Implement emotion intensity levels
  - Each emotion has 4 intensity levels: Low, Medium, High, Extreme
  - Example: Fine → Happy → Very Happy → Elated (or Fine → Sad → Very Sad → Devastated)
  - Intensity determined by sum of active moodlet weights
  - Higher intensity emotions have stronger effects on autonomy and interactions
  - Extreme emotions can trigger special behaviors (e.g., Extreme Anger → "Rage" interaction)

- [ ] **23.2** Implement emotion-specific interactions
  - Angry: "Furious Running", "Slam Door", "Yell At", "Work Out Aggressively"
  - Sad: "Cry", "Cry in Closet", "Call Sad Friend", "Watch Sad Movie"
  - Happy: "Skip", "Cheer Up Another Sim", "Bake Treat", "Play Music"
  - Flirty: "Pickup Line", "Seranade", "Blow Kiss", "Romantic Dance"
  - Focused: "Ponder", "Research", "Plan", "Browse Encyclopedia"
  - Energized: "Jog", "Push Ups", "Go Running", "High Five"
  - Tense: "Take Deep Breaths", "Complain", "Kick Trash Can"
  - Embarrassed: "Hide in Bed", "Fret", "Apologize"
  - Uncomfortable: "Complain About Temperature", "Take Medicine"

- [ ] **23.3** Implement emotion decay and transitions
  - Emotions decay over time if not reinforced by new moodlets
  - Default emotion returns when all moodlets expire (usually "Fine")
  - Moodlet duration categories: brief (5 min), medium (1 hour), long (4 hours), persistent (until condition resolves)
  - Some interactions create reinforcing moodlets (e.g., painting while Inspired keeps the moodlet alive)
  - Emotional death: extreme emotion sustained for too long can kill (very rare, elders only)

- [ ] **23.4** Implement emotional aura system
  - Certain objects and decorations emit emotional auras
  - Decorative items: inspiring painting (Inspired aura), romantic candle (Flirty aura)
  - Auras affect sims within a radius (the room the object is in)
  - Sims can toggle "enable emotional aura" on objects (on/off)
  - Multiple auras in the same room stack (but diminishing returns)
  - Aura strength shown as glow effect on the object

- [ ] **23.5** Implement moodlet source tracking and UI
  - Each moodlet shows its source icon and text: "+1 Happy from Beautiful Decor"
  - Clicking a moodlet in the panel highlights the source object or sim
  - Moodlet panel shows: emotion type, intensity, remaining duration, source
  - Moodlets sorted by weight (strongest at top)
  - Visual indicator: sim glow color matches emotion (blue = sad, red = angry, pink = flirty)

- [ ] **23.6** Implement mood-driven autonomous behaviors
  - Angry sims may autonomously: kick trash can, start argument, work out
  - Sad sims may autonomously: cry, seek comfort, watch TV alone
  - Flirty sims may autonomously: check phone, groom, seek romantic partner
  - Energized sims may autonomously: exercise, go jogging, clean
  - Inspired sims may autonomously: paint, write, play instrument
  - Bored sims may autonomously: browse phone, nap, seek fun

## Phase 24: Community Lots & Travel

- [ ] **24.1** Implement community lot system
  - `CommunityLot` component: type, name, operating_hours, entry_fee
  - Lot types: Park, Gym, Library, Bar, Nightclub, Cafe, Museum, Retail, Restaurant
  - Community lots are pre-built and loaded when sim travels there
  - Multiple community lots in the neighborhood
  - Sims from other households also visit community lots

- [ ] **24.2** Implement travel system
  - "Travel" interaction on phone: opens lot selection menu
  - Sim walks to edge of lot, screen transitions, sim arrives at destination
  - Travel takes in-game time based on distance (5-30 minutes)
  - Travel costs money (taxi fare) unless walking to nearby lot
  - Loading screen during travel with sim trivia tips
  - Household sim can "Travel With" other household members

- [ ] **24.3** Implement park lot type
  - Park: open green space with benches, playground, pond, walking paths
  - Park interactions: "Jog" (fitness), "Play Chess" (logic), "Feed Ducks" (fun), "Cloud Watch" (fun)
  - Park attracts NPCs for socialization
  - Park has a festival area for holiday events
  - Playground objects for children: slide, swings, jungle gym

- [ ] **24.4** Implement gym lot type
  - Gym: treadmills, weights, punching bag, yoga mats, showers
  - Gym interactions: "Work Out" (fitness skill), "Take Class" (fitness + social)
  - Gym membership fee (weekly)
  - Gym atmosphere: "Energized" aura from exercise equipment
  - Trainer NPC who can mentor fitness skill

- [ ] **24.5** Implement bar and nightclub lot types
  - Bar: counter, stools, drink menu, bartender NPC
  - Bar interactions: "Order Drink", "Make Drink" (Mixology), "Sit at Bar", "Listen to Music"
  - Nightclub: dance floor, DJ booth, VIP area
  - Nightclub interactions: "Dance", "Order Fancy Drink", "Flirt", "Join Dance Circle"
  - Nightclub opens only at night (8 PM - 2 AM)
  - "Bar Fly" moodlet from visiting bar, "Dance Machine" moodlet from nightclub

- [ ] **24.6** Implement library and cafe lot types
  - Library: bookshelves, computers, study tables, quiet atmosphere
  - Library interactions: "Read", "Research" (logic skill), "Study" (any skill), "Use Computer"
  - Library has "Focused" aura from books
  - Cafe: coffee maker, pastries, seating, atmosphere
  - Cafe interactions: "Order Coffee", "Study at Cafe" (focused moodlet), "People Watch"
  - Cafe has "Energized" aura from coffee

- [ ] **24.7** Implement restaurant lot type
  - Restaurant: host stand, dining tables, kitchen, bathroom
  - Restaurant interactions: "Order Meal", "Dine In", "Order to Go"
  - Restaurant quality depends on chef NPC's cooking skill
  - Romantic restaurant gives "Flirty" moodlet
  - Restaurant cost varies: fast food (§10), mid-range (§30), fine dining (§80)
  - Chef career sims can work at restaurant (part-time)

- [ ] **24.8** Implement retail lot type
  - Retail store: shelves with goods, cash register, browsing area
  - Retail interactions: "Browse", "Buy Item" (adds to inventory), "Sell Valuables"
  - Player-owned retail: hire employees, set prices, manage inventory
  - Retail career: sales employee → manager → store owner
  - Items for sale: clothes, collectibles, crafts, food

## Phase 25: Romance & Family Systems

- [ ] **25.1** Implement romantic relationship progression
  - Romantic interactions unlock at friendship thresholds
  - Romance levels: Stranger → Romantic Interest → Boyfriend/Girlfriend → Fiancé → Spouse
  - Each level unlocks new interactions (propose, move in, try for baby)
  - Romantic relationship score tracked separately from friendship
  - Romantic score can go negative (bad date, rejection, cheating)

- [ ] **25.2** Implement dating and romantic events
  - "Plan Date" interaction: choose location, invite partner
  - Date score tracked: positive interactions increase, negative decrease
  - Date milestones: Bronze, Silver, Gold date score
  - Gold date gives big romantic boost and moodlet
  - Date locations: home, restaurant, park, bar
  - Date failures (all needs low) give "Terrible Date" moodlet

- [ ] **25.3** Implement marriage system
  - "Propose" interaction (requires high romantic score + friendship)
  - Proposal success/failure based on relationship and mood
  - Engagement moodlet: "Just Engaged" (very happy)
  - Wedding event: plan ceremony at home or community lot
  - Wedding interactions: "Exchange Vows", "Kiss the Bride", "Cut Cake", "First Dance"
  - Married sims share household funds and can "Try for Baby"

- [ ] **25.4** Implement pregnancy and baby system
  - "Try for Baby" interaction available for married/committed couples
  - Pregnancy lasts 3 in-game days
  - Pregnant sim gets moodlets: "Expecting" (happy), morning sickness (uncomfortable)
  - Pregnancy progression: 1st trimester (nausea), 2nd trimester (showing), 3rd trimester (tired)
  - "Give Birth" event: sim goes to hospital (off-lot), returns with baby
  - Baby gender randomized (or chosen in settings)

- [ ] **25.5** Implement breakup and divorce
  - Romantic score decrease leads to "Unhappy Relationship" moodlet
  - "Break Up" interaction: ends romantic relationship, big negative moodlets
  - "Divorce" interaction for married sims: splits household, one sim moves out
  - Divorce affects both sims' mood for several in-game days
  - Former partners can eventually become friends again (or remain enemies)
  - "Ask to Just Be Friends" interaction: converts romantic to platonic

- [ ] **25.6** Implement parenting interactions
  - Parent-child interactions: "Teach", "Encourage", "Scold", "Hug", "Read to Sleep"
  - Parenting style affects child's traits and mood
  - "Potty Train" for toddlers (hygiene skill)
  - "Help with Homework" for children (school performance boost)
  - "Ground" interaction: child can't leave the house for set time
  - "Family Outing" interaction: whole household travels together

- [ ] **25.7** Implement family events and milestones
  - Birthday: celebration event, age transition, "Birthday Moodlet"
  - Anniversary: romantic event for married couples
  - First Day of School: child gets "Nervous" moodlet
  - Graduation: teen gets "Proud" moodlet, career boost
  - Retirement: elder gets "Relieved" moodlet, pension starts
  - Funeral: event for deceased sim, attendees get "Grieving" moodlet

## Phase 26: Simlish & Audio Deep Dive

- [ ] **26.1** Create simlish voice system
  - Generate or source simlish-style vocalizations (nonsense syllables)
  - Simlish for: greetings, questions, exclamations, arguments, laughter
  - Voice pitch varies per sim (based on `SimVoice` component)
  - Emotional variation: happy simlish, sad simlish, angry simlish, flirty simlish
  - Simlish plays during conversations and reactions

- [ ] **26.2** Implement ambient soundscapes
  - Morning: birds chirping, alarm clocks, traffic
  - Daytime: neighborhood sounds, lawnmowers, kids playing
  - Evening: crickets, wind, distant traffic
  - Night: owls, wind, quiet hum
  - Indoor: clock ticking, fridge hum, floor creaks, water pipes
  - Sound volume based on location (louder outdoors, muffled indoors)

- [ ] **26.3** Implement music system
  - Build mode music: relaxing, jazzy, ambient (Sims-style)
  - Live mode music: subtle ambient that changes with time of day
  - CAS music: upbeat, creative
  - Stereo object: sim can "Listen to Music" for fun moodlet
  - Music genres: Pop, Rock, Classical, Jazz, Electronic, Country
  - Generate background music tracks via MCP or use royalty-free

- [ ] **26.4** Implement object sound effects
  - Footstep sounds: vary by surface (wood, tile, carpet, grass, concrete)
  - Door sounds: open, close, lock, knock
  - Kitchen sounds: chopping, sizzling, microwave beep, fridge door
  - Bathroom sounds: shower running, toilet flush, sink running
  - Electronic sounds: TV channel change, computer typing, phone ring
  - Furniture sounds: sit on couch, bed creak, chair scrape
  - Generate/curate all sound effects

- [ ] **26.5** Implement UI sound effects
  - Button click: soft, satisfying click sound
  - Button hover: subtle tick
  - Notification: pleasant chime
  - Error: low buzz or negative tone
  - Tab switch: swish
  - Pie menu open: whoosh
  - Pie menu select: pop
  - Need warning: gentle alarm
  - Money change: cash register ding (positive), sad trombone (negative)

- [ ] **26.6** Implement event sound effects
  - Sim level up: fanfare/trumpet
  - Career promotion: celebratory jingle
  - Relationship milestone: romantic harp
  - Death: somber tune
  - Fire alarm: loud, jarring
  - Doorbell: classic chime
  - Phone ring: varied ringtones
  - Alarm clock: persistent beeping

## Phase 27: Accessibility & Input

- [ ] **27.1** Implement keyboard controls
  - WASD: camera pan
  - Q/E: camera rotate
  - +/- or scroll: camera zoom
  - 1/2/3: game speed
  - Space: pause/resume
  - Escape: close current panel/menu
  - Tab: cycle through household sims
  - Enter: confirm dialog
  - Delete: sell/delete object in buy mode
  - R: rotate object in build mode
  - B: open build mode
  - H: open buy mode
  - F1-F6: select specific household sim

- [ ] **27.2** Implement mouse controls
  - Left click: select sim/object, confirm placement
  - Right click: open pie menu on sim/object
  - Middle click/drag: camera pan
  - Scroll wheel: camera zoom
  - Click and drag: build walls, select area
  - Double click: zoom to sim/object
  - Hover: show tooltip after delay

- [ ] **27.3** Implement touch controls (WASM/mobile)
  - Single tap: select
  - Long press: open pie menu
  - Two-finger pinch: zoom
  - Two-finger drag: pan camera
  - Swipe: rotate camera
  - Tap and drag: move object in build mode
  - Touch-friendly UI: larger hit targets, clear visual feedback

- [ ] **27.4** Implement accessibility features
  - Colorblind mode: alternate need bar colors (patterns instead of just colors)
  - High contrast mode: stronger borders, larger text
  - Font size options: small, medium, large
  - Subtitle system: display text for all sound effects (doorbell, phone, etc.)
  - Reduced motion mode: disable particle effects and animations
  - Screen reader support: ARIA labels on all UI elements (WASM)
  - Auto-pause on important events (fire, death, need critical)

- [ ] **27.5** Implement gamepad support
  - Map all camera controls to right stick
  - Map sim selection to shoulder buttons
  - Map pie menu to face buttons
  - Map build/buy mode to start/select
  - Map speed controls to D-pad
  - Full gamepad navigation of all UI panels
  - Steam-compatible controller mappings

- [ ] **27.6** Implement input remapping
  - Settings panel: remap any key/button to any action
  - Preset control schemes: Default, WASD, Arrow Keys, Gamepad
  - Reset to defaults button
  - Conflict detection: warn if two actions map to same key
  - Save/load custom control profiles

## Phase 28: Post-Launch & Future Features

- [ ] **28.1** Implement pet system (dogs and cats)
  - Pet component bundle: PetId, PetName, PetBreed, PetTraits
  - Pet needs: Hunger, Energy, Fun, Social, Bladder, Affection
  - Dog breeds: Labrador, Poodle, Bulldog, Husky, Corgi (different trait tendencies)
  - Cat breeds: Siamese, Persian, Maine Coon, Tabby, Sphinx (different trait tendencies)
  - Pet interactions: "Pet", "Play Fetch", "Walk", "Feed", "Train", "Scold"
  - Pets can learn tricks (Sit, Shake, Roll Over) with training
  - Pets autonomously interact with objects and sims
  - Pet generates `PetSimMesh` (procedural low-poly animal shapes)

- [ ] **28.2** Implement vehicle system
  - Car object: can be placed on lot (driveway required)
  - Car types: economy (§5,000), mid-range (§15,000), luxury (§50,000)
  - Car interactions: "Drive to Work" (faster commute), "Go for a Joyride" (fun)
  - Bicycle: cheap transport option, fun + fitness
  - Carpool: NPCs offer rides (free but slower)
  - No free-roam driving (travel is screen transition only)

- [ ] **28.3** implement supernatural and occult life states
  - Ghost: dead sims can haunt the lot, interact with objects, scare living sims
  - Vampire: needs change (no hunger, thirst for plasma), sunlight avoidance, supernatural speed
  - Spellcaster: learn spells, brew potions, magical interactions
  - Werewolf: transformation cycle, enhanced needs, pack dynamics
  - Each occult state has unique interactions, needs, and visual effects
  - Occult states can be enabled/disabled per save file

- [ ] **28.4** Implement season-specific activities
  - Spring: gardening bonus, flower viewing, spring rain moodlet
  - Summer: pool party, sunburn risk, ice cream, outdoor activities
  - Fall: harvest festival, raking leaves, hot drinks, cozy moodlet
  - Winter: snowman building, ice skating, holiday celebrations, cocoa
  - Seasonal clothing auto-suggested for sims
  - Seasonal decor: pumpkins, holiday lights, spring flowers

- [ ] **28.5** Implement multiplayer social features (asynchronous)
  - Gallery: upload/share lots and households online
  - Download other players' builds and families
  - Rating system for shared content
  - Challenge modes: "Build the best house under §10,000"
  - Leaderboards: household net worth, sim skill levels, relationship milestones
  - No real-time multiplayer; all sharing is asynchronous

- [ ] **28.6** Implement modding tools (see Phase 29 for documentation)
  - Custom content validator CLI: `just-life validate-mod <mod_dir>` checks RON schema, texture sizes, locale keys
  - In-game mod manager: enable/disable mods, see conflicts, view load order
  - Mod conflict resolver: detect and warn about duplicate keys across mods
  - Example mod packs shipped with the game (see Phase 29)

- [ ] **28.7** Implement replay and story progression
  - Story mode: record key events in household timeline (first kiss, marriage, death, etc.)
  - Household timeline view: scrollable list of major events with timestamps
  - Auto-generated "story summary" at end of sim's life
  - Screenshot mode: pause game, free camera, apply filters
  - Photo album: collect photos taken by sims, view in album
  - Neighborhood story: track events across all households (who moved in, who married, etc.)

---

## Phase 29: Modding Documentation (Mandatory)

All documentation lives in the `docs/` directory and must be complete before the game is considered shippable. Every doc file is checked into the repo and updated alongside code changes.

- [ ] **29.1** Create `docs/README.md` — modding documentation hub
  - Table of contents linking to all other docs files
  - Quick-start guide: how to create your first mod in 5 minutes
  - File structure overview of the `mods/` directory
  - Glossary of game-specific terms (sim, need, moodlet, interaction, etc.)
  - Link to the example mods shipped with the game
  - Version compatibility table (which game version the docs target)

- [ ] **29.2** Create `docs/mod-structure.md` — mod folder layout
  - Required folder structure: `mods/<mod_name>/manifest.ron`
  - `mods/<mod_name>/data/` — RON data overrides (careers, objects, traits, etc.)
  - `mods/<mod_name>/textures/` — texture overrides and new textures
  - `mods/<mod_name>/locales/` — translation overrides and new locale files
  - `mods/<mod_name>/scripts/` — custom interaction scripts (future: WASM modules)
  - `manifest.ron` schema: mod name, version, author, description, dependencies, load order priority
  - How the game discovers and loads mods on startup
  - Mod naming conventions and forbidden characters
  - How to package a mod for distribution (zip structure)

- [ ] **29.3** Create `docs/ron-format.md` — RON data format reference
  - Overview of RON (Rusty Object Notation) syntax
  - How RON maps to Rust structs in the game code
  - Common patterns: enums, structs, HashMaps, Vecs, nested types
  - Full schema reference for each data file:
    - `careers.ron` — CareerTrack, CareerLevel, promotion requirements
    - `catalog.ron` — CatalogItem, dimensions, needs_satisfied, interactions list
    - `interactions.ron` — Interaction, duration, needs_effects, required_object, multi-step chains
    - `traits.ron` — TraitDefinition, conflicts, need_decay_modifiers, autonomy_weights
    - `aspirations.ron` — AspirationDefinition, milestones, reward_points
    - `recipes.ron` — Recipe, ingredients, cooking_skill_required, quality_levels
    - `config.ron` — GameConfig, all tunable values with descriptions
  - Validation rules: required fields, value ranges, foreign key constraints
  - Common errors and how to fix them
  - Example: adding a new career track step-by-step with RON snippets

- [ ] **29.4** Create `docs/adding-objects.md` — custom furniture and objects guide
  - Overview of the object catalog system
  - Step-by-step: define a new object in `catalog.ron`
  - Object schema: name, category, subcategory, price, description, dimensions (width x depth), interactions, needs_satisfied, mesh_definition
  - Mesh definitions: how to compose objects from procedural primitives (cubes, cylinders, spheres)
  - `MeshDefinition` reference: shape type, scale, rotation, offset, material, color
  - How to assign textures (from `textures/` folder or MCP-generated)
  - How to define interactions for a new object (link to interactions.ron)
  - How to test a new object in-game: spawn via debug console
  - Example: adding a "Gaming Desk" with custom interactions
  - Example: adding a "Hot Tub" with complex multi-tile footprint
  - Object validation checklist: no overlap, correct price, balanced needs

- [ ] **29.5** Create `docs/adding-traits.md` — custom personality traits guide
  - Overview of the trait system and how traits affect gameplay
  - Step-by-step: define a new trait in `traits.ron`
  - Trait schema: name, description, icon, conflicts, category, effects
  - Effect types: `NeedDecayModifier { need: Hunger, multiplier: 0.8 }`, `AutonomyWeightOverride { need: Fun, weight: 1.5 }`, `SocialOutcomeModifier { interaction: Joke, bonus: 0.3 }`
  - Trait conflict resolution: how to define mutually exclusive traits
  - How to add a custom moodlet triggered by a trait
  - How to link a trait to new autonomous behaviors
  - Example: adding a "Night Owl" trait (energy decays slower at night, faster in morning)
  - Example: adding a "Perfectionist" trait (skill gains faster, but failures cause bigger mood drops)
  - Trait balance guidelines: power level, synergy, anti-synergy

- [ ] **29.6** Create `docs/adding-careers.md` — custom career tracks guide
  - Overview of the career system (levels, performance, promotions)
  - Step-by-step: define a new career track in `careers.ron`
  - CareerTrack schema: name, description, icon, levels (1-10)
  - CareerLevel schema: title, salary, work_days, work_hours, performance_threshold, required_skills
  - Promotion logic: how performance, skills, and relationships determine promotion
  - How to add career-specific chance cards
  - How to add career-specific interactions (e.g., "Work Overtime" for career type)
  - Example: adding a "Streamer" career (Entertainment variant, work from home)
  - Example: adding a "Chef" career (Culinary track, cooking skill focus)
  - Career balance guidelines: salary curves, promotion pacing

- [ ] **29.7** Create `docs/adding-interactions.md` — custom interactions guide
  - Overview of the interaction system (types, queues, execution)
  - Interaction schema: name, display_name, duration, needs_effects, required_object, required_skill, mood_effects, animation_state
  - Multi-step interactions: how to define interaction chains (e.g., cooking)
  - Social interactions: how to define relationship requirements and effects
  - Conditional interactions: available only with specific traits, moods, or time of day
  - How to register interactions with the pie menu system
  - How to add interaction icons (texture or procedural)
  - Example: adding a "Meditate" interaction (energy + fun, requires Calm trait or Focused mood)
  - Example: adding a "Cook Gourmet Meal" multi-step interaction chain
  - Interaction balance: duration vs. need satisfaction, cooldowns, autonomy weights

- [ ] **29.8** Create `docs/adding-recipes.md` — custom recipes and food guide
  - Overview of the cooking/food system
  - Recipe schema: name, ingredients, required_appliances, cooking_skill_required, cooking_time, hunger_satisfaction, quality_levels
  - Ingredient system: how to define new ingredients
  - How cooking skill affects recipe outcome quality
  - How to add a recipe to the fridge/stove menu
  - How to define food quality levels and their mood effects
  - Example: adding a "Spaghetti Bolognese" recipe (multi-ingredient, medium skill)
  - Example: adding a "Gourmet Lobster" recipe (high skill, expensive ingredients)
  - Food balance guidelines: cost vs. hunger satisfaction vs. skill required

- [ ] **29.9** Create `docs/texture-guide.md` — creating and importing textures
  - Overview of the texture pipeline (MCP image gen → asset pipeline → Bevy)
  - Recommended texture sizes: 64x64 (icons), 128x128 (small objects), 256x256 (furniture), 512x512 (floors/walls), 1024x1024 (skybox)
  - Texture naming convention: `<category>_<name>_<variant>.png` (e.g., `floor_hardwood_light.png`)
  - How to generate textures using MCP image gen tool (prompts, aspect ratios, styles)
  - How to import custom textures: place in `mods/<mod_name>/textures/` with matching filenames
  - How texture overrides work: mod textures replace base game textures by filename
  - PBR material properties: how to define metallic, roughness, normal maps
  - Texture atlas guide: how to create sprite sheets for animated objects
  - Color palette guide: recommended color palette for a cohesive game look
  - Example prompts for MCP image gen: floors, walls, furniture, UI elements, sim clothing

- [ ] **29.10** Create `docs/locale-guide.md` — localization and translation guide
  - Overview of the locale system (RON-based key-value store)
  - Locale file structure: `locales/<language_code>.ron`
  - Key naming convention: `<scope>.<category>.<item>.<property>` (e.g., `ui.needs.hunger.name`)
  - How to add a new locale: copy `en.ron`, translate all values, save as `<language_code>.ron`
  - How to add locale keys for custom content (mods can extend locales)
  - Fallback behavior: missing keys fall back to English
  - Right-to-left (RTL) language considerations for UI layout
  - Character encoding: all files must be UTF-8
  - How to test a locale in-game: set language in options
  - List of required keys for a complete translation (UI, objects, interactions, traits, careers)

- [ ] **29.11** Create `docs/config-reference.md` — game configuration reference
  - Full documentation of `config.ron` with every field explained
  - Need decay rates: base values per need, trait modifiers, time-of-day modifiers
  - Economy: starting funds, salary multipliers, bill percentages, depreciation rates
  - Aging: days per life stage, aging speed multiplier
  - Autonomy: weights per need, trait modifiers, desperation thresholds
  - Relationship: gain/loss rates, decay rates, milestone thresholds
  - Career: performance gain/loss rates, promotion thresholds
  - Skill: XP gain rates, level caps, trait modifiers
  - Difficulty presets: Easy/Normal/Hard value tables
  - How to create a custom difficulty preset
  - How modders can override config values without editing the base file

- [ ] **29.12** Create `docs/api-reference.md` — ECS component and system reference
  - Overview of the Bevy ECS architecture used in Just Life
  - List of all public Components with their fields and types
  - List of all public Resources with their fields and types
  - List of all Events with their fields
  - List of all Systems with their scheduling (PreUpdate, Update, PostUpdate)
  - Entity hierarchy diagram: how a Sim entity is composed
  - Entity hierarchy diagram: how a PlacedObject entity is composed
  - Entity hierarchy diagram: how a Wall/Door/Window entity is composed
  - How to add a custom Bevy Plugin that integrates with existing systems
  - System ordering and dependency rules
  - How to register custom Components that the save system will serialize
  - How to register custom Interactions that appear in the pie menu

- [ ] **29.13** Create `docs/save-format.md` — save file format reference
  - Overview of the save/load system (RON serialization)
  - Save file structure: header (version, timestamp), world state, sim states, relationships, time
  - How to add a new serializable Component to the save system
  - Save file versioning: how migrations work when the format changes
  - How to manually inspect and edit a save file
  - Save file compatibility: what happens when a mod is removed that added data
  - Browser save: localStorage key structure and size limits
  - Native save: file path and backup strategy (auto-save rotation)

- [ ] **29.14** Create `docs/example-mods.md` — worked example mods
  - Example Mod 1: "Gourmet Expansion" — adds 5 new recipes, 2 new kitchen objects, and a cooking aspiration
    - Full `manifest.ron`
    - Full `data/catalog.ron` additions
    - Full `data/recipes.ron` additions
    - Full `data/aspirations.ron` additions
    - Texture files for new objects (generated via MCP)
    - Locale additions for new item names
  - Example Mod 2: "Tech Career Pack" — adds a new career track with 10 levels and chance cards
    - Full `manifest.ron`
    - Full `data/careers.ron` additions
    - Full `data/interactions.ron` additions
    - Locale additions for career titles and chance card text
  - Example Mod 3: "Cozy Traits" — adds 3 new personality traits with custom moodlets
    - Full `manifest.ron`
    - Full `data/traits.ron` additions
    - Full `data/interactions.ron` additions for trait-specific behaviors
  - Each example includes: how to install, how to verify it loads, how to uninstall

- [ ] **29.15** Create `docs/troubleshooting.md` — modding troubleshooting guide
  - Common error messages and their solutions
  - "Failed to parse RON" — syntax errors, missing commas, incorrect types
  - "Unknown variant" — enum variant name mismatch with game code
  - "Texture not found" — incorrect filename or path
  - "Duplicate key" — mod conflicts and how to resolve them
  - "Validation failed" — schema mismatch, value out of range
  - Game crashes on startup with mod — how to read the error log
  - Mod works in dev but not in release — common WASM compatibility issues
  - How to use the debug console to test mod content
  - How to report mod bugs: log file location, required info
  - FAQ section with answers to common modding questions

## Phase 30: Pathfinding & Navigation Deep Dive

- [ ] **30.1** Implement navmesh generation from world geometry
  - Generate navigation mesh from floor tiles, walls, doors, and placed objects
  - Navmesh updates when build mode changes walls or objects
  - Navmesh includes indoor/outdoor regions connected by doors
  - Staircase navmesh links for multi-story buildings
  - Navmesh visualization toggle for debug (shows walkable areas in blue)
  - Store navmesh as a resource that systems can query

- [ ] **30.2** Implement A* pathfinding on navmesh
  - A* pathfinding with configurable heuristics (Euclidean distance default)
  - Path smoothing: remove unnecessary waypoints from A* result
  - Path caching: store common routes, invalidate on build mode changes
  - Max path length: cancel routing if destination is unreachable or too far
  - Path recalculation when obstacles change mid-route (e.g., door closes)
  - Debug visualization: draw path lines for selected sim

- [ ] **30.3** Implement sim collision avoidance
  - Sims avoid each other on paths (steer around nearby sims)
  - Sims wait at doorways if another sim is passing through
  - Sims queue behind occupied objects (e.g., wait for bathroom)
  - "Excuse me" interaction: sim asks blocking sim to move
  - Collision radius per sim (smaller for children, larger for adults with wide stances)
  - Smooth steering: sims curve around obstacles rather than stopping and turning

- [ ] **30.4** Implement terrain pathfinding modifiers
  - Different terrain types affect movement speed: concrete (fast), grass (normal), sand (slow), water (impassable)
  - Puddles and snow patches slow sims down
  - Sims prefer paved paths over grass (path weight preference)
  - Stairs are slower than flat ground
  - Swimming: only allowed in pool tiles, very slow
  - Running: 1.5x speed, drains energy faster

- [ ] **30.5** Implement routing failure and recovery
  - When path is unreachable: sim shows frustration animation, cancels interaction
  - "Can't Get There" thought bubble appears above sim
  - Routing failure counts: if sim fails 3 times, autonomy seeks alternative
  - Route recalculation on: door lock/unlock, object moved, wall placed/deleted
  - Debug command: highlight all unreachable objects from sim's current position
  - Fallback: if primary path fails, try secondary path or nearest alternative object

- [ ] **30.6** Implement multi-floor routing
  - Sims path to staircase → climb stairs → path on next floor
  - Elevator object (future): sim enters, waits, arrives at floor
  - Multi-floor path: concatenate ground-floor path + stair transition + upper-floor path
  - Floor selection: sim automatically uses correct floor based on target
  - Sims on different floors don't collide (separate navmesh layers)

- [ ] **30.7** Implement vehicle and off-lot routing
  - "Travel to..." interaction: sim walks to lot edge, screen transitions, arrives at destination
  - Routing to community lots: path to edge of current lot → travel → path from lot edge to target
  - Car ownership reduces travel time (walk: 30 min, car: 5 min, taxi: 10 min)
  - Sims carpool to work if they don't own a car
  - Off-lot routing is simplified (no real-time pathfinding between lots)

## Phase 31: School & Education System

- [ ] **31.1** Implement school system for children and teens
  - Children attend elementary school (9 AM - 3 PM, weekdays)
  - Teens attend high school (8 AM - 2 PM, weekdays)
  - School is off-lot: sim teleports there and back
  - School performance tracked daily (like job performance for adults)
  - Grades: A, B, C, D, F — based on performance and homework completion
  - "Do Homework" interaction at home improves school performance

- [ ] **31.2** Implement school events and interactions
  - School bus/carpool arrives at scheduled time
  - "Skip School" interaction: sim stays home, performance drops, moodlet "Rebel"
  - "Go to School" interaction: auto-queued if not already at school
  - After-school activities: sports, chess club, drama, art club (boost skills)
  - Parent-teacher conferences: adult sims can attend for relationship boost with child
  - Prom event for teens (social event at school lot)
  - Graduation ceremony for teens aging up to young adults

- [ ] **31.3** Implement homework and studying
  - Homework object in child/teen inventory after school
  - "Do Homework" interaction: takes 1-2 in-game hours, improves school performance
  - "Ask for Help with Homework": adult sim assists, faster completion, relationship boost
  - Homework quality affected by: mood, skill level, desk quality
  - Neglecting homework: performance drops, "Bad Grade" moodlet
  - "Study" interaction on computer or bookshelf: slower but still helps performance

- [ ] **31.4** Implement university system (young adults+)
  - University enrollment: choose major (tech, arts, science, business)
  - University is off-lot: sim teleports to campus
  - Classes take 4-6 hours, 3 days per week
  - Tuition cost: §500-§2000 per term (configurable)
  - University performance: based on class attendance, studying, assignments
  - Degree completion: unlocks higher career starting levels
  - "Distinguished Degree" for top performers: even better career start

- [ ] **31.5** Implement skill-building for children
  - Children gain skills at an accelerated rate (fast learners)
  - Child-specific skills: Creativity, Mental, Motor, Social
  - Child skills convert to adult skills at age-up (Creativity → various art skills)
  - Children can't gain adult skills directly (cooking, handiness)
  - Toddler skills: Movement, Communication, Imagination, Thinking
  - Skill toys: blocks (Mental), dollhouse (Social), xylophone (Creativity)

- [ ] **31.6** Implement school performance UI
  - School performance bar in sim info panel (children/teens only)
  - Current grade displayed (A through F)
  - Hover shows: performance trend (improving/declining), days until report card
  - Report card notification at end of each in-game week
  - Good grades: "On the Honor Roll" moodlet (+happiness)
  - Bad grades: "Failing" moodlet (+tension), parent scolds child interaction

## Phase 32: Death, Ghosts & Afterlife

- [ ] **32.1** Implement death causes and mechanics
  - Death by starvation: hunger at 0 for extended period (3 in-game days grace)
  - Death by old age: natural death for elders (probability increases with age)
  - Death by fire: sim caught in fire without extinguishing
  - Death by electrocution: sim with low Handiness repairs broken electronics
  - Death by emotional extremes: laughter (too happy), rage (too angry), embarrassment (too mortified) — rare, elders only
  - Death by drowning: sim in pool with very low energy
  - Death by cow plant: sim eaten by carnivorous plant (future)
  - Each death type has a unique Grim Reaper animation

- [ ] **32.2** implement Grim Reaper
  - Grim Reaper NPC spawns on lot when a sim dies
  - Grim Reaper approaches the dead sim, performs soul collection animation
  - Other sims can "Plead for Sim's Life" interaction with Grim Reaper
  - Pleading success based on relationship strength and Grim's mood (random)
  - If pleading succeeds: sim is revived with all needs at 50%
  - If pleading fails: sim is permanently dead, becomes urn/tombstone
  - Grim Reaper leaves after 1 in-game hour

- [ ] **32.3** Implement urns, tombstones, and mourning
  - Dead sim becomes an urn (inside) or tombstone (outside) on the lot
  - Urn/tombstone shows sim's name and dates (birth-death)
  - "Mourn" interaction: sim cries at grave, gets "Grieving" moodlet (lasts 2 days)
  - "Strengthen Mourning" interaction: stronger grief moodlet
  - Grief moodlet decays over 7 in-game days
  - Urn can be moved in build mode
  - Multiple urns create a "memorial garden"

- [ ] **32.4** Implement ghost sim system
  - Ghost sims periodically emerge from their urn/tombstone at night
  - Ghost appearance: translucent, sim's death-color (orange=fire, blue=drowning, etc.)
  - Ghost interactions: "Possess Object" (makes object float), "Spook" (scares living sim)
  - Ghost mood: angry ghosts haunt more, sad ghosts cry, happy ghosts play
  - Living sims can "Chat with Ghost" (social need, but "Creeped Out" moodlet)
  - Ghosts can be "Put to Rest" by completing their unfinished business
  - Unfinished business: max a skill, see a loved one, fix a broken object

- [ ] **32.5** Implement ghost mechanics and interactions
  - Ghosts can interact with objects but not satisfy needs
  - Ghosts pass through walls (no pathfinding constraints)
  - Ghosts can possess electronics (TV turns on/off, computer types randomly)
  - Ghosts can scare sims: "Boo" interaction gives "Scared" moodlet
  - Ghost sims retain their personality and traits from life
  - Ghosts can be added to household with "Ask to Stay" interaction (high relationship required)
  - Playable ghosts: if added to household, ghost is fully controllable

- [ ] **32.6** Implement memorial and legacy systems
  - Family tree records all deceased sims with cause of death
  - Memorial wall in household: portraits of deceased family members
  - "Day of the Dead" holiday: ghosts emerge more frequently, sims visit graves
  - Ghostly visitors are more common on the anniversary of death
  - Legacy score: points for each generation that produces an heir
  - "Immortalized" achievement: sim's portrait hangs in a museum (very high lifetime happiness)

## Phase 33: Reactive World & Story Progression

- [ ] **33.1** Implement NPC story progression
  - Unplayed households progress autonomously: career promotions, relationships, children
  - Story progression is configurable: Full (all NPCs progress), Limited (only close friends), Off
  - NPC events appear as notifications: "Bob got promoted to Senior Developer!"
  - NPC relationship changes: "Alice and Bob are now dating!"
  - NPC babies: NPC households can have children autonomously
  - NPC deaths: NPCs die of old age, announced by notification
  - NPCs do NOT die of preventable causes during story progression (only old age)

- [ ] **33.2** Implement neighborhood dynamic events
  - Random neighborhood events: "Farmer's Market in the park this weekend!"
  - Neighborhood gossip: "Did you hear? The Johnsons are renovating their kitchen."
  - Neighborhood invitations: NPC invites your household to a party
  - Weather events affect the whole neighborhood: snow day, heat wave
  - Economic events: "Housing market boom — lot values increased 20%!"
  - Community events: charity drive, block party, neighborhood watch

- [ ] **33.3** Implement sim memory and story log
  - `MemoryLog` component: list of significant events in sim's life
  - Memory types: first kiss, first job, marriage, child born, death of loved one, skill maxed
  - Memories affect moodlets: seeing an old flame triggers nostalgic moodlet
  - Memory panel in sim info: scrollable list of all significant events
  - Memory fade: old memories have less emotional impact
  - Sims occasionally reference memories in conversation ("Remember when we met?")

- [ ] **33.4** Implement reactive world state
  - Empty lots in neighborhood: new households move in over time
  - Community lots change: restaurant opens, gym gets renovated
  - Seasonal decorations appear on NPC lots automatically
  - Newspaper (phone notification): daily digest of neighborhood events
  - Sims age across the neighborhood: children grow up together
  - If a sim dies, their house may be put up for sale (new NPC moves in)

- [ ] **33.5** Implement rumor and gossip system
  - Gossip spreads between sims who talk: "Did you hear about X?"
  - Gossip topics: romance, career events, fights, embarrassing moments
  - Gossip affects reputation: sims talked about negatively may have social penalties
  - "Spread Rumor" mean interaction: can damage another sim's reputation
  - Reputation system: how the neighborhood views a sim (good/bad/neutral)
  - Reputation affects: job opportunities, romantic prospects, party invitations

- [ ] **33.6** Implement household switching
  - Player can switch active household in neighborhood view
  - Switching households: "Manage Worlds" menu from main menu
  - Previously played households retain all progress
  - Option: "Leave household as-is" (frozen in time) or "Let story progression run"
  - Switching back to a household: see what happened while away (notifications)
  - Maximum number of active households (configurable, default: 5)

## Phase 34: Photography & Media System

- [ ] **34.1** Implement camera object and photography
  - Camera object: phone camera (always available) or dedicated camera (buyable)
  - "Take Photo" interaction: enters photo mode (freezes game, camera view)
  - Photo mode: pan camera, zoom, frame shot
  - Press shutter to capture screenshot as an in-game photo item
  - Photo quality: depends on photography skill and camera quality
  - Photos stored in sim's personal inventory as items

- [ ] **34.2** Implement photography skill
  - Photography skill: levels 1-10
  - Higher skill = better photo quality, more photo options (filters, poses)
  - Skill unlocks: Level 3: landscape mode, Level 5: portrait mode, Level 8: filters
  - Photography skill gained by taking photos (XP per photo)
  - "Practice Photography" whim: sim wants to take N photos

- [ ] **34.3** Implement photo album and display
  - `PhotoAlbum` component: collection of photo items with timestamps and captions
  - Photo album UI: browse photos, add captions, delete photos
  - Display photos on walls: "Frame Photo" interaction → place on wall
  - Photo frames: small, medium, large (different prices)
  - Photo collage: multiple photos on one wall surface
  - "View Photos" interaction: sim looks at wall photos, gets nostalgic moodlet

- [ ] **34.4** Implement TV and media system
  - TV object with channels: News, Cooking, Comedy, Drama, Sports, Horror, Kids, Music
  - "Watch TV" interaction: sim watches, gains fun need
  - TV skill shows: "Watch Cooking Show" (cooking XP), "Watch Workout" (fitness XP)
  - News channel: shows neighborhood events and gossip
  - Horror channel: gives "Scared" moodlet (or "Excited" for brave traits)
  - Romance channel: gives "Flirty" moodlet
  - Kids channel: only children/toddlers gain fun from it, adults get "Bored"

- [ ] **34.5** Implement computer and internet interactions
  - Computer: "Browse Web" (fun), "Play Video Game" (fun, varies by game)
  - "Stream Video" (fun), "Social Media" (social need, post updates)
  - "Program" (programming/logic skill), "Write Book" (creativity skill)
  - "Work from Home" (career), "Find Job" (career), "Order Items" (buy mode)
  - "Research" (logic skill, various topics)
  - Computer games: different genres, each with fun value and skill bonus

- [ ] **34.6** Implement music and stereo system
  - Stereo object: play music in room
  - "Listen to Music" interaction: fun need, mood depends on music type
  - Music genres: Pop, Rock, Classical, Jazz, Electronic, Country, Hip Hop
  - "Dance" interaction: sim dances near stereo, fun + fitness XP
  - "Dance Together" social interaction: two or more sims dance
  - Stereos disturb sleeping sims if in same room (autonomous "Turn Off" interaction)
  - Portable speaker: smaller stereo, can be placed anywhere

## Phase 35: Home Security & Maintenance

- [ ] **35.1** Implement burglary system
  - Burglar NPC: spawns at night on lots with low security
  - Burglar steals valuable objects and leaves
  - Security objects reduce burglary chance: alarm system (80% reduction), guard dog (60%), deadbolt (30%)
  - "Call Police" interaction: sim calls police, burglar may be caught
  - Burglar caught: stolen items returned, burglar goes to jail (off-screen)
  - Burglar escapes: household loses stolen items, gets "Violated" moodlet
  - Burglary notification wakes all sims in household

- [ ] **35.2** Implement fire alarm and safety system
  - Fire alarm object: automatically detects fire, sounds alarm, calls fire department
  - Without fire alarm: sims must manually call fire department
  - Fire extinguisher: "Extinguish Fire" interaction, faster than calling department
  - Smoke alarm: beeps loudly when smoke detected (early warning)
  - "Install Alarm" interaction on fire alarm and burglar alarm
  - Alarms require maintenance: battery check every 30 in-game days

- [ ] **35.3** Implement home maintenance and decay
  - Objects decay over time: cleanliness decreases, condition decreases
  - Dirty objects: "Clean" interaction (hygiene need for sim, object cleanliness restored)
  - Broken objects: "Repair" interaction (Handiness skill), or "Call Repair Service" (costs money)
  - Pipes can leak: puddle appears on floor, "Fix Pipe" interaction
  - Appliances break: fridge stops cooling (food spoils), TV won't turn on
  - Maintenance moodlet: "Dirty House" if too many uncleaned objects nearby

- [ ] **35.4** Implement pest control
  - Roaches spawn in dirty kitchens (low cleanliness score)
  - "Spray for Bugs" interaction on roaches
  - Roach moodlet: "Grossed Out" (negative)
  - Mice spawn in very dirty houses
  - "Call Exterminator" interaction on phone
  - Clean houses never get pests
  - Trash accumulation: "Take Out Trash" interaction prevents pests

- [ ] **35.5** Implement yard and outdoor maintenance
  - Lawn grows over time (visual change: grass gets longer)
  - "Mow Lawn" interaction: sim mows lawn, yard looks neat
  - Overgrown lawn moodlet: "Unkempt Yard" (slight negative)
  - Neat yards: "Well-Kept Yard" moodlet (slight positive)
  - Garden plants need watering and weeding (gardening system)
  - "Rake Leaves" interaction in fall: fun for Neat sims, chore for Lazy sims
  - "Shovel Snow" interaction in winter: clears walkways, fitness XP

- [ ] **35.6** Implement mail and delivery system
  - Mailbox object on lot edge
  - Mail arrives daily: bills, love letters, junk mail, career bonuses
  - Bills: weekly, based on lot value and utilities usage
  - "Check Mail" interaction: sim walks to mailbox, retrieves mail
  - Unpaid bills: warning after 1 day, repo after 3 days
  - Package delivery: ordered items appear at front door
  - Gift receiving: sims can receive gifts from other sims in mail

## Phase 36: Clothing & Outfit System

- [ ] **36.1** Implement outfit categories and slots
  - `OutfitCategory` enum: Everyday, Formal, Sleepwear, Athletic, Swimwear, Party, Outerwear, Career
  - `OutfitSlot` struct: top, bottom, shoes, accessories (hat, glasses, jewelry)
  - Each sim has 5 outfit slots per category (can cycle through with "Change Outfit")
  - Default outfits generated on sim creation based on style preference
  - Outfit affects: mood (uncomfortable in wrong outfit), need decay (athletic outfit slows energy decay during exercise)

- [ ] **36.2** Implement clothing catalog and shopping
  - Clothing catalog in buy mode → Fashion category
  - Clothing items: tops, bottoms, dresses, shoes, hats, accessories
  - Each item has: name, price, style tags (casual, formal, athletic, etc.), color
  - Generate clothing textures via MCP image gen (different styles per category)
  - "Try On" interaction: preview clothing on sim before purchase
  - Clothing items stored in sim inventory, can be sold back (50% value)

- [ ] **36.3** Implement outfit changing system
  - "Change Outfit" interaction: opens outfit category selector
  - Sims auto-change for situations: sleepwear at bedtime, athletic for exercise, formal for parties
  - Career outfit: auto-equipped during work hours
  - Outerwear: auto-equipped in cold weather
  - Swimwear: auto-equipped when approaching pool
  - Outfit change animation: sim spins, outfit swaps (visual change only, no mesh swap needed)

- [ ] **36.4** Implement style and fashion system
  - `StylePreference` component on sim: preferred colors, preferred tags
  - Sims in preferred outfit style get "Stylish" moodlet
  - Sims in wrong category outfit get "Uncomfortable" moodlet (sleepwear in public)
  - "Compliment Outfit" social interaction: positive relationship boost, moodlet for recipient
  - "Criticize Outfit" mean interaction: negative relationship, "Embarrassed" moodlet
  - Fashion skill: higher skill = better "Stylish" moodlet from self-outfits

- [ ] **36.5** Implement washing and laundry
  - Washing machine and dryer objects (buyable)
  - "Wash Clothes" interaction: loads washing machine, timer, move to dryer
  - Dirty clothes pile: appears after multiple outfit changes without washing
  - Dirty clothes moodlet: "Smelly" (hygiene need drops)
  - Laundromat: community lot with washing machines (for households without one)
  - "Fold Laundry" interaction: neat sims enjoy this, sloppy sims hate it
  - Washing machine can break (handiness repair)

## Phase 37: Skill Deep Dive

- [ ] **37.1** Implement Cooking skill progression
  - Level 1: Can make snacks and cereal, high burn risk
  - Level 3: Can cook basic meals (mac and cheese, salad)
  - Level 5: Can cook intermediate meals (pasta, stir fry), lower burn risk
  - Level 7: Can cook gourmet meals (lobster, filet mignon)
  - Level 10: Can cook perfect quality meals, "Master Chef" moodlet
  - Skill XP: gained by cooking any meal, more XP for complex recipes

- [ ] **37.2** Implement Handiness skill progression
  - Level 1: Can repair simple objects (plunger for toilet)
  - Level 3: Can upgrade objects (add self-cleaning to toilet)
  - Level 5: Can repair electronics, lower electric shock risk
  - Level 7: Can craft furniture from raw materials
  - Level 10: Can upgrade any object, "Master Tinkerer" moodlet, repairs never fail
  - Upgrade types: "Self-Cleaning", "Instant" (faster), "Unbreakable", "Enhanced" (better need satisfaction)

- [ ] **37.3** Implement Charisma skill progression
  - Level 1: Basic social interactions
  - Level 3: "Enthuse About" interaction (stronger friendship gain)
  - Level 5: "Apologize" more effective, "Cheer Up" unlocks
  - Level 7: "Network" interaction (career performance boost)
  - Level 10: "Entrance" interaction (room-wide moodlet), "Legendary" social moodlet
  - Skill XP: gained by successful social interactions, practicing speech in mirror

- [ ] **37.4** Implement Fitness skill progression
  - Level 1: Can jog, use treadmill
  - Level 3: Unlock "Push Limits" interaction (faster fitness XP, more energy drain)
  - Level 5: Unlock "Work Out" on all equipment, energy drain reduced
  - Level 7: Unlock "Exercise Demo" (teach others fitness), visible muscle increase
  - Level 10: "Fit" moodlet permanent, "Never Tired" while exercising
  - Visual change: sim body shape becomes more toned/muscular at higher levels

- [ ] **37.5** Implement Logic and Programming skill progression
  - Logic: gained by chess, programming, research
  - Logic Level 1-3: "Play Chess" (slow XP), "Browse Research" on computer
  - Logic Level 5: "Solve Problem" interaction (career boost)
  - Logic Level 7: "Mentor" interaction (teach others)
  - Logic Level 10: "Big Brain" moodlet, rocket science unlocks (future)
  - Programming: sub-skill of Logic, gained by coding on computer
  - Programming Level 5: "Freelance Program" interaction (earn money)
  - Programming Level 10: "Hack" interaction (various targets, earn money or info)

- [ ] **37.6** Implement Creativity and related sub-skills
  - Creativity: gained by painting, playing music, writing
  - Painting sub-skill: Level 1 (stick figures) → Level 10 (masterpieces)
  - Painting quality: directly tied to painting skill level
  - Paintings can be sold: §10 (level 1) → §5000 (level 10 masterpiece)
  - Music sub-skills: Guitar, Piano, Violin (separate instruments, shared creativity XP)
  - Music Level 5: "Write Song" interaction
  - Music Level 10: "Perform Concert" interaction (large social/fun event)
  - Writing sub-skill: Level 1 (short stories) → Level 10 (novels)
  - Written works earn royalties: passive income per in-game day

- [ ] **37.7** Implement Gardening skill progression
  - Level 1: Can plant and water basic crops (tomato, carrot)
  - Level 3: Unlock seasonal plants, faster growth
  - Level 5: Can graft plants (combine two plant types)
  - Level 7: Can evolve plants (increase quality tier)
  - Level 10: "Garden Guru" moodlet, plants evolve faster, never get diseased
  - Plant quality tiers: Normal → Nice → Very Nice → Excellent → Outstanding → Perfect

- [ ] **37.8** Implement Fishing skill progression
  - Level 1: Can fish at fishing spots, catch common fish
  - Level 3: Unlock bait fishing (better catch rate)
  - Level 5: Can catch rare fish, identify fish types
  - Level 7: Can catch legendary fish (very rare, very valuable)
  - Level 10: "Master Angler" moodlet, always catch something
  - Fishing spots: pond, river, ocean (different fish per location)
  - Fish can be mounted, cooked, sold, or kept in bowl

- [ ] **37.9** Implement Mixology skill progression
  - Level 1: Can make basic drinks (water, juice)
  - Level 3: Can make bar drinks (beer, wine, cocktails)
  - Level 5: Can make quality drinks, unlock "Flair Bartending" (fun for watchers)
  - Level 7: Can make mood-enhancing drinks (energy drink, romantic cocktail, calming tea)
  - Level 10: "Mixologist" moodlet, drinks never fail, can create custom drink recipes
  - Mixology gained at bar objects, career advancement for Culinary track

- [ ] **37.10** Implement skill UI and progression feedback
  - Skill bar in sim info panel: shows current level, XP progress to next level
  - Skill level-up notification: "SimName has reached Cooking Level 5!"
  - Skill unlock notification: "New unlock: Sim can now cook gourmet meals!"
  - Skill journal: list of all skills, current levels, total hours spent
  - Aspiration milestone tracking: "Reach Cooking Level 5" auto-completes when achieved
  - Skill decay: skills don't decay, but neglect means no progress toward next level

## Phase 38: Object State Machines & Degradation

- [ ] **38.1** Implement object state machine framework
  - `ObjectState` component: current state, available transitions, state timer
  - States: Clean, Dirty, Filthy, Broken, Destroyed
  - State transitions triggered by: time, use, sim interactions, environmental factors
  - Each state has visual representation (dirt overlay, cracks, sparks)
  - State affects need satisfaction: dirty toilet gives less hygiene, broken bed gives less comfort
  - States persist through save/load

- [ ] **38.2** Implement object cleanliness and cleaning
  - Objects get dirty over time (configurable rate per object type)
  - Kitchen objects get dirty faster (cooking spills)
  - Bathroom objects get dirty from use
  - "Clean" interaction: sim cleans object, restores to Clean state
  - Neat sims autonomously clean, Sloppy sims rarely clean
  - "Hire Maid" service: NPC cleans all dirty objects on lot daily (costs §100/day)
  - Maid NPC: arrives in the morning, cleans everything, leaves when done

- [ ] **38.3** Implement object breakage and repair
  - Objects break based on: use count, quality tier, Handiness level of last repair
  - Low-quality items break more often (budget fridge vs premium)
  - Electronics break from power surges, water damage, or overuse
  - Plumbing breaks from use (toilet, sink, shower)
  - "Repair" interaction: Handiness skill level determines success rate and speed
  - Failed repair: object gets worse, sim gets "Shocked" moodlet (electronics)
  - "Call Repair Service": costs §50-200, guaranteed fix, takes 1-2 hours
  - Broken objects show: sparks (electronics), water puddle (plumbing), wobble (furniture)

- [ ] **38.4** Implement object quality tiers
  - Quality tiers: Budget (cheap, breaks often), Standard (normal), Premium (rarely breaks), Luxury (almost never breaks)
  - Quality affects: durability, need satisfaction, moodlet, price
  - Budget: §100-300, Standard: §300-1000, Premium: §1000-3000, Luxury: §3000+
  - Premium and Luxury items give "Nicely Decorated" moodlet in room
  - Visual difference: budget items are smaller/duller, luxury items are larger/shinier
  - Generate texture variants per quality tier via MCP image gen

- [ ] **38.5** Implement object use counting and wear
  - `UseCounter` component: tracks number of times object has been used
  - Objects degrade after N uses: bed becomes less comfortable, TV develops static
  - "Well-Used" state: object still works but at reduced effectiveness (80% of original)
  - "Worn Out" state: 50% effectiveness, visual wear (scratches, fading)
  - Use counter displayed in buy mode tooltip (optional)
  - "Refurbish" interaction: restores worn object to full effectiveness (costs materials)

- [ ] **38.6** Implement environmental effects on objects
  - Rain: outdoor objects get "Wet" state, can rust (metal) or warp (wood) over time
  - Fire: objects near fire get "Scorched" state, may break
  - Water: electronics near water puddles get "Shorted" state
  - Sun: outdoor furniture fades over time (visual only)
  - Temperature: extreme cold can crack pipes, extreme heat can wilt plants
  - Protect objects: "Cover" interaction for outdoor furniture (tarp visual)

## Phase 39: Tutorial & Onboarding System

- [ ] **39.1** Implement tutorial framework
  - `TutorialSystem`: manages tutorial state, steps, and triggers
  - `TutorialStep` struct: id, text, trigger_condition, highlight_element, completion_condition
  - Tutorial state saved to player profile (never repeats for same player)
  - Tutorial can be re-enabled from settings
  - Tutorial steps only trigger when relevant UI is visible
  - Tutorial mode: reduced autonomy, paused time during some steps

- [ ] **39.2** Implement tutorial: first-time setup
  - Step 1: Welcome screen — "Welcome to Just Life! Let's learn the basics."
  - Step 2: Camera controls — "Move the camera with WASD or middle-mouse drag"
  - Step 3: Zoom — "Scroll to zoom in and out"
  - Step 4: Rotate — "Press Q/E to rotate the camera"
  - Step 5: Select a sim — "Click on a sim to select them"
  - Step 6: Needs panel — "This shows your sim's needs. Keep them satisfied!"
  - Step 7: Time controls — "Use 1/2/3 to change game speed"

- [ ] **39.3** Implement tutorial: basic gameplay
  - Step 8: Queue an interaction — "Click on the fridge and choose 'Get Snack'"
  - Step 9: Watch the sim — "Your sim will walk to the fridge and eat. Notice the hunger bar filling."
  - Step 10: Check needs — "Your sim's needs are decaying. Let's address the lowest one."
  - Step 11: Queue multiple — "You can queue multiple interactions. Try clicking several objects."
  - Step 12: Cancel queue — "Right-click a queued interaction to cancel it."

- [ ] **39.4** Implement tutorial: build mode
  - Step 13: Enter build mode — "Press B to enter build mode. This pauses your sims."
  - Step 14: Place a wall — "Click and drag to place walls. Rooms need 4 walls to be enclosed."
  - Step 15: Place a door — "Select the door tool and click on a wall segment."
  - Step 16: Buy furniture — "Switch to buy mode. Let's buy a bed and place it."
  - Step 17: Return to live mode — "Press B again to return to your sims."

- [ ] **39.5** Implement tutorial: social
  - Step 18: Meet a neighbor — "A neighbor is visiting! Click on them to interact."
  - Step 19: Social interaction — "Right-click the neighbor to see available interactions."
  - Step 20: Build friendship — "Choose 'Friendly' then 'Chat' to start a conversation."

- [ ] **39.6** Implement tutorial: career
  - Step 21: Find a job — "Click on the computer and select 'Find Job'"
  - Step 22: Go to work — "Your sim will leave for work at the scheduled time."
  - Step 23: Career panel — "Check the career panel to see your job performance."

- [ ] **39.7** Implement contextual hints system
  - Hints appear when a sim's need drops below 30% for the first time
  - "Your sim is very hungry! Click on a fridge to get food."
  - "Your sim is tired. Send them to bed before they pass out!"
  - "Your sim is dirty. A shower will help."
  - "Bills are due! Check the mailbox to pay them."
  - Hints only show once per session per hint type
  - Hints can be disabled in settings
  - Hint system tracks which hints have been shown

## Phase 40: Save/Load & State Management Deep Dive

- [ ] **40.1** Implement comprehensive save serialization
  - Serialize all Sim components: Needs, Moodlets, Traits, Appearance, Inventory, Skills, Career, Relationships
  - Serialize all World state: Walls, Doors, Windows, PlacedObjects, Rooms, Lot boundaries
  - Serialize all Resources: GameTime, GameSpeed, HouseholdFunds, Neighborhood state
  - Serialize all Relationships: friendship, romance, sentiment, known traits
  - Serialize all Events: pending career events, scheduled social events
  - Handle entity references correctly (Entity IDs → save IDs → Entity IDs on load)

- [ ] **40.2** Implement save file format and versioning
  - Save format: RON (Rusty Object Notation) for human-readable, compact binary for production
  - Save header: version number, game version, timestamp, household name, play time
  - Save data: compressed with gzip for file size reduction
  - Version migration: on load, if save version < current version, run migration functions
  - Migration functions: add missing fields with defaults, rename moved fields, convert old formats
  - Backward compatibility: game can always load saves from 1 major version back

- [ ] **40.3** Implement auto-save system
  - Auto-save triggers every 10 in-game minutes
  - Auto-save rotates: 3 auto-save slots (auto_1.ron, auto_2.ron, auto_3.ron)
  - Auto-save is asynchronous: doesn't freeze the game
  - Auto-save only saves if game state has changed since last save
  - Manual save: 3 manual slots + quick save (F5) + quick load (F9)
  - Save indicator: small spinning icon in corner while saving

- [ ] **40.4** Implement save/load UI
  - Save menu: list of save slots with thumbnail, household name, play time, save date
  - Load menu: same list, click to load
  - "New Save" button: creates new save slot
  - "Overwrite Save" button: saves to existing slot (with confirmation)
  - "Delete Save" button: removes save slot (with confirmation)
  - Save slot thumbnails: capture screenshot at save time
  - Load screen: progress bar with loading tips

- [ ] **40.5** Implement browser-specific save (WASM)
  - Use localStorage for save data on WASM (IndexedDB for larger saves)
  - IndexedDB wrapper: async save/load with quota management
  - Browser quota: warn player when storage is nearly full
  - Export save: download save file as .ron to local filesystem
  - Import save: upload .ron file from local filesystem
  - Cloud save: future integration (not implemented yet, placeholder)

- [ ] **40.6** Implement state snapshot and rollback
  - State snapshot: capture full game state at a moment (for debugging)
  - Rollback: restore game to a previous snapshot (limited to last 5 minutes)
  - Snapshot compression: store only deltas between snapshots
  - Snapshot triggered on: entering build mode, before dangerous actions
  - Debug command: `debug.snapshot` to create manual snapshot
  - Debug command: `debug.rollback <n>` to rollback N snapshots

## Phase 41: Performance & Profiling

- [ ] **41.1** Implement performance monitoring system
  - `PerformanceMonitor` resource: tracks FPS, frame time, memory usage
  - Performance overlay (toggle with F3): shows FPS, entity count, draw calls, system times
  - System timing: measure each Bevy system's execution time
  - Performance warnings: log when FPS drops below 30, when frame time exceeds budget
  - Performance data saved to file for analysis
  - Performance dashboard in debug console: `debug.perf` shows top 10 slowest systems

- [ ] **41.2** Optimize rendering pipeline
  - Instanced rendering: batch-render identical objects (chairs, trees, tiles)
  - Frustum culling: don't render objects outside camera view
  - Occlusion culling: don't render objects behind walls (if wall cutaway is on)
  - Texture atlas: combine small textures into atlas sheets to reduce draw calls
  - LOD system: simplify meshes at distance (low-poly models for distant objects)
  - Shadow optimization: shadow map resolution scaling, cascade shadow maps
  - Target: <100 draw calls for typical lot, <200 for neighborhood view

- [ ] **41.3** Optimize simulation systems
  - Spatial hashing: grid-based spatial index for proximity queries (O(1) lookups)
  - AI scheduling: only run autonomy for sims within camera range + 1 screen buffer
  - AI throttling: spread autonomy evaluations across 60 frames (1 sim per frame)
  - Pathfinding cache: store common paths, invalidate only on build mode changes
  - Need decay batching: update all sims' needs in a single parallel system
  - Relationship queries: use HashMap for O(1) relationship lookups between specific sims

- [ ] **41.4** Optimize WASM build
  - Profile WASM binary size with `twiggy` (Rust WASM analyzer)
  - Strip debug info in release builds
  - Run `wasm-opt -Oz` on output binary
  - Enable LTO (Link-Time Optimization) for WASM target
  - Tree-shake unused Bevy features (3D only, no 2D sprite features)
  - Compress assets: use KTX2/Basis Universal for GPU textures
  - Target WASM binary size: <10MB (compressed)
  - Target load time: <5 seconds on broadband connection

- [ ] **41.5** Optimize memory usage
  - Entity archetype optimization: group entities with same components together
  - Asset streaming: load assets on-demand (don't load all textures at startup)
  - Texture compression: use compressed texture formats for GPU
  - Sparse component storage: use sparse sets for rarely-used components
  - Object pooling: reuse entity allocations for frequently created/destroyed objects (particles, sounds)
  - Memory budget: <500MB total for typical gameplay on WASM

- [ ] **41.6** Implement adaptive quality system
  - Auto-detect performance: if FPS < 30, reduce quality settings
  - Quality levels: Low, Medium, High, Ultra
  - Low: no shadows, 30fps target, compressed textures, reduced draw distance
  - Medium: basic shadows, 45fps target, medium textures
  - High: full shadows, 60fps target, full textures, full draw distance
  - Ultra: enhanced shadows, anti-aliasing, post-processing effects
  - Adaptive mode: automatically adjusts quality to maintain target FPS
  - Player override: manual quality setting in options menu

## Phase 42: Localization & Internationalization Implementation

- [ ] **42.1** Implement locale loading system
  - Locale files in `assets/locales/<language_code>.ron`
  - Supported languages: English (en), Spanish (es), French (fr), German (de), Italian (it), Portuguese (pt), Japanese (ja), Korean (ko), Chinese Simplified (zh-CN), Russian (ru)
  - Default locale: English (en)
  - Fallback chain: requested locale → English → key name
  - Locale selection in options menu
  - Locale loaded at startup, can be changed without restart (hot swap)

- [ ] **42.2** Implement text rendering with Unicode
  - Bevy text rendering with font fallback for CJK characters
  - Include fonts: Latin, CJK (Japanese/Korean/Chinese), Cyrillic
  - Font fallback: if character not in primary font, check fallback fonts
  - Text layout: handle RTL (right-to-left) languages (Arabic, Hebrew)
  - Text wrapping: wrap long strings based on UI container width
  - Dynamic font atlas: generate font atlas at runtime for needed characters

- [ ] **42.3** Implement locale key system
  - All UI strings reference locale keys, never hardcoded text
  - Key format: `<scope>.<category>.<item>` (e.g., `ui.needs.hunger.name`, `objects.bed.sleep`)
  - Locale macro: `t!("ui.needs.hunger.name")` → resolves to "Hunger" (or localized equivalent)
  - Plural handling: `t!("ui.time.hours", count = hours)` → "1 hour" vs "5 hours"
  - Gender handling: some languages need gender-specific forms (e.g., Spanish adjectives)
  - Context variants: same key can have different translations based on context

- [ ] **42.4** Implement number and date formatting
  - Currency formatting: "§1,000" (US), "§1.000" (DE), "§1 000" (FR)
  - Date formatting: "Day 1, Season 1, Year 1" (in-game dates, locale-agnostic)
  - Number formatting: comma vs period for thousands separator
  - Percentage formatting: "50%" (all locales)
  - Time formatting: "6:00 PM" vs "18:00" based on locale
  - All formatting uses locale-appropriate conventions

- [ ] **42.5** Create English locale file (base)
  - `assets/locales/en.ron`: complete English string database
  - Sections: ui (interface), objects (furniture/objects), interactions, traits, careers, needs, moodlets, relationships, build_mode, notifications, tutorial, settings, accessibility
  - Estimated size: 2000+ locale keys for complete coverage
  - Keys organized hierarchically by feature area
  - Include developer comments for context (e.g., // This appears in the tooltip when hovering a need bar)

- [ ] **42.6** Implement locale fallback and debugging
  - Missing key warning: log warning when locale key is not found
  - Visual indicator: show key name in red text if translation is missing
  - Locale completeness report: `debug.locale_report` command shows % translated per language
  - Locale validation tool: CLI command to check all locale files for missing keys, extra keys, type mismatches
  - Locale editor tool: future web-based tool for community translations

## Phase 43: Error Handling & Crash Recovery

- [ ] **43.1** Implement global error handling
  - Catch panics in Bevy systems: use `std::panic::catch_unwind` wrapper
  - Log all errors to file: `logs/just-life-error.log` with timestamps
  - Error categories: asset loading, serialization, game logic, rendering, input
  - Graceful degradation: if non-critical system fails, log error and continue
  - Critical error: show error dialog to user with option to report or continue
  - Never crash silently: all errors are surfaced to the user or logged

- [ ] **43.2** Implement asset loading error handling
  - Missing texture: show placeholder magenta-black checkerboard pattern
  - Missing mesh: show placeholder cube with "MISSING" label
  - Missing sound: silently skip, log warning
  - Missing locale key: show key name in UI, log warning
  - Missing data file: load defaults, show notification "Using default data"
  - Corrupted save file: show error message, offer to load last auto-save

- [ ] **43.3** Implement crash recovery system
  - On crash: save emergency snapshot of game state
  - On next launch: detect emergency save, offer to restore
  - Emergency save includes: all sim states, world state, last 1 minute of gameplay
  - Crash reporter: collect crash log, system info, offer to save to file
  - WASM crash: catch JavaScript errors, show in-game error overlay
  - Infinite loop detection: if a system runs >10x its normal time, log warning

- [ ] **43.4** Implement input validation
  - All user input sanitized before processing (names, custom text)
  - Name input: max 30 characters, no special characters, Unicode allowed
  - Numeric inputs: clamped to valid ranges (money: 0 to MAX, needs: 0-100)
  - Save file names: alphanumeric only, max 50 characters
  - Build mode: validate wall placement doesn't create impossible geometry
  - Invalid state recovery: if game state becomes invalid, reset to last valid state

- [ ] **43.5** Implement logging system
  - Log levels: Error, Warn, Info, Debug, Trace
  - Release builds: Error and Warn only
  - Dev builds: all levels
  - Log to file: `logs/just-life.log` with rotation (max 5 files, 10MB each)
  - Log to console: colored output for dev builds
  - Performance logging: log system execution times every 60 frames in dev mode
  - Network logging: N/A (no network in current version)

## Phase 44: Bevy Migration & Dependency Management

- [ ] **44.1** Pin and document Bevy version
  - Pin exact Bevy version in `Cargo.toml` (e.g., `bevy = "0.15.0"`)
  - Document Bevy version in AGENTS.md and README
  - Document all Bevy features used: 3D rendering, UI, audio, input, asset loading
  - Document any Bevy workarounds or patches in `docs/bevy-notes.md`
  - Create `docs/bevy-migration.md` for future Bevy version upgrades

- [ ] **44.2** Manage Rust dependencies
  - Review and minimize all Cargo dependencies
  - Document each dependency's purpose in `docs/dependencies.md`
  - Use only well-maintained crates with recent updates
  - Avoid duplicate functionality (e.g., don't use two serialization formats)
  - Audit dependencies for WASM compatibility: all deps must compile to wasm32-unknown-unknown
  - Run `cargo audit` regularly for security vulnerabilities
  - Lock `Cargo.lock` in version control

- [ ] **44.3** Implement Bevy ECS best practices
  - Use `Commands` for entity spawning/despawning (not direct World access in systems)
  - Use `Query` filters to reduce system iteration scope
  - Use `Res` and `ResMut` for singleton resources
  - Use `EventWriter`/`EventReader` for cross-system communication
  - Avoid `Query` with too many components (split into multiple queries)
  - Use system sets for ordering: `PreUpdate`, `Update`, `PostUpdate`
  - Use `Local` for system-local state (avoid global mutable state)
  - Profile with `tracing` spans around critical systems

- [ ] **44.4** Create Bevy system scheduling configuration
  - Define system execution order explicitly using system sets
  - `InputSet`: process all input before game logic
  - `GameLogicSet`: needs decay, AI decisions, interaction execution
  - `AnimationSet`: update animations after game logic
  - `PhysicsSet`: collision detection, movement resolution
  - `RenderSet`: camera updates, UI updates, visibility
  - Document all system sets and their ordering in `docs/system-architecture.md`
  - Ensure no system ordering ambiguities (Bevy will warn at startup)

- [ ] **44.5** Set up CI testing and linting
  - GitHub Actions: run `cargo clippy` on every PR
  - GitHub Actions: run `cargo fmt --check` on every PR
  - GitHub Actions: run `cargo test` on every PR
  - GitHub Actions: run `cargo build --target wasm32-unknown-unknown` on every PR
  - GitHub Actions: run WASM bundle size check (fail if > 15MB compressed)
  - Pre-commit hook: run `cargo fmt` and `cargo clippy` locally
  - Badge in README showing CI status

## Phase 45: CI/CD & Release Pipeline

- [ ] **45.1** Create GitHub Actions workflow for native builds
  - Build for Linux (x86_64) on every push
  - Build for macOS (x86_64 + ARM) on every push
  - Build for Windows (x86_64) on every push
  - Upload build artifacts to GitHub Releases on tag
  - Cache Cargo dependencies between builds
  - Build time target: <10 minutes for native

- [ ] **45.2** Create GitHub Actions workflow for WASM builds
  - Build for wasm32-unknown-unknown on every push
  - Run wasm-bindgen to generate JS glue
  - Run wasm-opt for size optimization
  - Bundle WASM + JS + HTML + assets into deployable package
  - Deploy to GitHub Pages on main branch push
  - Deploy to itch.io on release tags (using butler CLI)
  - WASM build time target: <15 minutes

- [ ] **45.3** Create release packaging workflow
  - On version tag (e.g., `v0.1.0`): create GitHub Release
  - Package native builds: tarball for Linux, .app for macOS, .zip for Windows
  - Package WASM build: .zip with index.html, JS, WASM, and assets
  - Generate release notes from commit history
  - Upload all packages to GitHub Release
  - Publish to itch.io (WASM version)
  - Publish to Steam (native builds) — future

- [ ] **45.4** Implement version management
  - Semantic versioning: MAJOR.MINOR.PATCH (e.g., 0.1.0)
  - Version stored in `Cargo.toml` and `src/core/version.rs`
  - Version displayed on main menu and in settings
  - Save file compatibility: save files include version number
  - Breaking changes increment MAJOR, new features increment MINOR, fixes increment PATCH
  - Chelog generation: `CHANGELOG.md` updated on each release

- [ ] **45.5** Create automated testing pipeline
  - Unit tests: `cargo test` runs all unit tests
  - Integration tests: `cargo test --test integration` runs game loop tests
  - Screenshot tests: build WASM, take screenshots of key UI screens, compare to baseline
  - Performance tests: benchmark critical systems (pathfinding, AI, rendering)
  - All tests must pass before merging PR
  - Test coverage report: track coverage with `cargo tarpaulin`

- [ ] **45.6** Create demo build configuration
  - Demo build: limited to 1 household, 2 sims max, 30 in-game days
  - Demo build: limited build mode (fewer objects in catalog)
  - Demo build: no save/load (session only)
  - Demo build configuration in `Cargo.toml` feature flags
  - `cargo build --features demo` produces demo binary
  - Demo watermark on screen: "JUST LIFE DEMO"
  - "Buy Full Version" button in demo main menu

## Phase 46: Community & Social Features (Async)

- [ ] **46.1** Implement gallery and sharing system
  - In-game gallery: browse community-created lots and households
  - Upload lot: serialize lot layout + objects to shareable format
  - Upload household: serialize sim data (appearance, traits, skills)
  - Gallery browser: filter by category, popularity, newest, most downloaded
  - Download lot/household: add to player's game
  - Gallery is local-first (no server required, shared via file export/import)
  - Future: online gallery integration (requires server infrastructure)

- [ ] **46.2** Implement lot export/import
  - Export lot: save lot layout, walls, objects, terrain to `.jl-lot` file
  - Import lot: load `.jl-lot` file and place in player's world
  - Lot preview: thumbnail + stats (cost, size, room count) before import
  - Lot validation: check for missing objects (catalog items not in player's game)
  - Lot placement: choose empty lot or replace existing lot
  - Share lots via file sharing (Discord, forums, etc.)

- [ ] **46.3** Implement household export/import
  - Export household: save sims, relationships, funds, career data to `.jl-household` file
  - Import household: load household and place in player's world
  - Household preview: show sim portraits, traits, relationships before import
  - Gallery integration: upload household to gallery, download others' households
  - Conflict resolution: handle trait conflicts, career conflicts on import
  - Merge option: add household to existing neighborhood or replace

- [ ] **46.4** Implement challenge and scenario system
  - Challenges: pre-defined scenarios with goals and constraints
  - Challenge examples: "Rags to Riches" (start with §0, earn §100,000), "Survival" (no electricity, no plumbing), "Speed Build" (build a house in 10 in-game minutes)
  - Challenge data format: RON file with start conditions, goals, time limits, constraints
  - Challenge progress tracking: percentage complete, time remaining
  - Challenge completion: notification, badge, aspiration points
  - Community challenges: share challenge files on gallery
  - Challenge leaderboard (local only, future: online)

- [ ] **46.5** Implement screenshot mode
  - Screenshot mode: pause game, free camera, no UI overlay
  - Camera controls in screenshot mode: pan, zoom, rotate, pitch
  - Filters: None, Warm, Cool, Vintage, B&W, Sepia, Dramatic
  - Depth of field: adjustable blur for background
  - Timestamp and sim name overlay (optional, toggle)
  - "Take Photo" saves screenshot to `screenshots/` folder
  - Screenshots can be shared on gallery
  - Photo resolution: configurable (720p, 1080p, 1440p, 4K)

- [ ] **46.6** Implement neighborhood sharing
  - Export entire neighborhood: all lots, households, relationships, world state
  - Import neighborhood: replace current world or merge into existing
  - Neighborhood preview: show overview map, lot count, sim count
  - Neighborhood validation: check for conflicts (duplicate sim IDs, missing lots)
  - Share neighborhoods via `.jl-neighborhood` file
  - Future: online neighborhood sharing (requires server)

## Phase 47: Mini-Games & Activities

- [ ] **47.1** Implement chess mini-game
  - Two sims can "Play Chess" at a chess table
  - Simplified chess: 4x4 board, random moves or strategic based on Logic skill
  - Higher Logic skill = better moves, higher win chance
  - Winning sim gets "Winner" moodlet (+focused), loser gets "Sore Loser" moodlet (+tense)
  - Both sims gain Logic skill XP during the game
  - Game duration: 30 in-game minutes
  - Observer sims can "Watch Chess" (fun moodlet)

- [ ] **47.2** Implement card game mini-game
  - Two sims can "Play Cards" at a card table
  - Simple card game: higher card wins (war variant)
  - Luck-based with small skill modifier (Charisma for bluffing)
  - "Winner" and "Loser" moodlets
  - Betting: sims can bet §10-§100 on the game
  - Card game unlocks at Charisma Level 3
  - Duration: 15 in-game minutes

- [ ] **47.3** implement darts mini-game
  - Two sims can "Play Darts" at a dartboard object
  - Darts mini-game: aim and throw, accuracy based on Fitness skill
  - Scoring: 301 rules (start at 301, count down to 0)
  - Higher Fitness = more accurate throws
  - "Winner" moodlet for winner, "Competitive" moodlet for both
  - Duration: 20 in-game minutes

- [ ] **47.4** Implement dancing mini-game
  - Sims can "Dance" near a stereo or at a nightclub
  - Simple rhythm game: arrows appear, press matching key in time
  - Success = fun moodlet, failure = "Off Beat" moodlet
  - Dancing skill: based on Creativity and Fun need
  - Group dance: multiple sims dance together, synchronized bonus moodlet
  - DJ booth at nightclub: sims can "Be DJ" (Creativity skill), affects dance quality
  - Dance competitions: "Dance Battle" interaction between two sims

- [ ] **47.5** Implement painting mini-game
  - Sims can "Paint" at an easel (Creativity skill)
  - Painting quality: based on Creativity level, mood, and focus
  - Painting styles unlock at skill levels: Abstract (1), Landscape (3), Portrait (5), Surreal (7), Masterwork (10)
  - Paintings can be: kept (decoration), sold (§10-§5000 based on skill and quality), gifted
  - "Paint from Reference": sim paints something they saw (landscape, still life)
  - Painting progress bar: shows completion percentage during painting
  - Completed paintings are inventory items with quality rating

- [ ] **47.6** Implement video game interaction (sim plays a game)
  - "Play Video Game" on computer or TV
  - Game-within-a-game: simple retro-style arcade screen (generated texture)
  - Fun need increases while playing
  - Gaming skill: tracked per sim, affects game performance (shown as score)
  - Multiplayer: two sims can "Play Video Game Together" (more fun)
  - Gaming tournaments: social event at community lot (future)
  - "Binge Gaming" moodlet: if played for >4 hours, "Screen Fatigue" uncomfortable moodlet

- [ ] **47.7** Implement exercise activities
  - Treadmill: "Run" (fitness XP, energy drain, hygiene drain), "Jog" (lighter workout)
  - Weight machine: "Work Out" (fitness XP, energy drain), "Lift Weights" (heavy, more XP)
  - Yoga mat: "Do Yoga" (fitness XP + focus moodlet, low energy drain)
  - Swimming pool: "Swim Laps" (fitness XP, fun, energy drain), "Play in Pool" (fun)
  - Jogging: "Go Jogging" (fitness XP, outdoor, energy drain), autonomous for Active trait
  - Exercise moodlet: "Good Workout" (+energized) after successful exercise session
  - Over-exertion: if energy < 20, "Sore" moodlet (+uncomfortable)

## Phase 48: Neighborhood & World Generation

- [ ] **48.1** Implement neighborhood terrain generation
  - Procedural terrain: gentle hills, flat areas for building, natural features
  - Terrain noise function: Perlin/simplex noise for natural elevation
  - Road network: main road through neighborhood, side streets connecting lots
  - Water features: pond, stream, or coastline at low elevation
  - Tree placement: procedural forest areas, scattered trees
  - Generate terrain textures via MCP image gen (grass, dirt, road, water)

- [ ] **48.2** Implement lot layout in neighborhood
  - Each lot has: position, size (width x depth), terrain flatness score
  - Lots are arranged along roads with setbacks
  - Empty lots: just grass, available for purchase
  - Pre-built lots: come with house and furniture (starter homes)
  - Community lots: pre-placed at neighborhood center
  - Lot cost based on size and location (waterfront premium, downtown premium)

- [ ] **48.3** Implement neighborhood road system
  - Roads connect all lots to each other
  - Roads are visual only (sims teleport between lots, no car driving)
  - Road rendering: flat grey surface with lane markings
  - Sidewalks along roads for sim walking (visual)
  - Crosswalks at intersections (visual)
  - Street lights along roads (functional: light at night)

- [ ] **48.4** Implement neighborhood decoration
  - Park benches, mailboxes, fire hydrants, trash cans along roads
  - Flower beds, hedges, and decorative plants
  - Street signs, neighborhood name sign
  - Bus stops (visual, future: functional fast travel)
  - Weather effects on neighborhood: snow accumulation, rain puddles, autumn leaves

- [ ] **48.5** Implement neighborhood NPC population
  - Initial NPC households: 5-10 pre-made households with diverse traits
  - NPC households have homes, careers, and daily routines
  - Townies: 10-20 NPCs without homes that wander community lots
  - NPC generation: new NPCs created when needed (career fill, social connections)
  - NPC appearance: randomize from appearance pool (varied skin tones, hair, clothing)
  - NPC names: generated from first/last name pools per locale

- [ ] **48.6** Implement neighborhood view mode
  - Zoom out from lot to see entire neighborhood
  - Click on any lot to see its name, owner, and sim portraits
  - Click occupied lot to switch household (if owned) or visit (if NPC)
  - Click empty lot to purchase and build
  - Neighborhood view shows: lot boundaries, roads, community lots, water features
  - Mini-map in corner shows neighborhood overview with player lot highlighted

- [ ] **48.7** Implement neighborhood story events
  - Random events: "New family moving in!", "Business opening downtown!", "Park renovation complete!"
  - Seasonal events: neighborhood barbecue (summer), ice skating (winter)
  - Relationship events: "Two townies started dating!", "A household had a baby!"
  - Economic events: "Property values rising!", "Local business closing!"
  - Events shown as notifications with small neighborhood map
  - Player can attend or ignore neighborhood events


## Phase 50: Launch Preparation & Final QA

- [ ] **50.1** Create final demo content
  - Pre-built starter house #1: "Cozy Cottage" (1 bedroom, bathroom, kitchen, living room) — §8,000
  - Pre-built starter house #2: "Family Home" (3 bedrooms, 2 bathrooms, kitchen, living, dining) — §18,000
  - Pre-built starter house #3: "Modern Loft" (studio apartment, open plan) — §12,000
  - Pre-made household #1: "The Johnsons" (2 parents, 1 teen, 1 child — Family-Oriented traits)
  - Pre-made household #2: "Solo Sim" (1 young adult — Ambitious, Creative traits)
  - Pre-made household #3: "The Roommates" (3 young adults — diverse traits, conflicts)
  - Pre-made household #4: "The Retiree" (1 elder — Wise, Romantic traits)
  - Pre-made household #5: "The Power Couple" (2 adults — Ambitious, Career-driven traits)
  - Community lot: "Central Park" (park with benches, playground, chess, grill)
  - Community lot: "The Local Bar" (bar, darts, music, seating)
  - Neighborhood: 10 lots total (5 empty, 3 starter homes, 2 community)

- [ ] **50.2** Create game intro and tutorial flow
  - Title screen animation: "Just Life" logo fades in, camera pans over neighborhood
  - New Game flow: select neighborhood → select lot or choose starter home → create sim or choose household
  - First-time tutorial: guided steps for camera, needs, interactions, build mode (see Phase 39)
  - Skip tutorial option for experienced players
  - Tutorial completion reward: §5,000 bonus and "Quick Learner" achievement

- [ ] **50.3** Comprehensive playtesting
  - Playtest scenario 1: Create a sim, get a job, survive 7 in-game days
  - Playtest scenario 2: Build a house from scratch, furnish it, move in a household
  - Playtest scenario 3: Play a family household for 14 in-game days (birth, aging, school)
  - Playtest scenario 4: Play a single sim focused on career and skills
  - Playtest scenario 5: Play a household with 6+ sims (multi-sim management stress test)
  - Playtest scenario 6: Build mode stress test (large house, many objects)
  - Playtest scenario 7: Social focus (make friends, date, marry, have baby)
  - Document all bugs found during playtesting

- [ ] **50.4** Final WASM optimization and testing
  - Run `twiggy` on WASM binary to find size optimizations
  - Strip all debug assertions in release build
  - Optimize asset loading: compress textures, lazy-load non-essential assets
  - Test on: Chrome, Firefox, Safari, Edge (latest versions)
  - Test on: desktop, tablet, mobile (responsive layout)
  - Test on: low-end device (4GB RAM, integrated GPU)
  - Benchmark: measure FPS, load time, memory usage on each platform
  - Target: 30+ FPS on mid-range hardware in WASM

- [ ] **50.5** Final asset generation
  - Generate all remaining textures via MCP image gen tool:
  - UI: main menu background, logo, buttons, panels, icons (needs, moods, objects)
  - Walls: 10 wallpaper styles, 5 exterior wall styles, 3 brick, 2 stone
  - Floors: 5 hardwood, 3 tile, 3 carpet, 2 concrete, 2 marble
  - Roofs: 3 shingle styles, 2 metal, 1 flat
  - Furniture textures: wood grain (light, medium, dark), fabric (10 colors), metal (3 types)
  - Sim textures: 6 skin tones, 5 hair colors, clothing sets per category
  - Environment: grass, dirt, water, road, sidewalk, sky
  - Verify all textures load correctly in WASM build
  - Optimize texture sizes: max 512x512 for objects, 1024x1024 for environment

- [ ] **50.6** Final documentation review
  - Review all `docs/` files for accuracy and completeness
  - Verify modding documentation matches actual game systems
  - Verify API reference matches actual code
  - Verify RON format docs match actual data files
  - Test all example mods from `docs/example-mods.md`
  - Update README.md with final build instructions and play instructions
  - Update AGENTS.md with final project operations (build, test, lint commands)

- [ ] **50.7** Final release build and packaging
  - Build release for all platforms: Linux, macOS, Windows, WASM
  - Run all tests: `cargo test`, `cargo clippy`, `cargo fmt --check`
  - Run WASM build and verify in browser with screenshot
  - Package release builds with assets, docs, and licenses
  - Create release notes from CHANGELOG.md
  - Tag release version in git (e.g., `v0.1.0`)
  - Upload release packages to GitHub Releases and itch.io
  - Deploy WASM build to GitHub Pages
  - Verify deployment works in browser

- [ ] **50.8** Post-launch support plan
  - Monitor GitHub Issues for bug reports
  - Create issue templates: Bug Report, Feature Request, Mod Bug
  - Set up community channels: Discord server, Reddit community
  - Plan first patch: bug fixes from launch feedback
  - Plan first content update: new career, new objects, new interactions
  - Document known launch issues in KNOWN_ISSUES.md
  - Set up automated crash reporting pipeline
  - Schedule regular playtesting sessions for future updates

---

## Notes

- Tasks marked with `[x]` are complete
- Tasks marked with `[ ]` are pending (OCLoop will execute these)
- Tasks marked with `[MANUAL]` require human intervention
- Tasks marked with `[BLOCKED: reason]` cannot proceed until blocker is resolved

**Key Architectural Decisions:**
- Bevy ECS architecture: all game objects are entities with components, systems process them
- WASM target: always test in browser, maintain WASM compatibility
- Procedural 3D primitives + generated textures: no need for external 3D model files
- MCP image gen tool: use for all texture generation (documented in `.loop-prompt.md`)
- RON format: used for all data files (catalog, careers, traits, locale)
- Grid-based: world uses 1x1 unit grid for build mode and pathfinding

OCLoop will:
1. Skip completed (`[x]`), manual (`[MANUAL]`), and blocked (`[BLOCKED]`) tasks
2. Pick one pending (`[ ]`) task at a time
3. Execute it in a fresh opencode session
4. Mark it complete and continue to the next task
5. Create `.loop-complete` when all automatable tasks are done