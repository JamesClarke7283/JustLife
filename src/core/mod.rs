use bevy::prelude::*;

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
) {
    commands.spawn((Camera3dBundle {
        transform: Transform::from_xyz(10.0, 10.0, 10.0).looking_at(Vec3::ZERO, Vec3::Y),
        ..default()
    },));

    commands.spawn((DirectionalLightBundle {
        directional_light: DirectionalLight {
            shadows_enabled: true,
            ..default()
        },
        transform: Transform::from_xyz(4.0, 8.0, 4.0).looking_at(Vec3::ZERO, Vec3::Y),
        ..default()
    },));

    commands.spawn((PbrBundle {
        mesh: meshes.add(Plane3d::default().mesh().size(20.0, 20.0)),
        material: materials.add(StandardMaterial {
            base_color: Color::srgb(0.25, 0.55, 0.25),
            perceptual_roughness: 0.85,
            ..default()
        }),
        ..default()
    },));

    commands.spawn((PbrBundle {
        mesh: meshes.add(Cuboid::new(1.0, 1.0, 1.0)),
        material: materials.add(Color::srgb_u8(124, 144, 255)),
        transform: Transform::from_xyz(0.0, 0.5, 0.0),
        ..default()
    },));
}
