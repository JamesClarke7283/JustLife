use bevy::prelude::*;

use crate::render::camera::IsometricCamera;

pub mod components;
pub mod events;
pub mod resources;
pub mod state;
pub mod time;

pub struct CorePlugin;

impl Plugin for CorePlugin {
    fn build(&self, app: &mut App) {
        app.register_type::<resources::GameTime>()
            .register_type::<resources::GameSpeed>()
            .register_type::<resources::MoneyResource>()
            .register_type::<resources::GameConfig>()
            .register_type::<resources::NeedDecayRates>()
            .register_type::<resources::AutonomyLevel>()
            .register_type::<resources::SelectionResource>()
            .init_resource::<resources::GameConfig>()
            .init_resource::<resources::GameTime>()
            .init_resource::<resources::GameSpeed>()
            .init_resource::<resources::MoneyResource>()
            .init_resource::<resources::SelectionResource>()
            .init_state::<state::GameState>()
            .add_event::<events::NeedChangeEvent>()
            .add_event::<crate::sim::needs::NeedThresholdEvent>()
            .add_event::<events::InteractionEvent>()
            .add_event::<events::TimeTickEvent>()
            .add_event::<events::SocialEvent>()
            .add_event::<events::CareerEvent>()
            .add_event::<events::BuildModeEvent>()
            .add_event::<events::SimSpawnEvent>()
            .add_event::<events::SimDeathEvent>()
            .add_systems(Startup, setup)
            .add_systems(Update, time::tick_game_time);
    }
}

fn setup(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    asset_server: Res<AssetServer>,
) {
    commands.spawn((
        Camera3dBundle {
            transform: Transform::from_xyz(10.0, 10.0, 10.0).looking_at(Vec3::ZERO, Vec3::Y),
            ..default()
        },
        IsometricCamera,
    ));

    commands.spawn((PbrBundle {
        mesh: meshes.add(Cuboid::new(1.0, 1.0, 1.0)),
        material: materials.add(StandardMaterial {
            base_color_texture: Some(asset_server.load("textures/furniture_wood_oak.png")),
            perceptual_roughness: 0.6,
            ..default()
        }),
        transform: Transform::from_xyz(0.0, 0.5, 0.0),
        ..default()
    },));
}
