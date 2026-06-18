use bevy::input::mouse::{MouseScrollUnit, MouseWheel};
use bevy::prelude::*;
use std::f32::consts::{FRAC_PI_2, FRAC_PI_4, PI};

pub struct CameraPlugin;

impl Plugin for CameraPlugin {
    fn build(&self, app: &mut App) {
        app.register_type::<IsometricCamera>()
            .register_type::<CameraRig>()
            .init_resource::<CameraInputState>()
            .add_systems(Startup, spawn_camera)
            .add_systems(
                Update,
                (camera_input, update_camera_transform, camera_follow),
            );
    }
}

/// Marker for the isometric gameplay camera.
#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect(Component)]
pub struct IsometricCamera;

/// Rig configuration for the isometric camera. Stored on the camera entity.
#[derive(Component, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect(Component)]
pub struct CameraRig {
    /// Horizontal orbit angle in radians around the Y axis.
    pub yaw: f32,
    /// Vertical pitch in radians (fixed for isometric look).
    pub pitch: f32,
    /// Distance from the focal point.
    pub distance: f32,
    /// Minimum allowed zoom distance.
    pub min_distance: f32,
    /// Maximum allowed zoom distance.
    pub max_distance: f32,
    /// World-space focal point the camera orbits around.
    pub target: Vec3,
    /// Whether the camera is following the selected entity.
    pub follow_mode: bool,
}

impl Default for CameraRig {
    fn default() -> Self {
        Self {
            yaw: FRAC_PI_4,
            pitch: FRAC_PI_4,
            distance: 18.0,
            min_distance: 5.0,
            max_distance: 50.0,
            target: Vec3::ZERO,
            follow_mode: false,
        }
    }
}

impl CameraRig {
    /// Snap the orbit to the nearest quarter-turn (90 degrees).
    pub fn snap_rotation(&mut self) {
        let quarters = (self.yaw / FRAC_PI_4).round();
        self.yaw = quarters * FRAC_PI_4;
        // Normalize to [0, 2*pi).
        self.yaw = self.yaw.rem_euclid(2.0 * PI);
    }

    /// Quarter-turn rotation step in radians.
    pub const ROTATION_STEP: f32 = FRAC_PI_2;

    /// Current camera position derived from the rig.
    pub fn eye_position(&self) -> Vec3 {
        let dx = self.distance * self.yaw.cos() * self.pitch.cos();
        let dz = self.distance * self.yaw.sin() * self.pitch.cos();
        let dy = self.distance * self.pitch.sin();
        self.target + Vec3::new(dx, dy, dz)
    }
}

/// Runtime transient input state for the camera.
#[derive(Resource, Default, Debug, Clone, Copy, PartialEq)]
pub struct CameraInputState {
    pub is_panning: bool,
    pub last_cursor: Option<Vec2>,
}

fn spawn_camera(mut commands: Commands) {
    commands.spawn((
        Camera3dBundle {
            projection: Projection::Orthographic(OrthographicProjection {
                // Pixels-per-world-unit. At the default rig distance (18) this
                // shows ~32 world units across a 1280px-wide canvas, framing the
                // 10x10 lot. `scale` (driven by rig distance below) zooms it.
                scale: 1.0,
                near: 0.1,
                far: 1000.0,
                viewport_origin: Vec2::new(0.5, 0.5),
                scaling_mode: bevy::render::camera::ScalingMode::WindowSize(40.0),
                area: Rect::new(-1.0, -1.0, 1.0, 1.0),
            }),
            transform: Transform::from_xyz(10.0, 10.0, 10.0).looking_at(Vec3::ZERO, Vec3::Y),
            ..default()
        },
        IsometricCamera,
        CameraRig::default(),
    ));
}

/// Reads keyboard/mouse input and updates the camera rig.
#[allow(clippy::too_many_arguments)]
fn camera_input(
    mut rig_query: Query<&mut CameraRig, With<IsometricCamera>>,
    mut input_state: ResMut<CameraInputState>,
    keyboard: Res<ButtonInput<KeyCode>>,
    mouse_button: Res<ButtonInput<MouseButton>>,
    mut scroll_events: EventReader<MouseWheel>,
    windows: Query<&Window>,
    settings: Res<crate::settings::GameSettings>,
    time: Res<Time>,
) {
    let Ok(mut rig) = rig_query.get_single_mut() else {
        return;
    };

    // Toggle follow mode. Escape cancels it.
    if keyboard.just_pressed(KeyCode::KeyF) {
        rig.follow_mode = !rig.follow_mode;
    }
    if keyboard.just_pressed(KeyCode::Escape) && rig.follow_mode {
        rig.follow_mode = false;
    }

    // Rotation with Q/E (counter-clockwise / clockwise).
    if keyboard.just_pressed(KeyCode::KeyQ) {
        rig.yaw -= CameraRig::ROTATION_STEP;
        rig.snap_rotation();
    }
    if keyboard.just_pressed(KeyCode::KeyE) {
        rig.yaw += CameraRig::ROTATION_STEP;
        rig.snap_rotation();
    }

    // WASD panning relative to camera orientation on the XZ plane.
    let mut pan_input = Vec2::ZERO;
    if keyboard.pressed(KeyCode::KeyW) {
        pan_input.y += 1.0;
    }
    if keyboard.pressed(KeyCode::KeyS) {
        pan_input.y -= 1.0;
    }
    if keyboard.pressed(KeyCode::KeyA) {
        pan_input.x -= 1.0;
    }
    if keyboard.pressed(KeyCode::KeyD) {
        pan_input.x += 1.0;
    }

    if pan_input != Vec2::ZERO {
        // Disable follow mode when the player manually pans.
        rig.follow_mode = false;
        let flat_forward = Vec3::new(rig.yaw.sin(), 0.0, rig.yaw.cos()).normalize();
        let flat_right = Vec3::new(rig.yaw.cos(), 0.0, -rig.yaw.sin()).normalize();
        let delta =
            (flat_forward * pan_input.y + flat_right * pan_input.x) * 8.0 * time.delta_seconds();
        rig.target += delta;
    }

    // Zoom via mouse wheel. Browsers report large per-notch pixel deltas, so
    // scale them down; desktop line-deltas are ~1 per notch.
    for event in scroll_events.read() {
        let step = match event.unit {
            MouseScrollUnit::Line => event.y * 1.5,
            MouseScrollUnit::Pixel => event.y * 0.02,
        } * settings.zoom_speed;
        rig.distance = (rig.distance - step).clamp(rig.min_distance, rig.max_distance);
    }

    // Middle-mouse drag panning.
    let Ok(window) = windows.get_single() else {
        return;
    };

    if mouse_button.just_pressed(MouseButton::Middle) {
        input_state.is_panning = true;
        input_state.last_cursor = window.cursor_position();
    }
    if mouse_button.just_released(MouseButton::Middle) {
        input_state.is_panning = false;
        input_state.last_cursor = None;
    }

    if input_state.is_panning
        && let Some(current) = window.cursor_position()
        && let Some(previous) = input_state.last_cursor
    {
        let delta = current - previous;
        if delta.length_squared() > 0.0 {
            rig.follow_mode = false;
            let scale = rig.distance * 0.0015;
            let flat_forward = Vec3::new(rig.yaw.sin(), 0.0, rig.yaw.cos()).normalize();
            let flat_right = Vec3::new(rig.yaw.cos(), 0.0, -rig.yaw.sin()).normalize();
            let world_delta = flat_forward * delta.y * scale + flat_right * -delta.x * scale;
            rig.target -= world_delta;
        }
        input_state.last_cursor = Some(current);
    }
}

/// Smoothly update the camera transform from the rig.
fn update_camera_transform(
    mut camera_query: Query<(&mut Transform, &CameraRig, &mut Projection), With<IsometricCamera>>,
    time: Res<Time>,
) {
    let Ok((mut transform, rig, mut projection)) = camera_query.get_single_mut() else {
        return;
    };

    let target_position = rig.eye_position();
    // Look straight at the focal point from the (elevated) eye position. The old
    // hand-built quaternion pointed the camera *upward*, leaving the scene as a
    // foreshortened sliver at the bottom of the view.
    let target_rotation = Transform::from_translation(target_position)
        .looking_at(rig.target, Vec3::Y)
        .rotation;

    let lerp_factor = 10.0 * time.delta_seconds();
    transform.translation = transform.translation.lerp(target_position, lerp_factor);
    transform.rotation = transform.rotation.slerp(target_rotation, lerp_factor);

    // Update orthographic projection size when zooming for a true isometric feel.
    // `scale` multiplies the WindowSize-derived area; tie it to the rig distance
    // so the default distance (18) maps to scale 1.0.
    if let Projection::Orthographic(ref mut ortho) = *projection {
        ortho.scale = rig.distance / 18.0;
    }
}

/// Camera follow mode: track the selected entity with a smooth lerp.
fn camera_follow(
    mut rig_query: Query<&mut CameraRig, With<IsometricCamera>>,
    selection: Res<crate::core::resources::SelectionResource>,
    target_query: Query<&Transform, Without<IsometricCamera>>,
    time: Res<Time>,
) {
    let Ok(mut rig) = rig_query.get_single_mut() else {
        return;
    };
    if !rig.follow_mode {
        return;
    }

    let Some(selected) = selection.selected else {
        return;
    };

    let Ok(target_transform) = target_query.get(selected) else {
        return;
    };

    let goal = target_transform.translation;
    rig.target = rig.target.lerp(goal, 5.0 * time.delta_seconds());

    // Reset the yaw to the default isometric angle when following to keep
    // the selected sim framed nicely.
    let default_yaw = FRAC_PI_4;
    if (rig.yaw - default_yaw).abs() > 0.01 {
        rig.yaw = rig.yaw.lerp(default_yaw, 2.0 * time.delta_seconds());
    }
}
