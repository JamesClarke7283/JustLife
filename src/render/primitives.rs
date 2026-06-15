use bevy::prelude::*;

/// Procedural mesh generation helpers and resource caches.
#[derive(Resource, Default, Debug)]
pub struct ShapeLibrary {
    pub meshes: bevy::utils::HashMap<ShapeKey, Handle<Mesh>>,
}

/// Key used to cache generated meshes.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum ShapeKey {
    Cube,
    Plane,
    Cylinder(u32),
    Sphere(u32),
    Cone(u32),
}

/// Utility for generating common procedural meshes.
pub struct MeshGenerator;

impl MeshGenerator {
    /// Generate a plane mesh with optional tiling for textures.
    pub fn plane(width: f32, depth: f32, uv_scale: f32) -> Mesh {
        let mut mesh = Plane3d::default().mesh().size(width, depth).build();
        apply_uv_tiling(&mut mesh, Vec2::splat(uv_scale));
        mesh
    }

    /// Generate a box suitable for a wall segment.
    pub fn wall(length: f32, height: f32, thickness: f32) -> Mesh {
        Cuboid::new(length, height, thickness).mesh().build()
    }

    /// Generate a cube of the given size.
    pub fn cube(size: f32) -> Mesh {
        Cuboid::new(size, size, size).mesh().build()
    }

    /// Generate a cylinder.
    pub fn cylinder(radius: f32, height: f32, resolution: u32) -> Mesh {
        let resolution = resolution.max(3);
        Cylinder::new(radius, height)
            .mesh()
            .resolution(resolution)
            .build()
    }

    /// Generate a sphere.
    pub fn sphere(radius: f32, resolution: u32) -> Mesh {
        let subdivisions = resolution as usize;
        Sphere::new(radius)
            .mesh()
            .ico(subdivisions)
            .unwrap_or_else(|_| Sphere::new(radius).mesh().uv(16, 16))
    }

    /// Generate a cone.
    pub fn cone(radius: f32, height: f32, resolution: u32) -> Mesh {
        Cone { radius, height }
            .mesh()
            .resolution(resolution.max(3))
            .build()
    }

    /// Generate a capsule.
    pub fn capsule(radius: f32, length: f32) -> Mesh {
        Capsule3d::new(radius, length).mesh().build()
    }

    /// Populate the shape library with the most commonly used primitives.
    pub fn populate_default_shapes(library: &mut ShapeLibrary, meshes: &mut Assets<Mesh>) {
        library
            .meshes
            .insert(ShapeKey::Cube, meshes.add(Self::cube(1.0)));
        library
            .meshes
            .insert(ShapeKey::Plane, meshes.add(Self::plane(1.0, 1.0, 1.0)));
        library.meshes.insert(
            ShapeKey::Cylinder(16),
            meshes.add(Self::cylinder(0.5, 1.0, 16)),
        );
        library
            .meshes
            .insert(ShapeKey::Sphere(1), meshes.add(Self::sphere(0.5, 1)));
        library
            .meshes
            .insert(ShapeKey::Cone(16), meshes.add(Self::cone(0.5, 1.0, 16)));
    }
}

use bevy::render::mesh::VertexAttributeValues;

// Patch the typo `uxs` to use the correct `VertexAttributeValues` type.
fn apply_uv_tiling(mesh: &mut Mesh, scale: Vec2) {
    if let Some(VertexAttributeValues::Float32x2(uvs)) = mesh.attribute_mut(Mesh::ATTRIBUTE_UV_0) {
        for uv in uvs.iter_mut() {
            uv[0] *= scale.x;
            uv[1] *= scale.y;
        }
    }
}

/// Helper component bundle linking a mesh to a material for a textured primitive.
#[derive(Bundle, Default, Debug, Clone)]
pub struct TexturedPrimitive {
    pub mesh: Handle<Mesh>,
    pub material: Handle<StandardMaterial>,
}

impl TexturedPrimitive {
    /// Scale a 1x1 primitive to the requested world size and rotation.
    pub fn transform(&self, position: Vec3, scale: Vec3, rotation: Quat) -> Transform {
        Transform {
            translation: position,
            rotation,
            scale,
        }
    }
}
