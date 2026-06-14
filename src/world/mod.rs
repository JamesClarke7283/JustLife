use bevy::prelude::*;

pub struct WorldPlugin;

impl Plugin for WorldPlugin {
    fn build(&self, app: &mut App) {
        app.init_resource::<LotManager>()
            .register_type::<Lot>()
            .register_type::<Wall>()
            .register_type::<Door>()
            .register_type::<Window>()
            .register_type::<Room>()
            .register_type::<PlacedObject>();
    }
}

#[derive(Resource, Default, Debug)]
pub struct LotManager {
    pub lots: Vec<Entity>,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Lot {
    pub name: String,
    pub position: Vec2,
    pub width: f32,
    pub depth: f32,
    pub value: u32,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Wall {
    pub start: Vec2,
    pub end: Vec2,
    pub height: f32,
    pub thickness: f32,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Door {
    pub locked: bool,
    pub connected_rooms: [Option<Entity>; 2],
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Window {
    pub wall_segment: Option<Entity>,
    pub allows_light: bool,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct Room {
    pub name: String,
    pub area: f32,
    pub indoor: bool,
    pub floor_material: String,
}

#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct PlacedObject {
    pub catalog_id: String,
    pub position: Vec3,
    pub rotation: Quat,
    pub condition: ObjectCondition,
}

#[derive(Default, Debug, Clone, Copy, PartialEq, Eq, Reflect)]
#[reflect]
pub enum ObjectCondition {
    #[default]
    Clean,
    Dirty,
    Broken,
}
