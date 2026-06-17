use bevy::prelude::*;

use crate::render::primitives::MeshGenerator;

/// Visual properties of a Sim.
#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct SimAppearance {
    pub skin_tone: Color,
    pub hair_color: Color,
    pub hair_style: HairStyle,
    pub shirt_color: Color,
    pub pants_color: Color,
    pub shoe_color: Color,
}

#[derive(Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect]
pub enum HairStyle {
    #[default]
    Short,
    Long,
    Curly,
    Bald,
}

/// Named skin-tone presets for Create-A-Sim.
pub fn skin_tones() -> [(&'static str, Color); 5] {
    [
        ("Fair", Color::srgb(0.96, 0.84, 0.74)),
        ("Light", Color::srgb(0.90, 0.74, 0.60)),
        ("Tan", Color::srgb(0.80, 0.62, 0.46)),
        ("Brown", Color::srgb(0.58, 0.42, 0.30)),
        ("Deep", Color::srgb(0.40, 0.28, 0.20)),
    ]
}

/// Named hair-colour presets.
pub fn hair_colors() -> [(&'static str, Color); 5] {
    [
        ("Black", Color::srgb(0.10, 0.09, 0.09)),
        ("Brown", Color::srgb(0.36, 0.24, 0.14)),
        ("Blonde", Color::srgb(0.85, 0.72, 0.40)),
        ("Red", Color::srgb(0.62, 0.26, 0.14)),
        ("Grey", Color::srgb(0.66, 0.66, 0.68)),
    ]
}

/// Named shirt-colour presets.
pub fn shirt_colors() -> [(&'static str, Color); 5] {
    [
        ("Blue", Color::srgb(0.25, 0.45, 0.78)),
        ("Red", Color::srgb(0.78, 0.28, 0.28)),
        ("Green", Color::srgb(0.30, 0.62, 0.38)),
        ("Purple", Color::srgb(0.52, 0.34, 0.70)),
        ("Charcoal", Color::srgb(0.28, 0.30, 0.34)),
    ]
}

/// Named hair styles.
pub fn hair_styles() -> [(&'static str, HairStyle); 4] {
    [
        ("Short", HairStyle::Short),
        ("Long", HairStyle::Long),
        ("Curly", HairStyle::Curly),
        ("Bald", HairStyle::Bald),
    ]
}

/// Build a `SimAppearance` from Create-A-Sim preset indices (wrapping).
pub fn appearance_from_indices(
    skin: usize,
    hair_color: usize,
    hair_style: usize,
    shirt: usize,
) -> SimAppearance {
    let skins = skin_tones();
    let hairs = hair_colors();
    let shirts = shirt_colors();
    let styles = hair_styles();
    SimAppearance {
        skin_tone: skins[skin % skins.len()].1,
        hair_color: hairs[hair_color % hairs.len()].1,
        hair_style: styles[hair_style % styles.len()].1,
        shirt_color: shirts[shirt % shirts.len()].1,
        pants_color: Color::srgb(0.22, 0.24, 0.30),
        shoe_color: Color::srgb(0.15, 0.15, 0.17),
    }
}

/// Voice parameters for Simlish vocalizations.
#[derive(Component, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect(Component)]
pub struct SimVoice {
    pub pitch: f32,
    pub tone: f32,
}

impl Default for SimVoice {
    fn default() -> Self {
        Self {
            pitch: 1.0,
            tone: 0.5,
        }
    }
}

/// Marker component indicating an entity has a procedurally built Sim body.
#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Component)]
pub struct SimBody;

/// Build a simple procedural Sim body as children of the given parent.
///
/// The body consists of a capsule torso, sphere head, and cylinder limbs.
/// Uses `appearance` colors for hair/shirt/pants; the skin texture is still
/// applied to the head, arms, and hands.
pub fn build_sim_body(
    parent: &mut ChildBuilder,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    appearance: &SimAppearance,
    skin_texture: Handle<Image>,
) {
    let skin_material = materials.add(StandardMaterial {
        base_color_texture: Some(skin_texture),
        base_color: appearance.skin_tone,
        perceptual_roughness: 0.7,
        ..default()
    });
    let hair_material = materials.add(StandardMaterial {
        base_color: appearance.hair_color,
        perceptual_roughness: 0.9,
        ..default()
    });
    let shirt_material = materials.add(StandardMaterial {
        base_color: appearance.shirt_color,
        perceptual_roughness: 0.8,
        ..default()
    });
    let pants_material = materials.add(StandardMaterial {
        base_color: appearance.pants_color,
        perceptual_roughness: 0.85,
        ..default()
    });
    let shoe_material = materials.add(StandardMaterial {
        base_color: appearance.shoe_color,
        perceptual_roughness: 0.85,
        ..default()
    });

    // Torso capsule: radius 0.25, length 0.6.
    parent.spawn(PbrBundle {
        mesh: meshes.add(MeshGenerator::capsule(0.25, 0.6)),
        material: shirt_material.clone(),
        transform: Transform::from_xyz(0.0, 1.0, 0.0),
        ..default()
    });

    // Shoulders: a flattened sphere across the top of the torso for breadth.
    parent.spawn(PbrBundle {
        mesh: meshes.add(MeshGenerator::sphere(0.22, 1)),
        material: shirt_material,
        transform: Transform::from_xyz(0.0, 1.32, 0.0).with_scale(Vec3::new(1.45, 0.55, 0.85)),
        ..default()
    });

    // Neck: a short skin cylinder linking the torso and head.
    parent.spawn(PbrBundle {
        mesh: meshes.add(MeshGenerator::cylinder(0.5, 1.0, 8)),
        material: skin_material.clone(),
        transform: Transform::from_xyz(0.0, 1.42, 0.0).with_scale(Vec3::new(0.16, 0.18, 0.16)),
        ..default()
    });

    // Head sphere: radius 0.22.
    let head = parent
        .spawn(PbrBundle {
            mesh: meshes.add(MeshGenerator::sphere(0.22, 1)),
            material: skin_material.clone(),
            transform: Transform::from_xyz(0.0, 1.65, 0.0),
            ..default()
        })
        .id();

    // Eyes: white sclera with a dark pupil, on the front (+Z) of the head, so
    // the sim reads as a face rather than a blank ball.
    let eye_white = materials.add(StandardMaterial {
        base_color: Color::srgb(0.96, 0.96, 0.96),
        perceptual_roughness: 0.4,
        ..default()
    });
    let eye_dark = materials.add(StandardMaterial {
        base_color: Color::srgb(0.12, 0.10, 0.10),
        perceptual_roughness: 0.3,
        ..default()
    });
    for side in [-1.0_f32, 1.0] {
        parent.spawn(PbrBundle {
            mesh: meshes.add(MeshGenerator::sphere(0.05, 1)),
            material: eye_white.clone(),
            transform: Transform::from_xyz(side * 0.085, 1.68, 0.17),
            ..default()
        });
        parent.spawn(PbrBundle {
            mesh: meshes.add(MeshGenerator::sphere(0.026, 1)),
            material: eye_dark.clone(),
            transform: Transform::from_xyz(side * 0.085, 1.68, 0.205),
            ..default()
        });
    }

    // Hair cap: slightly larger sphere segment on top of head, style-driven.
    let hair_transform = match appearance.hair_style {
        HairStyle::Long => {
            Transform::from_xyz(0.0, 1.68, 0.0).with_scale(Vec3::new(1.05, 0.55, 1.05))
        }
        HairStyle::Curly => {
            Transform::from_xyz(0.0, 1.74, 0.0).with_scale(Vec3::new(1.15, 0.45, 1.15))
        }
        HairStyle::Bald => {
            Transform::from_xyz(0.0, 1.72, 0.0).with_scale(Vec3::new(0.9, 0.05, 0.9))
        }
        HairStyle::Short => {
            Transform::from_xyz(0.0, 1.72, 0.0).with_scale(Vec3::new(1.0, 0.35, 1.0))
        }
    };

    if appearance.hair_style != HairStyle::Bald {
        parent.spawn(PbrBundle {
            mesh: meshes.add(MeshGenerator::sphere(0.23, 1)),
            material: hair_material,
            transform: hair_transform,
            ..default()
        });
    }

    // Arms (cylinders) with simple hands.
    let arm_transform_l = Transform::from_xyz(-0.38, 1.25, 0.0)
        .with_rotation(Quat::from_rotation_z(0.15))
        .with_scale(Vec3::new(0.12, 0.6, 0.12));
    let arm_transform_r = Transform::from_xyz(0.38, 1.25, 0.0)
        .with_rotation(Quat::from_rotation_z(-0.15))
        .with_scale(Vec3::new(0.12, 0.6, 0.12));

    parent.spawn(PbrBundle {
        mesh: meshes.add(MeshGenerator::cylinder(0.5, 1.0, 8)),
        material: skin_material.clone(),
        transform: arm_transform_l,
        ..default()
    });
    parent.spawn(PbrBundle {
        mesh: meshes.add(MeshGenerator::cylinder(0.5, 1.0, 8)),
        material: skin_material.clone(),
        transform: arm_transform_r,
        ..default()
    });

    // Hands (small spheres at the end of arms).
    parent.spawn(PbrBundle {
        mesh: meshes.add(MeshGenerator::sphere(0.07, 1)),
        material: skin_material.clone(),
        transform: Transform::from_xyz(-0.42, 0.9, 0.0),
        ..default()
    });
    parent.spawn(PbrBundle {
        mesh: meshes.add(MeshGenerator::sphere(0.07, 1)),
        material: skin_material.clone(),
        transform: Transform::from_xyz(0.42, 0.9, 0.0),
        ..default()
    });

    // Legs (cylinders).
    let leg_transform_l =
        Transform::from_xyz(-0.15, 0.35, 0.0).with_scale(Vec3::new(0.14, 0.7, 0.14));
    let leg_transform_r =
        Transform::from_xyz(0.15, 0.35, 0.0).with_scale(Vec3::new(0.14, 0.7, 0.14));

    parent.spawn(PbrBundle {
        mesh: meshes.add(MeshGenerator::cylinder(0.5, 1.0, 8)),
        material: pants_material.clone(),
        transform: leg_transform_l,
        ..default()
    });
    parent.spawn(PbrBundle {
        mesh: meshes.add(MeshGenerator::cylinder(0.5, 1.0, 8)),
        material: pants_material,
        transform: leg_transform_r,
        ..default()
    });

    // Shoes (small boxes at the bottom of legs).
    parent.spawn(PbrBundle {
        mesh: meshes.add(MeshGenerator::cube(0.18)),
        material: shoe_material.clone(),
        transform: Transform::from_xyz(-0.15, 0.05, 0.0).with_scale(Vec3::new(1.0, 0.4, 1.4)),
        ..default()
    });
    parent.spawn(PbrBundle {
        mesh: meshes.add(MeshGenerator::cube(0.18)),
        material: shoe_material,
        transform: Transform::from_xyz(0.15, 0.05, 0.0).with_scale(Vec3::new(1.0, 0.4, 1.4)),
        ..default()
    });

    // Store the head entity so animation systems can rotate it.
    parent.spawn((SimBodyPart {
        part: BodyPart::Head,
        target: head,
    },));
}

/// Marker for a named body part that can be animated.
#[derive(Component, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Component)]
pub struct SimBodyPart {
    pub part: BodyPart,
    pub target: Entity,
}

/// Identifiable body part for procedural animation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect]
pub enum BodyPart {
    Head,
    LeftArm,
    RightArm,
    LeftLeg,
    RightLeg,
}

/// Height offset used to place a Sim on the ground at a given position.
pub fn ground_offset(_age: crate::sim::SimAge) -> f32 {
    0.0 // Child primitives are already built relative to ground.
}

impl crate::sim::SimAge {
    /// Build a scale transform that sizes the body based on life stage.
    pub fn body_scale(self) -> Vec3 {
        Vec3::splat(self.height_scale())
    }
}
