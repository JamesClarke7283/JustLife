//! Radial / pie interaction menu (Phase 8.1).
//!
//! Opening the menu lays interaction categories out in a ring around a centre
//! point. The cursor's direction from the centre selects a wedge; choosing a
//! category expands it into a sub-ring of concrete interactions (one level of
//! drill-down). Selection is by click or number key; Escape backs out or closes.
//!
//! Pointer-driven opening (click a sim/object) and a keyboard toggle both feed
//! the same [`PieMenuState`]; the keyboard path keeps the menu reachable in the
//! headless WASM harness where synthetic mouse events don't reach winit.

use bevy::prelude::*;

use crate::core::state::GameState;
use crate::interaction::InteractionCategory;
use crate::render::camera::IsometricCamera;
use crate::sim::SimName;
use crate::world::PlacedObject;
use crate::world::catalog::CatalogDatabase;
use crate::world::placed::ObjectGrid;
use crate::world::wall::snap_to_grid;
use crate::world::wall_tool::cursor_ground_xz;

/// Radius (px) of the category/interaction ring from the menu centre.
const RING_RADIUS: f32 = 120.0;
/// Size (px) of each wedge button.
const WEDGE_SIZE: f32 = 84.0;
/// Cursor must be at least this far (px) from centre to select a wedge.
const DEAD_ZONE: f32 = 18.0;

/// One selectable wedge in the ring.
#[derive(Clone, Debug, PartialEq)]
pub struct PieSegment {
    pub label: String,
    pub category: InteractionCategory,
}

/// The live pie-menu state (immediate-mode: re-rendered each frame while open).
#[derive(Resource, Default)]
pub struct PieMenuState {
    pub open: bool,
    /// Screen-space centre the ring is drawn around.
    pub center: Vec2,
    /// Wedges currently shown (categories at level 0, interactions at level 1).
    pub segments: Vec<PieSegment>,
    /// Index of the wedge under the cursor, if any.
    pub hovered: Option<usize>,
    /// 0 = category ring, 1 = expanded sub-interaction ring.
    pub level: u8,
    /// The sim/object the menu was opened on (the interaction's eventual target).
    pub target: Option<Entity>,
    /// Text shown in the centre hub (the target's name, or a heading).
    pub title: String,
    /// Whether the level-1 ring can back out to a level-0 category ring (sim
    /// menus) or selecting/Escape just closes (object menus, which are flat).
    pub allow_back: bool,
}

/// Marks the menu's UI root so it can be cleared and re-spawned each frame.
#[derive(Component)]
struct PieMenuRoot;

/// Top-level interaction categories shown when the menu opens.
pub fn category_segments() -> Vec<PieSegment> {
    use InteractionCategory::*;
    [
        ("Friendly", Friendly),
        ("Romantic", Romantic),
        ("Funny", Funny),
        ("Mean", Mean),
        ("Special", Special),
    ]
    .into_iter()
    .map(|(label, category)| PieSegment {
        label: label.to_string(),
        category,
    })
    .collect()
}

/// Concrete interactions for a category (the sub-ring after drilling in).
pub fn sub_segments(category: InteractionCategory) -> Vec<PieSegment> {
    use InteractionCategory::*;
    let labels: &[&str] = match category {
        Friendly => &["Chat", "Joke", "Compliment", "Hug", "Console"],
        Romantic => &["Flirt", "Compliment", "Hold Hands", "Kiss", "Propose"],
        Mean => &["Insult", "Argue", "Fight", "Slap", "Spread Rumor"],
        Funny => &["Tell Joke", "Funny Story", "Prank", "Silly Face"],
        Special => &["Teach", "Advise", "Ask for Loan", "Propose Activity"],
        Object => &["Use", "Examine"],
    };
    labels
        .iter()
        .map(|label| PieSegment {
            label: label.to_string(),
            category,
        })
        .collect()
}

/// Index of the wedge the cursor points at, or `None` inside the dead zone.
///
/// Wedge 0 is centred at the top (12 o'clock) and indices advance clockwise.
pub fn segment_index(center: Vec2, cursor: Vec2, n: usize) -> Option<usize> {
    if n == 0 {
        return None;
    }
    let d = cursor - center;
    if d.length() < DEAD_ZONE {
        return None;
    }
    let seg = std::f32::consts::TAU / n as f32;
    // atan2(dx, -dy): clockwise angle from straight up.
    let theta = d.x.atan2(-d.y).rem_euclid(std::f32::consts::TAU);
    Some((((theta + seg / 2.0) / seg).floor() as usize) % n)
}

/// Screen position for wedge `index`'s button centre.
pub fn segment_anchor(center: Vec2, index: usize, n: usize, radius: f32) -> Vec2 {
    let seg = std::f32::consts::TAU / n.max(1) as f32;
    let angle = index as f32 * seg;
    center + Vec2::new(angle.sin(), -angle.cos()) * radius
}

/// Themed colour for a category wedge.
fn category_color(category: InteractionCategory) -> Color {
    use InteractionCategory::*;
    match category {
        Friendly => Color::srgb(0.30, 0.72, 0.40),
        Romantic => Color::srgb(0.88, 0.36, 0.55),
        Funny => Color::srgb(0.95, 0.74, 0.25),
        Mean => Color::srgb(0.74, 0.26, 0.24),
        Special => Color::srgb(0.40, 0.52, 0.85),
        Object => Color::srgb(0.55, 0.55, 0.58),
    }
}

/// Open a social (category) menu at `center` for `target` with the given title.
fn open_menu(state: &mut PieMenuState, center: Vec2, target: Option<Entity>, title: String) {
    state.open = true;
    state.center = center;
    state.segments = category_segments();
    state.hovered = None;
    state.level = 0;
    state.target = target;
    state.title = title;
    state.allow_back = true;
}

/// Open a flat object menu at `center` showing the object's actions directly.
fn open_object_menu(
    state: &mut PieMenuState,
    center: Vec2,
    target: Entity,
    title: String,
    segments: Vec<PieSegment>,
) {
    state.open = true;
    state.center = center;
    state.segments = segments;
    state.hovered = None;
    state.level = 1; // flat: selecting an action is final
    state.target = Some(target);
    state.title = title;
    state.allow_back = false;
}

/// Object-action wedges from a catalog item's actions.
pub fn object_action_segments(actions: &[crate::world::catalog::ObjectAction]) -> Vec<PieSegment> {
    if actions.is_empty() {
        return vec![PieSegment {
            label: "Examine".to_string(),
            category: InteractionCategory::Object,
        }];
    }
    actions
        .iter()
        .map(|a| PieSegment {
            label: a.name.clone(),
            category: InteractionCategory::Object,
        })
        .collect()
}

/// Map number keys 1..=9 to a wedge index within range.
fn number_key_pick(keyboard: &ButtonInput<KeyCode>, n: usize) -> Option<usize> {
    const KEYS: [KeyCode; 9] = [
        KeyCode::Digit1,
        KeyCode::Digit2,
        KeyCode::Digit3,
        KeyCode::Digit4,
        KeyCode::Digit5,
        KeyCode::Digit6,
        KeyCode::Digit7,
        KeyCode::Digit8,
        KeyCode::Digit9,
    ];
    KEYS.iter().take(n).position(|k| keyboard.just_pressed(*k))
}

/// Drive the menu: toggle/open, track hover, drill into categories, select.
fn pie_menu_input(
    keyboard: Res<ButtonInput<KeyCode>>,
    mouse: Res<ButtonInput<MouseButton>>,
    windows: Query<&Window>,
    mut state: ResMut<PieMenuState>,
) {
    let Ok(window) = windows.get_single() else {
        return;
    };
    let cursor = window.cursor_position();

    // Q toggles a generic social menu at the cursor (right-click opens a
    // context menu on a specific target - see pie_menu_open_on_target).
    if keyboard.just_pressed(KeyCode::KeyQ) {
        if state.open {
            state.open = false;
        } else {
            let center = cursor.unwrap_or(Vec2::new(window.width(), window.height()) * 0.5);
            open_menu(&mut state, center, None, "Actions".to_string());
        }
        return;
    }

    if !state.open {
        return;
    }

    // Escape backs out of a sub-ring (sim menus) or closes.
    if keyboard.just_pressed(KeyCode::Escape) {
        if state.level == 1 && state.allow_back {
            state.segments = category_segments();
            state.hovered = None;
            state.level = 0;
        } else {
            state.open = false;
        }
        return;
    }

    // A click well outside the ring dismisses the menu.
    if mouse.just_pressed(MouseButton::Left)
        && let Some(c) = cursor
        && c.distance(state.center) > RING_RADIUS + WEDGE_SIZE
    {
        state.open = false;
        return;
    }

    // Hover follows the cursor direction from centre.
    if let Some(c) = cursor {
        state.hovered = segment_index(state.center, c, state.segments.len());
    }

    // Selection: click the hovered wedge, or press its number key.
    let pick = if mouse.just_pressed(MouseButton::Left) {
        state.hovered
    } else {
        number_key_pick(&keyboard, state.segments.len())
    };

    if let Some(idx) = pick
        && let Some(segment) = state.segments.get(idx).cloned()
    {
        if state.level == 0 {
            // Drill into the chosen category's sub-interactions.
            state.segments = sub_segments(segment.category);
            state.hovered = None;
            state.level = 1;
        } else {
            // A concrete interaction was chosen; close the menu.
            // (Enqueueing onto the target sim is wired up in Phase 8.4.)
            state.open = false;
        }
    }
}

/// Right-click a sim or object to open a context menu with its name and the
/// interactions available on it.
#[allow(clippy::too_many_arguments)]
fn pie_menu_open_on_target(
    mouse: Res<ButtonInput<MouseButton>>,
    windows: Query<&Window>,
    cameras: Query<(&Camera, &GlobalTransform), With<IsometricCamera>>,
    grid: Res<ObjectGrid>,
    catalog: Res<CatalogDatabase>,
    placed: Query<&PlacedObject>,
    sims: Query<(Entity, &Transform, &SimName)>,
    mut state: ResMut<PieMenuState>,
) {
    if state.open || !mouse.just_pressed(MouseButton::Right) {
        return;
    }
    let Ok(window) = windows.get_single() else {
        return;
    };
    let Some(cursor) = window.cursor_position() else {
        return;
    };
    let Some(ground) = cursor_ground_xz(&windows, &cameras) else {
        return;
    };
    let point = Vec3::new(ground.x, 0.0, ground.y);

    // Prefer a sim near the cursor -> social context menu.
    let mut nearest: Option<(f32, Entity, String)> = None;
    for (entity, transform, name) in &sims {
        let d = transform.translation.distance(point);
        if d < 1.4 && nearest.as_ref().is_none_or(|(bd, _, _)| d < *bd) {
            nearest = Some((d, entity, name.first.clone()));
        }
    }
    if let Some((_, entity, name)) = nearest {
        open_menu(&mut state, cursor, Some(entity), name);
        return;
    }

    // Otherwise an object under the cursor -> its actions.
    let cell = snap_to_grid(ground);
    let key = (cell.x as i32, cell.y as i32);
    if let Some(&entity) = grid.occupied.get(&key)
        && let Ok(obj) = placed.get(entity)
        && let Some(item) = catalog.get(&obj.catalog_id)
    {
        open_object_menu(
            &mut state,
            cursor,
            entity,
            item.name.clone(),
            object_action_segments(&item.actions),
        );
    }
}

/// Immediate-mode render: clear last frame's ring and rebuild it while open.
fn render_pie_menu(
    mut commands: Commands,
    state: Res<PieMenuState>,
    existing: Query<Entity, With<PieMenuRoot>>,
) {
    for entity in &existing {
        commands.entity(entity).despawn_recursive();
    }
    if !state.open {
        return;
    }

    let n = state.segments.len();
    let root = commands
        .spawn((
            NodeBundle {
                style: Style {
                    position_type: PositionType::Absolute,
                    left: Val::Px(0.0),
                    top: Val::Px(0.0),
                    width: Val::Percent(100.0),
                    height: Val::Percent(100.0),
                    ..default()
                },
                ..default()
            },
            PieMenuRoot,
            Name::new("Pie Menu"),
        ))
        .id();

    for (i, segment) in state.segments.iter().enumerate() {
        let anchor = segment_anchor(state.center, i, n, RING_RADIUS);
        let hovered = state.hovered == Some(i);
        let base = category_color(segment.category);
        let color = if hovered {
            base.lighter(0.18)
        } else {
            base.with_alpha(0.92)
        };
        let size = if hovered {
            WEDGE_SIZE + 10.0
        } else {
            WEDGE_SIZE
        };

        commands.entity(root).with_children(|parent| {
            parent
                .spawn(NodeBundle {
                    style: Style {
                        position_type: PositionType::Absolute,
                        left: Val::Px(anchor.x - size / 2.0),
                        top: Val::Px(anchor.y - size / 2.0),
                        width: Val::Px(size),
                        height: Val::Px(size),
                        align_items: AlignItems::Center,
                        justify_content: JustifyContent::Center,
                        padding: UiRect::all(Val::Px(4.0)),
                        border: UiRect::all(Val::Px(if hovered { 3.0 } else { 1.0 })),
                        ..default()
                    },
                    background_color: color.into(),
                    border_color: Color::srgba(1.0, 1.0, 1.0, 0.85).into(),
                    border_radius: BorderRadius::all(Val::Px(size / 2.0)),
                    ..default()
                })
                .with_children(|wedge| {
                    wedge.spawn(TextBundle::from_section(
                        format!("{}\n{}", i + 1, segment.label),
                        TextStyle {
                            font_size: 15.0,
                            color: Color::WHITE,
                            ..default()
                        },
                    ));
                });
        });
    }

    // Centre hub: shows the target's name (or a back hint inside a sub-ring).
    let label = if state.level == 1 && state.allow_back {
        "< back"
    } else {
        state.title.as_str()
    };
    commands.entity(root).with_children(|parent| {
        parent
            .spawn(NodeBundle {
                style: Style {
                    position_type: PositionType::Absolute,
                    left: Val::Px(state.center.x - 34.0),
                    top: Val::Px(state.center.y - 34.0),
                    width: Val::Px(68.0),
                    height: Val::Px(68.0),
                    align_items: AlignItems::Center,
                    justify_content: JustifyContent::Center,
                    ..default()
                },
                background_color: Color::srgba(0.12, 0.14, 0.18, 0.92).into(),
                border_radius: BorderRadius::all(Val::Px(34.0)),
                ..default()
            })
            .with_children(|hub| {
                hub.spawn(TextBundle::from_section(
                    label,
                    TextStyle {
                        font_size: 14.0,
                        color: Color::srgb(0.9, 0.92, 1.0),
                        ..default()
                    },
                ));
            });
    });
}

/// Registers the pie-menu resource and systems (live mode only).
pub struct PieMenuPlugin;

impl Plugin for PieMenuPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<PieMenuState>().add_systems(
            Update,
            (pie_menu_open_on_target, pie_menu_input, render_pie_menu)
                .chain()
                .run_if(in_state(GameState::LiveMode)),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const C: Vec2 = Vec2::new(500.0, 400.0);

    #[test]
    fn cursor_direction_maps_to_clockwise_wedges() {
        // 4 wedges: up=0, right=1, down=2, left=3.
        assert_eq!(segment_index(C, C + Vec2::new(0.0, -50.0), 4), Some(0));
        assert_eq!(segment_index(C, C + Vec2::new(50.0, 0.0), 4), Some(1));
        assert_eq!(segment_index(C, C + Vec2::new(0.0, 50.0), 4), Some(2));
        assert_eq!(segment_index(C, C + Vec2::new(-50.0, 0.0), 4), Some(3));
    }

    #[test]
    fn dead_zone_selects_nothing() {
        assert_eq!(segment_index(C, C, 5), None);
        assert_eq!(segment_index(C, C + Vec2::new(2.0, 2.0), 5), None);
    }

    #[test]
    fn anchors_ring_around_center() {
        let top = segment_anchor(C, 0, 4, 100.0);
        assert!((top - (C + Vec2::new(0.0, -100.0))).length() < 0.01);
        let right = segment_anchor(C, 1, 4, 100.0);
        assert!((right - (C + Vec2::new(100.0, 0.0))).length() < 0.01);
    }

    #[test]
    fn categories_and_subitems_are_populated() {
        assert_eq!(category_segments().len(), 5);
        assert!(!sub_segments(InteractionCategory::Friendly).is_empty());
        assert!(!sub_segments(InteractionCategory::Object).is_empty());
    }

    #[test]
    fn opening_resets_to_category_level() {
        let mut state = PieMenuState::default();
        open_menu(&mut state, C, None, "Alex".to_string());
        assert!(state.open);
        assert_eq!(state.level, 0);
        assert!(state.allow_back);
        assert_eq!(state.title, "Alex");
        assert_eq!(state.segments, category_segments());
    }

    #[test]
    fn object_menu_is_flat_and_lists_actions() {
        use crate::sim::needs::NeedType;
        use crate::world::catalog::ObjectAction;
        let actions = vec![
            ObjectAction {
                name: "Sleep".to_string(),
                need: NeedType::Energy,
                rate: 10.0,
            },
            ObjectAction {
                name: "Relax".to_string(),
                need: NeedType::Fun,
                rate: 3.0,
            },
        ];
        let segments = object_action_segments(&actions);
        assert_eq!(segments.len(), 2);
        assert_eq!(segments[0].label, "Sleep");
        // Objects with no actions still offer Examine.
        assert_eq!(object_action_segments(&[])[0].label, "Examine");
    }
}
