use bevy::prelude::*;

pub struct AssetsPlugin;

impl Plugin for AssetsPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<MaterialLibrary>()
            .init_resource::<MeshLibrary>()
            .init_resource::<CatalogDatabase>();
    }
}

#[derive(Resource, Default, Debug)]
pub struct MaterialLibrary {
    pub materials: bevy::utils::HashMap<String, Handle<StandardMaterial>>,
}

#[derive(Resource, Default, Debug)]
pub struct MeshLibrary {
    pub meshes: bevy::utils::HashMap<String, Handle<Mesh>>,
}

#[derive(Resource, Default, Debug)]
pub struct CatalogDatabase {
    pub items: Vec<CatalogItem>,
}

#[derive(Default, Debug, Clone, PartialEq, Reflect)]
#[reflect]
pub struct CatalogItem {
    pub id: String,
    pub name: String,
    pub category: String,
    pub subcategory: String,
    pub price: u32,
    pub description: String,
    pub dimensions: Vec3,
}
