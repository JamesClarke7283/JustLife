use bevy::prelude::*;

/// A wall segment connecting two grid points.
#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Wall {
    pub start: Vec2,
    pub end: Vec2,
    pub height: f32,
    pub thickness: f32,
}

impl Wall {
    /// Create a new wall segment between two points.
    pub fn new(start: Vec2, end: Vec2) -> Self {
        Self {
            start,
            end,
            height: 3.0,
            thickness: 0.15,
        }
    }

    /// Snap wall endpoints to the nearest grid unit.
    pub fn snapped(start: Vec2, end: Vec2) -> Self {
        Self::new(snap_to_grid(start), snap_to_grid(end))
    }

    /// Length of the wall segment in the XZ plane.
    pub fn length(&self) -> f32 {
        self.end.distance(self.start)
    }

    /// Midpoint of the wall segment.
    pub fn midpoint(&self) -> Vec2 {
        (self.start + self.end) * 0.5
    }

    /// Direction vector from start to end (normalized).
    pub fn direction(&self) -> Vec2 {
        (self.end - self.start).normalize_or_zero()
    }

    /// Perpendicular normal pointing to one side of the wall.
    pub fn normal(&self) -> Vec2 {
        let dir = self.direction();
        Vec2::new(-dir.y, dir.x)
    }

    /// Check if this wall overlaps another wall (coincident and intersecting).
    pub fn overlaps(&self, other: &Wall) -> bool {
        self.start == other.start && self.end == other.end
            || self.start == other.end && self.end == other.start
    }
}

/// Snap a point to the nearest whole grid unit.
pub fn snap_to_grid(point: Vec2) -> Vec2 {
    Vec2::new(point.x.round(), point.y.round())
}

/// Marker that a wall needs its visual mesh rebuilt.
#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Component)]
pub struct WallVisualDirty;

/// Marker for a wall mesh child entity.
#[derive(Component, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect(Component)]
pub struct WallMeshChild {
    pub parent_wall: Entity,
    pub face: WallFace,
}

/// Which face of a wall a mesh represents.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect]
pub enum WallFace {
    Interior,
    Exterior,
}

/// Build the visual meshes for a wall and attach them as children.
pub fn build_wall_visuals(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    asset_server: &AssetServer,
    wall_entity: Entity,
    wall: &Wall,
) {
    let interior_texture: Handle<Image> = asset_server.load("textures/wall_plaster_light.png");
    let exterior_texture: Handle<Image> = asset_server.load("textures/wall_brick_red.png");

    let interior_material = materials.add(StandardMaterial {
        base_color_texture: Some(interior_texture),
        perceptual_roughness: 0.9,
        ..default()
    });
    let exterior_material = materials.add(StandardMaterial {
        base_color_texture: Some(exterior_texture),
        perceptual_roughness: 0.9,
        ..default()
    });

    let mid = wall.midpoint().extend(0.0);
    let delta = wall.end - wall.start;
    let length = delta.length();
    let angle = delta.y.atan2(delta.x);
    let rotation = Quat::from_rotation_y(-angle);

    let interior_mesh = meshes.add(crate::render::primitives::MeshGenerator::wall(
        length,
        wall.height,
        wall.thickness,
    ));
    let interior = commands
        .spawn((
            PbrBundle {
                mesh: interior_mesh,
                material: interior_material,
                transform: Transform {
                    translation: mid + Vec3::new(0.0, wall.height / 2.0, 0.0),
                    rotation,
                    scale: Vec3::ONE,
                },
                ..default()
            },
            WallMeshChild {
                parent_wall: wall_entity,
                face: WallFace::Interior,
            },
        ))
        .id();

    let exterior = commands
        .spawn((
            PbrBundle {
                mesh: meshes.add(crate::render::primitives::MeshGenerator::wall(
                    length,
                    wall.height,
                    wall.thickness,
                )),
                material: exterior_material,
                transform: Transform {
                    translation: mid + Vec3::new(0.0, wall.height / 2.0, 0.0),
                    rotation,
                    scale: Vec3::new(1.0, 1.0, 1.02),
                },
                ..default()
            },
            WallMeshChild {
                parent_wall: wall_entity,
                face: WallFace::Exterior,
            },
        ))
        .id();

    commands
        .entity(wall_entity)
        .push_children(&[interior, exterior]);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wall_snaps_to_grid() {
        let wall = Wall::snapped(Vec2::new(0.4, 0.6), Vec2::new(4.3, 4.4));
        assert_eq!(wall.start, Vec2::new(0.0, 1.0));
        assert_eq!(wall.end, Vec2::new(4.0, 4.0));
    }

    #[test]
    fn wall_direction_and_normal_are_perpendicular() {
        let wall = Wall::new(Vec2::ZERO, Vec2::X * 4.0);
        assert!(wall.direction().dot(wall.normal()).abs() < 0.0001);
    }

    #[test]
    fn wall_overlaps_detects_coincident() {
        let a = Wall::new(Vec2::ZERO, Vec2::X * 4.0);
        let b = Wall::new(Vec2::ZERO, Vec2::X * 4.0);
        let c = Wall::new(Vec2::X, Vec2::X * 4.0);
        assert!(a.overlaps(&b));
        assert!(!a.overlaps(&c));
    }
}
