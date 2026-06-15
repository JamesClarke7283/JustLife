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
        material: shirt_material,
        transform: Transform::from_xyz(0.0, 1.0, 0.0),
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
