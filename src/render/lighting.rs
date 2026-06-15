use bevy::prelude::*;

pub struct LightingPlugin;

impl Plugin for LightingPlugin {
    fn build(&self, app: &mut App) {
        app.register_type::<SunLight>()
            .register_type::<AmbientLighting>()
            .init_resource::<AmbientLighting>()
            .add_systems(Startup, spawn_sun_and_ambient)
            .add_systems(Update, update_sun);
    }
}

/// Directional sun light that rotates through the day.
#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect(Component)]
pub struct SunLight {
    pub time_of_day: f32,
}

/// Global ambient light settings.
#[derive(Resource, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect(Resource)]
pub struct AmbientLighting {
    pub enabled: bool,
    pub color: Color,
    pub brightness: f32,
}

impl Default for AmbientLighting {
    fn default() -> Self {
        Self {
            enabled: true,
            color: Color::srgb(0.3, 0.35, 0.4),
            brightness: 0.6,
        }
    }
}

fn spawn_sun_and_ambient(mut commands: Commands, ambient: Res<AmbientLighting>) {
    commands.spawn((
        DirectionalLightBundle {
            directional_light: DirectionalLight {
                shadows_enabled: true,
                illuminance: 35_000.0,
                ..default()
            },
            transform: Transform::from_xyz(8.0, 12.0, 8.0).looking_at(Vec3::ZERO, Vec3::Y),
            ..default()
        },
        SunLight { time_of_day: 12.0 },
    ));

    commands.insert_resource(AmbientLight {
        color: ambient.color,
        brightness: ambient.brightness,
    });
}

fn update_sun(
    mut commands: Commands,
    mut sun_query: Query<(&mut Transform, &mut DirectionalLight, &mut SunLight)>,
    ambient: Res<AmbientLighting>,
    game_time: Res<crate::core::resources::GameTime>,
    keyboard: Res<ButtonInput<KeyCode>>,
) {
    let Ok((mut transform, mut light, mut sun)) = sun_query.get_single_mut() else {
        return;
    };

    // Update time from game clock.
    sun.time_of_day = game_time.hour as f32 + game_time.minute as f32 / 60.0;

    // N shortcut toggles day/night override for quick testing.
    if keyboard.just_pressed(KeyCode::KeyN) {
        sun.time_of_day = if sun.time_of_day < 12.0 { 18.0 } else { 6.0 };
    }

    let normalized = (sun.time_of_day - 6.0) / 12.0; // 0 at 6:00, 1 at 18:00.
    let angle = normalized.clamp(0.0, 1.0) * std::f32::consts::PI;

    let radius = 20.0;
    transform.translation = Vec3::new(
        -radius * angle.cos(),
        radius * angle.sin().max(0.05),
        radius * 0.5,
    );
    transform.look_at(Vec3::ZERO, Vec3::Y);

    // Color temperature shifts through the day.
    let (color, illuminance) = if sun.time_of_day < 5.0 || sun.time_of_day > 21.0 {
        (Color::srgb(0.15, 0.18, 0.35), 1_000.0)
    } else if sun.time_of_day < 8.0 {
        (Color::srgb(0.9, 0.7, 0.5), 20_000.0)
    } else if sun.time_of_day > 17.0 {
        (Color::srgb(0.9, 0.6, 0.45), 18_000.0)
    } else {
        (Color::srgb(1.0, 0.98, 0.95), 35_000.0)
    };

    light.color = color;
    light.illuminance = illuminance;

    if ambient.is_changed() {
        commands.insert_resource(AmbientLight {
            color: ambient.color,
            brightness: ambient.brightness,
        });
    }
}
