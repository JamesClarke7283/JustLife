use bevy::prelude::*;
use serde::{Deserialize, Serialize};

use crate::core::components::{Interactable, Sellable};
use crate::render::primitives::MeshGenerator;
use crate::sim::needs::NeedType;
use crate::world::{ObjectCondition, PlacedObject};

/// Buy-mode catalog categories (mirrors The Sims buy-mode sorting).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Reflect, Default)]
pub enum CatalogCategory {
    #[default]
    Comfort,
    Surfaces,
    Plumbing,
    Electronics,
    Appliances,
    Lighting,
    Decorative,
    Outdoor,
    Kids,
    Dining,
    Bathroom,
    Bedroom,
    Kitchen,
    Office,
    Fitness,
    Party,
}

impl CatalogCategory {
    /// Every category, for building category tabs.
    pub const ALL: [CatalogCategory; 16] = [
        CatalogCategory::Comfort,
        CatalogCategory::Surfaces,
        CatalogCategory::Plumbing,
        CatalogCategory::Electronics,
        CatalogCategory::Appliances,
        CatalogCategory::Lighting,
        CatalogCategory::Decorative,
        CatalogCategory::Outdoor,
        CatalogCategory::Kids,
        CatalogCategory::Dining,
        CatalogCategory::Bathroom,
        CatalogCategory::Bedroom,
        CatalogCategory::Kitchen,
        CatalogCategory::Office,
        CatalogCategory::Fitness,
        CatalogCategory::Party,
    ];

    /// Human-readable label for UI.
    pub fn label(&self) -> &'static str {
        match self {
            CatalogCategory::Comfort => "Comfort",
            CatalogCategory::Surfaces => "Surfaces",
            CatalogCategory::Plumbing => "Plumbing",
            CatalogCategory::Electronics => "Electronics",
            CatalogCategory::Appliances => "Appliances",
            CatalogCategory::Lighting => "Lighting",
            CatalogCategory::Decorative => "Decorative",
            CatalogCategory::Outdoor => "Outdoor",
            CatalogCategory::Kids => "Kids",
            CatalogCategory::Dining => "Dining",
            CatalogCategory::Bathroom => "Bathroom",
            CatalogCategory::Bedroom => "Bedroom",
            CatalogCategory::Kitchen => "Kitchen",
            CatalogCategory::Office => "Office",
            CatalogCategory::Fitness => "Fitness",
            CatalogCategory::Party => "Party",
        }
    }
}

/// A procedural primitive shape used to assemble a catalog item's mesh.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize, Reflect, Default)]
pub enum PrimitiveShape {
    #[default]
    Cuboid,
    Cylinder,
    Sphere,
    Cone,
}

/// One coloured primitive part of a catalog item, expressed in the item's local
/// space. `size` is the full bounding extent; for round shapes the X extent is
/// treated as the diameter and Y as the height.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Reflect)]
pub struct PrimitivePart {
    pub shape: PrimitiveShape,
    pub size: (f32, f32, f32),
    pub offset: (f32, f32, f32),
    pub color: (f32, f32, f32),
}

/// An interaction an object offers and the need it restores while used.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Reflect)]
pub struct ObjectAction {
    /// Pie-menu label, e.g. "Sleep", "Get Snack".
    pub name: String,
    /// Which need this action restores.
    pub need: NeedType,
    /// Need points restored per in-game minute while performing the action.
    pub rate: f32,
}

/// A purchasable object definition loaded from the catalog data file.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Reflect)]
pub struct CatalogItem {
    pub id: String,
    pub name: String,
    pub category: CatalogCategory,
    pub subcategory: String,
    pub price: u32,
    pub description: String,
    /// Grid footprint in cells (width, depth).
    pub footprint: (u32, u32),
    /// Primitive parts assembled into the object's 3D mesh.
    pub parts: Vec<PrimitivePart>,
    /// Interactions this object offers (which need each satisfies). Optional in
    /// the data file; defaults to none for purely decorative objects.
    #[serde(default)]
    pub actions: Vec<ObjectAction>,
}

/// Resource holding every catalog item, loaded from `assets/data/catalog.ron`.
/// (No `Default` derive: it provides `FromWorld` to load the embedded RON, which
/// would conflict with Bevy's blanket `FromWorld for T: Default`.)
#[derive(Resource, Debug, Clone)]
pub struct CatalogDatabase {
    pub items: Vec<CatalogItem>,
}

impl CatalogDatabase {
    /// Look up an item by its stable id.
    pub fn get(&self, id: &str) -> Option<&CatalogItem> {
        self.items.iter().find(|i| i.id == id)
    }

    /// Iterate every item in a category.
    pub fn by_category(&self, category: CatalogCategory) -> impl Iterator<Item = &CatalogItem> {
        self.items.iter().filter(move |i| i.category == category)
    }

    /// Parse a catalog from a RON string (a list of `CatalogItem`).
    pub fn parse_ron(src: &str) -> Result<Self, ron::error::SpannedError> {
        let items: Vec<CatalogItem> = ron::from_str(src)?;
        Ok(Self { items })
    }
}

impl FromWorld for CatalogDatabase {
    fn from_world(_world: &mut World) -> Self {
        // Embedded at compile time so the catalog is available immediately at
        // startup and works identically on the wasm target.
        const RON: &str = include_str!("../../assets/data/catalog.ron");
        match Self::parse_ron(RON) {
            Ok(db) => {
                info!("Loaded {} catalog items", db.items.len());
                db
            }
            Err(err) => {
                error!("Failed to parse catalog.ron: {err}");
                Self { items: Vec::new() }
            }
        }
    }
}

/// Spawn a catalog item as a parent entity with one child mesh per primitive
/// part. Returns the parent entity, which carries a [`PlacedObject`].
pub fn spawn_catalog_item(
    commands: &mut Commands,
    meshes: &mut Assets<Mesh>,
    materials: &mut Assets<StandardMaterial>,
    item: &CatalogItem,
    position: Vec3,
    rotation: Quat,
) -> Entity {
    let parent = commands
        .spawn((
            SpatialBundle::from_transform(
                Transform::from_translation(position).with_rotation(rotation),
            ),
            PlacedObject {
                catalog_id: item.id.clone(),
                position,
                rotation,
                condition: ObjectCondition::Clean,
                footprint: item.footprint,
                powered: false,
            },
            Interactable,
            Sellable { value: item.price },
            Name::new(item.name.clone()),
        ))
        .id();

    for part in &item.parts {
        let (sx, sy, sz) = part.size;
        let mesh = match part.shape {
            PrimitiveShape::Cuboid => meshes.add(Cuboid::new(sx, sy, sz)),
            PrimitiveShape::Cylinder => meshes.add(Cylinder::new(sx * 0.5, sy)),
            PrimitiveShape::Sphere => meshes.add(Sphere::new(sx * 0.5)),
            PrimitiveShape::Cone => meshes.add(MeshGenerator::cone(sx * 0.5, sy, 16)),
        };
        let material = materials.add(StandardMaterial {
            base_color: Color::srgb(part.color.0, part.color.1, part.color.2),
            perceptual_roughness: 0.8,
            ..default()
        });
        let child = commands
            .spawn(PbrBundle {
                mesh,
                material,
                transform: Transform::from_translation(Vec3::new(
                    part.offset.0,
                    part.offset.1,
                    part.offset.2,
                )),
                ..default()
            })
            .id();
        commands.entity(parent).add_child(child);
    }

    parent
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn embedded_catalog_parses_and_is_populated() {
        let db = CatalogDatabase::from_world(&mut World::new());
        assert!(!db.items.is_empty(), "catalog.ron should contain items");
        // Every item must have at least one primitive part to render.
        for item in &db.items {
            assert!(!item.parts.is_empty(), "{} has no parts", item.id);
            assert!(!item.id.is_empty());
        }
    }

    #[test]
    fn lookup_helpers_work() {
        let db = CatalogDatabase::from_world(&mut World::new());
        let first_id = db.items[0].id.clone();
        assert!(db.get(&first_id).is_some());
        assert!(db.get("definitely-not-real").is_none());
        // At least one comfort item exists in the starter catalog.
        let comfort = db.by_category(CatalogCategory::Comfort).count();
        assert!(comfort >= 1);
    }

    #[test]
    fn need_objects_declare_actions() {
        let db = CatalogDatabase::from_world(&mut World::new());
        // The core need-satisfying objects all exist and restore the right need.
        let cases = [
            ("bed_double", NeedType::Energy),
            ("toilet", NeedType::Bladder),
            ("shower", NeedType::Hygiene),
            ("fridge", NeedType::Hunger),
            ("tv_flatscreen", NeedType::Fun),
            ("phone", NeedType::Social),
        ];
        for (id, need) in cases {
            let item = db.get(id).unwrap_or_else(|| panic!("missing {id}"));
            assert!(
                item.actions.iter().any(|a| a.need == need && a.rate > 0.0),
                "{id} should restore {need:?}"
            );
        }
    }
}
