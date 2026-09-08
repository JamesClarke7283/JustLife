# Lifelet actor contract

`LifeActor` owns appearance, procedural poses, expressions, props, the selection sprout, speech bubbles, and original vocal chatter. The controller owns the actor's navigation root position and facing. Call `configure(profile)` after adding the actor to the tree, then `animate(delta, simulation_speed, moving, active_action_id)` each frame. Speed zero freezes poses and stops the voice. `voice_enabled = false` also stops any currently playing voice immediately.

Profile fields: `frame` 0/1, `hair` 0 crop / 1 bob / 2 curls, `outfit` 0 casual / 1 jacket / 2 cardigan, `body_scale` .85–1.15, `height_scale` .93–1.08, and hexadecimal `skin_color`, `hair_color`, `top_color`, `bottom_color`, `eye_color`, `shoe_color`. `low_detail: true` selects the live-play LOD. During asset review, `rig_preview: true` loads the staged `character_rig` assets. Outfit selection also works through `set_outfit(index)` without reloading the actor. It requires the newer wardrobe assets.

The actor discovers both retained accessory pivots and imported `Skeleton3D` joints. It supports Godot's numbered bone-name suffixes and converts poses through each bone's rest basis. Each instance duplicates its material overrides. Blink and smile morphs are initialized explicitly and driven across all matching face and eye meshes. A `Sit` corrective morph blends with seated leg poses to keep clothing smoother at the hips and knees.

Optional identity controls `face_round`, `jaw_strong`, `nose_wide`, and `eye_spacing` range from 0 to 1 and default to neutral 0. `set_face_feature(feature, value)` updates them immediately without reloading the model. The matching `Face_Round`, `Jaw_Strong`, `Nose_Wide`, and `Eye_Spacing` morphs are applied to every mesh that exposes them, keeping skin, eyes, lids, brows and lips aligned. These controls require the newer identity-enabled assets; older assets remain compatible.

The production surface-revision-2 models also expose independent `Hand_Grip_L`/`Hand_Grip_R` morphs and forearm-local grip anchors in exported extras. Activity poses blend these values, align the spoon with its grasp channel, and support the bowl from beneath its base. Old models fall back to their palm anchors. The combined model/actor checks and independent normal-speed contact review are recorded in `GRIP_REVIEW.md`.

## Furniture support

Call `set_activity_anchor(world_position, world_yaw, kind, action_id)` when the Lifelet reaches the activity. The last argument limits the anchor to that action. Pass an empty action ID to apply it to any active action. Call `clear_activity_anchor()` after completion, cancellation, or replacement. Walking ignores the anchor automatically.

| Kind | Position supplied by world | Orientation |
| --- | --- | --- |
| `standing` | Foot position on the floor or shower tray | Actor's forward is yaw's +Z |
| `seat` | Center of the cushion's top surface | Actor's forward is yaw's +Z |
| `bed` | Center of the mattress's top surface | Sleeping head points toward yaw's −Z |

The actor adjusts only `visual`, its animated child, accounting for height and body scaling. Root position and rotation remain unchanged. Selection, speech, and voice follow the posed body. `seat` plus `nap` produces a seated doze; `standing` plus `work`, `job`, or `study` keeps legs straight. Standing study holds a book. Bed and seat support settle within approximately .02 m after their short animation transition.

`interaction_offset` is an optional additional offset in the navigation root's local coordinates. `clear_activity_anchor()` also resets it. Avoid shifting the navigation root to compensate for poses.

## Verification

`tests/test_actor.gd` exercises both frames, imported bone naming, real wardrobe meshes, eye morph initialization, sleep expressions, rotated furniture anchors, body scaling, standing work, seated naps, pause, return to walking, and finite normalized rotations across nine activities. Run it in an isolated project with the character imports and without the editor MCP autoload.

## Cooking, eating, and transitions

Cooking carries an original glazed mixing bowl at the left palm and a wooden spoon at the right palm. A two-bone arm solve uses the imported shoulder/elbow rest offsets and measured palm locations. The bowl counter-rotates around its grip to remain level; the spoon points into the ingredients through the complete stirring cycle. Eating uses a small vegetable roll with a lift, bite hold, lowering motion, and resting interval. The food approaches the measured mouth point through the retained Head transform, including its authored scale.

Both new props remain children of the corresponding forearm. Their appearance blends over a short transition, while retained accessory pivots and skinned bones use matching quaternion interpolation. Changing an action resets its local motion cycle. Speed zero returns before changing the pose, prop visibility, expressions, speech timer, or transition clock, even if the controller supplies different paused action arguments. Audio still stops immediately.

`tests/test_actor_activities.gd` verifies both body frames at opposite scale limits, complete spoon cycles, measured bite contact, pause invariance, continuous return to walking, and unchanged seat/navigation support. The current standard v12 assets pass 250 checks; the existing actor suite passes 576. During the test, the spoon tip stays within .049 m of the bowl center (rim radius .130 m); food contact is within .021 m of the lip point during the bite hold. These are geometric checks, not a visual quality score.

Matched rendered captures are in `art/activity_review/`, with `before_*` and `after_*` front/side views. `tests/render_activity_gallery.gd` reproduces the after captures in an isolated imported project. Captures show active poses using normal released model paths. They do not replace the critic's live gameplay review. The current relaxed finger shape still limits how tightly fingers appear to wrap the utensil; a future authored hand grip morph can improve that without moving the prop anchors.

## Distinct age models and keyboard targets

`age_stage` selects the distinct `character_child`, `character_teen`, or `character_elder` GLB families, including both frames and LOD variants. Young adults and adults use the standard character family. These are separately sculpted assets; profile body/height sliders remain relative adjustments to the chosen model. The actor reads the imported Character node's `extras` dictionary for authored height, hip/knee heights, and palm/mouth contact locations. Adult assets retain compatible fallback landmarks.

`available_age_stages()` is a static list of verified age families whose four assets are available. `supports_age(stage)` is the instance equivalent for creator gating. `get_display_height()` includes the profile's relative height adjustment. `get_portrait_center()` returns the current head framing point in **actor-local coordinates**. `get_body_landmarks()` exposes authored/scaled height, scaled hip/knee heights, actual model age, and pivot-local contact anchors.

`set_activity_anchor(position, yaw, kind, action_id, details={})` accepts an optional fifth Dictionary. For desk actions, `details.hand_center` is the keyboard center in world coordinates, and `details.hand_spread` is half the hand separation in meters. The world supplies a forward seat position and a visible 18cm Blender booster for child desk actions. The actor preserves those supplied hip and navigation positions, leans from the supported hips, and solves an upward/outward elbow path. `desk_surface_y`, `desk_front_edge`, and `desk_forward` describe the actual desktop in world coordinates. Lean selection checks both complete limb segments with scaled skin/garment radii at the front edge; hand endpoint reach alone is insufficient for acceptance. Schooling uses typing for online classes and desk homework; standing bookshelf homework uses the reading pose.

For cooperative homework, the controller supplies `attention_target`, the partner's head framing point in world coordinates. The helper's open explaining hand rises toward the upper torso, then lowers while listening. The learner periodically looks toward the helper and reduces typing motion during that phase. Head turns are bounded, and both actors keep their actual desk/chair/standing anchors. `homework_wait` keeps an arrived learner seated with resting hands until the helper arrives. Pause freezes the gestures and attention clock. The accepted child/adult rendered sequence and its limits are recorded in `REVIEWS/iteration_10_homework.md`; other ages and body extremes are not implied by that focused visual acceptance.

## Birthday presentation

The `birthday` action holds the original `birthday_cake.glb`, leans toward its candles, hides the three named flame meshes after blowing, then puts the cake away for applause and a smile. Cake geometry remains attached to the hand; its pose, flame visibility, and transition clock freeze at speed zero. Original happy vocal chatter accompanies the celebration when sound is enabled. `tests/test_actor_birthday.gd` covers child, teen, and adult transitions and pause. Rendered references are in `art/age_activity_review/`.

The final pre-grip actor snapshot passes 984 checks: 134 age/model/furniture/contact checks, 576 existing rig checks, 250 activity checks, and 24 birthday checks. The visible open-hand grip limitation remains; these checks do not assign a visual quality score.


Desk clearance regression: `tests/test_actor_desk.gd` checks 9 independent child body/height combinations, both authored frames, four desk rotations, both full padded arm segments, keyboard contact over a typing cycle, exact supplied hip support, and paused transforms (288 checks). Actual cottage front/side rendering remains the independent visual acceptance gate.

Independent rendered correction review: 39 public-flow checks passed using the actual cottage. `art/age_activity_review/child_desk_clearance_side.png` and `_over_shoulder.png` show the arms above the desktop and the visible cushion supporting the seated body. The observed shoulders were 1.107m and elbows 1.136m above a desktop at 1.03m; both palms stayed within 1.1–4.1mm of the keyboard targets. The child remains slightly extended on this adult-sized desk.
