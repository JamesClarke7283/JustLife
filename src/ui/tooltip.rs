//! Tooltip system (Phase 10.10).
//!
//! Hovering a UI element (with a `Tooltip`) or a lot object/sim for 500ms shows
//! a small tooltip near the cursor. Object tooltips list name/price/needs/state;
//! sim tooltips show name/mood/action. (Pointer hover isn't deliverable by the
//! headless harness, so the dwell + content logic is unit-tested.)

use bevy::prelude::*;

use crate::core::state::GameState;
use crate::render::camera::IsometricCamera;
use crate::sim::moodlet::{ActiveMoodlets, Mood};
use crate::sim::{AnimationState, SimName};
use crate::world::PlacedObject;
use crate::world::catalog::{CatalogDatabase, ObjectAction};
use crate::world::placed::ObjectGrid;
use crate::world::wall::snap_to_grid;
use crate::world::wall_tool::cursor_ground_xz;

/// Hover dwell required before a tooltip appears.
const TOOLTIP_DELAY: f32 = 0.5;
/// Distance to consider a sim "under" the cursor.
const HOVER_RADIUS: f32 = 1.4;

/// Attach to any UI element to give it a hover tooltip.
#[derive(Component)]
pub struct Tooltip(pub String);

/// The currently-hovered tooltip text and how long it has been hovered.
#[derive(Resource, Default)]
struct TooltipState {
    text: Option<String>,
    dwell: f32,
}

/// The rendered tooltip node (immediate-mode).
#[derive(Component)]
struct TooltipNode;

/// Tooltip text for a placed object.
pub fn object_tooltip(name: &str, price: u32, actions: &[ObjectAction], condition: &str) -> String {
    let needs = if actions.is_empty() {
        "nothing".to_string()
    } else {
        actions
            .iter()
            .map(|a| format!("{:?}", a.need))
            .collect::<Vec<_>>()
            .join(", ")
    };
    format!("{name}\nPrice: ${price}\nSatisfies: {needs}\nCondition: {condition}")
}

/// Tooltip text for a sim.
pub fn sim_tooltip(name: &str, mood: Mood, action: AnimationState) -> String {
    format!("{name}\nMood: {mood:?}\nDoing: {action:?}")
}

/// Determine what (if anything) is hovered and accumulate dwell time.
#[allow(clippy::too_many_arguments)]
fn detect_tooltip(
    time: Res<Time>,
    windows: Query<&Window>,
    cameras: Query<(&Camera, &GlobalTransform), With<IsometricCamera>>,
    grid: Res<ObjectGrid>,
    catalog: Res<CatalogDatabase>,
    ui: Query<(&Interaction, &Tooltip)>,
    objects: Query<&PlacedObject>,
    sims: Query<(&Transform, &SimName, &AnimationState, &ActiveMoodlets)>,
    mut state: ResMut<TooltipState>,
) {
    // UI tooltips take priority over world hover.
    let mut hovered = ui
        .iter()
        .find(|(interaction, _)| **interaction == Interaction::Hovered)
        .map(|(_, tip)| tip.0.clone());

    if hovered.is_none()
        && let Some(ground) = cursor_ground_xz(&windows, &cameras)
    {
        let point = Vec3::new(ground.x, 0.0, ground.y);
        // A sim under the cursor?
        hovered = sims
            .iter()
            .find(|(t, ..)| t.translation.distance(point) < HOVER_RADIUS)
            .map(|(_, name, anim, moods)| sim_tooltip(&name.first, moods.dominant_mood(), *anim));
        // Otherwise an object?
        if hovered.is_none() {
            let cell = snap_to_grid(ground);
            if let Some(&entity) = grid.occupied.get(&(cell.x as i32, cell.y as i32))
                && let Ok(obj) = objects.get(entity)
                && let Some(item) = catalog.get(&obj.catalog_id)
            {
                hovered = Some(object_tooltip(
                    &item.name,
                    item.price,
                    &item.actions,
                    &format!("{:?}", obj.condition),
                ));
            }
        }
    }

    if hovered == state.text {
        state.dwell += time.delta_seconds();
    } else {
        state.text = hovered;
        state.dwell = 0.0;
    }
}

/// Render the tooltip near the cursor once the dwell threshold is reached.
fn render_tooltip(
    mut commands: Commands,
    windows: Query<&Window>,
    state: Res<TooltipState>,
    nodes: Query<Entity, With<TooltipNode>>,
) {
    for node in &nodes {
        commands.entity(node).despawn_recursive();
    }
    if state.dwell < TOOLTIP_DELAY {
        return;
    }
    let (Some(text), Ok(window)) = (&state.text, windows.get_single()) else {
        return;
    };
    let Some(cursor) = window.cursor_position() else {
        return;
    };
    let left = (cursor.x + 16.0).min(window.width() - 250.0).max(4.0);
    let top = (cursor.y + 18.0).min(window.height() - 90.0).max(4.0);

    commands
        .spawn((
            NodeBundle {
                style: Style {
                    position_type: PositionType::Absolute,
                    left: Val::Px(left),
                    top: Val::Px(top),
                    width: Val::Px(240.0),
                    padding: UiRect::all(Val::Px(8.0)),
                    ..default()
                },
                background_color: Color::srgba(0.04, 0.06, 0.10, 0.96).into(),
                border_radius: BorderRadius::all(Val::Px(5.0)),
                z_index: ZIndex::Global(100),
                ..default()
            },
            TooltipNode,
            Name::new("Tooltip"),
        ))
        .with_children(|t| {
            t.spawn(TextBundle::from_section(
                text.clone(),
                TextStyle {
                    font_size: 14.0,
                    color: Color::srgb(0.92, 0.95, 1.0),
                    ..default()
                },
            ));
        });
}

/// Registers the tooltip system (live mode only).
pub struct TooltipPlugin;

impl Plugin for TooltipPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<TooltipState>().add_systems(
            Update,
            (detect_tooltip, render_tooltip)
                .chain()
                .run_if(in_state(GameState::LiveMode)),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sim::needs::NeedType;

    #[test]
    fn object_tooltip_lists_name_price_needs_state() {
        let actions = vec![ObjectAction {
            name: "Sleep".to_string(),
            need: NeedType::Energy,
            rate: 10.0,
        }];
        let tip = object_tooltip("Double Bed", 800, &actions, "Clean");
        assert!(tip.contains("Double Bed"));
        assert!(tip.contains("$800"));
        assert!(tip.contains("Energy"));
        assert!(tip.contains("Clean"));
    }

    #[test]
    fn sim_tooltip_shows_name_mood_action() {
        let tip = sim_tooltip("Alex", Mood::Happy, AnimationState::Sleeping);
        assert!(tip.contains("Alex"));
        assert!(tip.contains("Happy"));
        assert!(tip.contains("Sleeping"));
    }

    #[test]
    fn empty_action_object_reads_nothing() {
        let tip = object_tooltip("Statue", 200, &[], "Clean");
        assert!(tip.contains("nothing"));
    }
}
