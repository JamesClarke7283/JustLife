use bevy::prelude::*;
use bevy::render::primitives::Aabb;

use crate::build::BuildTool;
use crate::core::resources::MoneyResource;
use crate::core::state::GameState;
use crate::render::camera::IsometricCamera;
use crate::world::room::RoomFloor;
use crate::world::wall::{Wall, WallFace, WallMeshChild};
use crate::world::wall_tool::{cursor_ground_xz, point_segment_distance};

/// Width of the material picker panel; clicks over it must not paint.
const PANEL_WIDTH: f32 = 250.0;

/// A selectable surface material.
pub struct MaterialDef {
    pub name: &'static str,
    pub texture: &'static str,
    pub cost: u32,
}

/// Floor materials (wood / tile / carpet / stone / concrete).
pub const FLOOR_MATERIALS: &[MaterialDef] = &[
    MaterialDef {
        name: "Oak Wood",
        texture: "textures/floor_hardwood_oak.png",
        cost: 4,
    },
    MaterialDef {
        name: "Light Wood",
        texture: "textures/floor_hardwood_light.png",
        cost: 4,
    },
    MaterialDef {
        name: "White Tile",
        texture: "textures/floor_tile_white.png",
        cost: 5,
    },
    MaterialDef {
        name: "Cream Tile",
        texture: "textures/floor_tile_cream.png",
        cost: 5,
    },
    MaterialDef {
        name: "Gray Carpet",
        texture: "textures/floor_carpet_gray.png",
        cost: 3,
    },
    MaterialDef {
        name: "Beige Carpet",
        texture: "textures/floor_carpet_beige.png",
        cost: 3,
    },
    MaterialDef {
        name: "Stone",
        texture: "textures/floor_stone.png",
        cost: 6,
    },
    MaterialDef {
        name: "Concrete",
        texture: "textures/terrain_concrete.png",
        cost: 2,
    },
];

/// Wall materials (paint / brick / paneling / stone).
pub const WALL_MATERIALS: &[MaterialDef] = &[
    MaterialDef {
        name: "Paint",
        texture: "textures/wall_plaster_light.png",
        cost: 3,
    },
    MaterialDef {
        name: "Brick",
        texture: "textures/wall_brick_red.png",
        cost: 5,
    },
    MaterialDef {
        name: "Paneling",
        texture: "textures/wall_wood_panel.png",
        cost: 4,
    },
    MaterialDef {
        name: "Stone",
        texture: "textures/floor_stone.png",
        cost: 6,
    },
];

/// The currently selected floor and wall material (indices into the arrays).
#[derive(Resource, Default)]
pub struct SelectedMaterials {
    pub floor: usize,
    pub wall: usize,
}

pub struct MaterialPickerPlugin;

impl Plugin for MaterialPickerPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<SelectedMaterials>()
            .add_systems(OnEnter(GameState::BuildMode), spawn_material_panel)
            .add_systems(OnExit(GameState::BuildMode), despawn_material_panel)
            .add_systems(
                Update,
                (
                    material_button_clicks,
                    highlight_material_buttons,
                    floor_paint_tool,
                    wall_paint_tool,
                )
                    .run_if(in_state(GameState::BuildMode)),
            );
    }
}

#[derive(Component)]
struct MaterialPanelUi;

#[derive(Component)]
struct FloorSwatch(usize);

#[derive(Component)]
struct WallSwatch(usize);

const SWATCH_BG: Color = Color::srgb(0.16, 0.19, 0.26);
const SWATCH_SELECTED: Color = Color::srgb(0.30, 0.55, 0.85);

fn spawn_material_panel(mut commands: Commands) {
    commands
        .spawn((
            NodeBundle {
                style: Style {
                    position_type: PositionType::Absolute,
                    top: Val::Px(56.0),
                    right: Val::Px(0.0),
                    width: Val::Px(PANEL_WIDTH),
                    flex_direction: FlexDirection::Column,
                    padding: UiRect::all(Val::Px(8.0)),
                    row_gap: Val::Px(4.0),
                    ..default()
                },
                background_color: Color::srgba(0.08, 0.10, 0.16, 0.92).into(),
                ..default()
            },
            MaterialPanelUi,
            Name::new("Material Picker"),
        ))
        .with_children(|panel| {
            heading(panel, "FLOORS  (tool 3)");
            for (i, m) in FLOOR_MATERIALS.iter().enumerate() {
                swatch(panel, m.name, m.cost, FloorSwatch(i));
            }
            heading(panel, "WALLS  (tool 4)");
            for (i, m) in WALL_MATERIALS.iter().enumerate() {
                swatch(panel, m.name, m.cost, WallSwatch(i));
            }
        });
}

fn heading(panel: &mut ChildBuilder, text: &str) {
    panel.spawn(TextBundle::from_section(
        text,
        TextStyle {
            font_size: 14.0,
            color: Color::srgb(0.85, 0.9, 0.7),
            ..default()
        },
    ));
}

fn swatch(panel: &mut ChildBuilder, name: &str, cost: u32, marker: impl Component) {
    panel
        .spawn((
            ButtonBundle {
                style: Style {
                    padding: UiRect::axes(Val::Px(6.0), Val::Px(3.0)),
                    ..default()
                },
                background_color: SWATCH_BG.into(),
                ..default()
            },
            marker,
        ))
        .with_children(|b| {
            b.spawn(TextBundle::from_section(
                format!("{name}   ${cost}"),
                TextStyle {
                    font_size: 13.0,
                    color: Color::srgb(0.9, 0.92, 0.96),
                    ..default()
                },
            ));
        });
}

fn despawn_material_panel(mut commands: Commands, panels: Query<Entity, With<MaterialPanelUi>>) {
    for entity in &panels {
        commands.entity(entity).despawn_recursive();
    }
}

fn material_button_clicks(
    mut selected: ResMut<SelectedMaterials>,
    floors: Query<(&Interaction, &FloorSwatch), Changed<Interaction>>,
    walls: Query<(&Interaction, &WallSwatch), Changed<Interaction>>,
) {
    for (interaction, swatch) in &floors {
        if *interaction == Interaction::Pressed {
            selected.floor = swatch.0;
        }
    }
    for (interaction, swatch) in &walls {
        if *interaction == Interaction::Pressed {
            selected.wall = swatch.0;
        }
    }
}

#[allow(clippy::type_complexity)]
fn highlight_material_buttons(
    selected: Res<SelectedMaterials>,
    mut floors: Query<(&FloorSwatch, &mut BackgroundColor), Without<WallSwatch>>,
    mut walls: Query<(&WallSwatch, &mut BackgroundColor), Without<FloorSwatch>>,
) {
    for (swatch, mut bg) in &mut floors {
        *bg = pick(swatch.0 == selected.floor).into();
    }
    for (swatch, mut bg) in &mut walls {
        *bg = pick(swatch.0 == selected.wall).into();
    }
}

fn pick(active: bool) -> Color {
    if active { SWATCH_SELECTED } else { SWATCH_BG }
}

/// True while the cursor is over the material panel.
fn over_panel(windows: &Query<&Window>) -> bool {
    let Ok(window) = windows.get_single() else {
        return true;
    };
    let Some(cursor) = window.cursor_position() else {
        return true;
    };
    cursor.x > window.width() - PANEL_WIDTH
}

/// Repaint the floor under the cursor with the selected floor material.
#[allow(clippy::too_many_arguments)]
fn floor_paint_tool(
    mouse: Res<ButtonInput<MouseButton>>,
    tool: Res<BuildTool>,
    selected: Res<SelectedMaterials>,
    windows: Query<&Window>,
    cameras: Query<(&Camera, &GlobalTransform), With<IsometricCamera>>,
    mut floors: Query<(&GlobalTransform, &Aabb, &mut Handle<StandardMaterial>), With<RoomFloor>>,
    mut money: ResMut<MoneyResource>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    asset_server: Res<AssetServer>,
) {
    if *tool != BuildTool::FloorPaint
        || !mouse.just_pressed(MouseButton::Left)
        || over_panel(&windows)
    {
        return;
    }
    let Some(p) = cursor_ground_xz(&windows, &cameras) else {
        return;
    };
    let def = &FLOOR_MATERIALS[selected.floor.min(FLOOR_MATERIALS.len() - 1)];
    for (gt, aabb, mut handle) in &mut floors {
        let c = gt.translation();
        if (p.x - c.x).abs() <= aabb.half_extents.x && (p.y - c.z).abs() <= aabb.half_extents.z {
            *handle = materials.add(StandardMaterial {
                base_color_texture: Some(asset_server.load(def.texture)),
                perceptual_roughness: 0.85,
                ..default()
            });
            money.amount -= def.cost as i64;
            break;
        }
    }
}

/// Repaint the interior face of the nearest wall with the selected wall material.
#[allow(clippy::too_many_arguments)]
fn wall_paint_tool(
    mouse: Res<ButtonInput<MouseButton>>,
    tool: Res<BuildTool>,
    selected: Res<SelectedMaterials>,
    windows: Query<&Window>,
    cameras: Query<(&Camera, &GlobalTransform), With<IsometricCamera>>,
    walls: Query<(Entity, &Wall)>,
    mut children: Query<(&WallMeshChild, &mut Handle<StandardMaterial>)>,
    mut money: ResMut<MoneyResource>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    asset_server: Res<AssetServer>,
) {
    if *tool != BuildTool::WallPaint
        || !mouse.just_pressed(MouseButton::Left)
        || over_panel(&windows)
    {
        return;
    }
    let Some(p) = cursor_ground_xz(&windows, &cameras) else {
        return;
    };
    let mut best: Option<(Entity, f32)> = None;
    for (entity, wall) in &walls {
        let d = point_segment_distance(p, wall.start, wall.end);
        if d <= 0.6 && best.is_none_or(|(_, bd)| d < bd) {
            best = Some((entity, d));
        }
    }
    let Some((wall_entity, _)) = best else {
        return;
    };
    let def = &WALL_MATERIALS[selected.wall.min(WALL_MATERIALS.len() - 1)];
    let new_material = materials.add(StandardMaterial {
        base_color_texture: Some(asset_server.load(def.texture)),
        perceptual_roughness: 0.9,
        ..default()
    });
    let mut painted = false;
    for (child, mut handle) in &mut children {
        if child.parent_wall == wall_entity && child.face == WallFace::Interior {
            *handle = new_material.clone();
            painted = true;
        }
    }
    if painted {
        money.amount -= def.cost as i64;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn material_tables_are_populated() {
        assert!(FLOOR_MATERIALS.len() >= 5);
        assert!(WALL_MATERIALS.len() >= 4);
        for m in FLOOR_MATERIALS.iter().chain(WALL_MATERIALS) {
            assert!(m.texture.starts_with("textures/"));
            assert!(!m.name.is_empty());
        }
    }
}
