use bevy::prelude::*;

use super::{SimAge, SimTraits, Trait, needs::Needs};

/// Movement target for a Sim. Added when the Sim should travel to a location.
#[derive(Component, Default, Debug, Clone, Copy, PartialEq, Reflect)]
#[reflect(Component)]
pub struct MoveTo {
    pub target: Vec3,
    pub speed: f32,
    pub arrival_distance: f32,
    pub running: bool,
}

impl MoveTo {
    pub fn new(target: Vec3) -> Self {
        Self {
            target,
            speed: BASE_WALK_SPEED,
            arrival_distance: 0.1,
            running: false,
        }
    }

    pub fn with_speed(mut self, speed: f32) -> Self {
        self.speed = speed;
        self
    }

    pub fn running(mut self) -> Self {
        self.running = true;
        self
    }
}

/// Pathfinding state for a Sim following a grid path.
#[derive(Component, Default, Debug, Clone, PartialEq, Reflect)]
#[reflect(Component)]
pub struct PathState {
    pub waypoints: Vec<Vec3>,
    pub current_index: usize,
}

impl PathState {
    pub fn new(waypoints: Vec<Vec3>) -> Self {
        Self {
            waypoints,
            current_index: 0,
        }
    }

    pub fn current_target(&self) -> Option<Vec3> {
        self.waypoints.get(self.current_index).copied()
    }

    pub fn advance(&mut self) {
        self.current_index += 1;
    }

    pub fn is_complete(&self) -> bool {
        self.current_index >= self.waypoints.len()
    }
}

/// Base movement speed for an adult Sim in world units per second.
pub const BASE_WALK_SPEED: f32 = 2.0;
pub const BASE_RUN_SPEED: f32 = 4.5;

/// Compute an A* path over a grid from `start` to `goal`.
///
/// Grid cells are 1x1 world units. Walls and placed objects are treated as
/// blocking obstacles when present. This is a minimal placeholder pathfinder
/// sufficient for early lots; it can be replaced with a navmesh later.
pub fn compute_grid_path(
    start: Vec3,
    goal: Vec3,
    obstacles: &[(i32, i32)],
    half_extents: i32,
) -> Vec<Vec3> {
    let start_cell = (start.x.round() as i32, start.z.round() as i32);
    let goal_cell = (goal.x.round() as i32, goal.z.round() as i32);

    if start_cell == goal_cell {
        return vec![goal];
    }

    let mut open: std::collections::BinaryHeap<std::cmp::Reverse<NodeCost>> =
        std::collections::BinaryHeap::new();
    let mut came_from: std::collections::HashMap<(i32, i32), (i32, i32)> =
        std::collections::HashMap::new();
    let mut g_score: std::collections::HashMap<(i32, i32), f32> = std::collections::HashMap::new();

    g_score.insert(start_cell, 0.0);
    open.push(std::cmp::Reverse(NodeCost {
        cell: start_cell,
        f: heuristic(start_cell, goal_cell),
    }));

    let neighbors = [(1, 0), (-1, 0), (0, 1), (0, -1)];

    while let Some(std::cmp::Reverse(current)) = open.pop() {
        if current.cell == goal_cell {
            break;
        }

        let current_g = *g_score.get(&current.cell).unwrap_or(&f32::MAX);
        for (dx, dz) in neighbors {
            let neighbor = (current.cell.0 + dx, current.cell.1 + dz);
            if neighbor.0.abs() > half_extents || neighbor.1.abs() > half_extents {
                continue;
            }
            if obstacles.contains(&neighbor) {
                continue;
            }

            let tentative = current_g + 1.0;
            if tentative < *g_score.get(&neighbor).unwrap_or(&f32::MAX) {
                came_from.insert(neighbor, current.cell);
                g_score.insert(neighbor, tentative);
                open.push(std::cmp::Reverse(NodeCost {
                    cell: neighbor,
                    f: tentative + heuristic(neighbor, goal_cell),
                }));
            }
        }
    }

    // Reconstruct path if found.
    let mut path = Vec::new();
    let mut current = goal_cell;
    while current != start_cell {
        path.push(Vec3::new(current.0 as f32, 0.0, current.1 as f32));
        if let Some(prev) = came_from.get(&current) {
            current = *prev;
        } else {
            // No path found: return direct fallback.
            return vec![goal];
        }
    }

    path.reverse();
    if path
        .last()
        .map(|p| (p.x.round() as i32, p.z.round() as i32))
        != Some(goal_cell)
    {
        path.push(goal);
    }
    path
}

fn heuristic(a: (i32, i32), b: (i32, i32)) -> f32 {
    ((a.0 - b.0).abs() + (a.1 - b.1).abs()) as f32
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct NodeCost {
    cell: (i32, i32),
    f: f32,
}

impl Eq for NodeCost {}

impl Ord for NodeCost {
    fn cmp(&self, other: &Self) -> std::cmp::Ordering {
        self.f
            .partial_cmp(&other.f)
            .unwrap_or(std::cmp::Ordering::Equal)
    }
}

impl PartialOrd for NodeCost {
    fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
        Some(self.cmp(other))
    }
}

type MovingSimQueryItem<'a> = (
    Entity,
    &'a mut Transform,
    &'a MoveTo,
    &'a SimAge,
    Option<&'a Needs>,
    Option<&'a SimTraits>,
);

pub fn move_to_system(
    mut commands: Commands,
    mut sims: Query<MovingSimQueryItem>,
    path_states: Query<(Entity, &PathState)>,
    time: Res<Time>,
) {
    let mut moving: std::collections::HashSet<Entity> = std::collections::HashSet::new();

    for (entity, mut transform, move_to, age, needs, traits) in &mut sims {
        moving.insert(entity);

        let direction = move_to.target - transform.translation;
        let distance_sq = direction.length_squared();
        let arrival_sq = move_to.arrival_distance * move_to.arrival_distance;

        if distance_sq <= arrival_sq {
            commands.entity(entity).remove::<MoveTo>();
            continue;
        }

        let speed = effective_speed(move_to.speed, move_to.running, *age, needs, traits);
        let step = direction.normalize() * speed * time.delta_seconds();
        transform.translation += step;

        // Face movement direction on the XZ plane.
        if step.xz().length_squared() > 0.0001 {
            let forward = Vec3::new(step.x, 0.0, step.z).normalize();
            let target_rotation = Quat::from_rotation_arc(Vec3::Z, forward);
            transform.rotation = transform
                .rotation
                .slerp(target_rotation, 10.0 * time.delta_seconds());
        }
    }

    // PathState entities without a MoveTo get a fresh MoveTo pointed at their current waypoint.
    for (entity, path) in path_states.iter() {
        if !moving.contains(&entity)
            && !path.is_complete()
            && let Some(target) = path.current_target()
        {
            commands.entity(entity).insert(MoveTo::new(target));
        }
    }
}

/// Follow a precomputed path, waypoint by waypoint.
pub fn path_follow_system(
    mut commands: Commands,
    mut sims: Query<(Entity, &mut PathState, &Transform)>,
) {
    for (entity, mut path, transform) in &mut sims {
        if path.is_complete() {
            commands.entity(entity).remove::<PathState>();
            continue;
        }

        let Some(target) = path.current_target() else {
            commands.entity(entity).remove::<PathState>();
            continue;
        };

        let distance_sq = (target - transform.translation).length_squared();
        if distance_sq < 0.04 {
            path.advance();
        }
    }
}

/// Compute effective movement speed based on energy, age, traits, and running.
fn effective_speed(
    requested: f32,
    running: bool,
    age: SimAge,
    needs: Option<&Needs>,
    traits: Option<&SimTraits>,
) -> f32 {
    let mut speed = if running {
        BASE_RUN_SPEED
    } else {
        requested.max(BASE_WALK_SPEED)
    };
    speed *= age.speed_multiplier();

    if let Some(needs) = needs {
        // Very low energy slows movement.
        if needs.energy < 20.0 {
            speed *= 0.6;
        } else if needs.energy < 50.0 {
            speed *= 0.85;
        }
    }

    if let Some(traits) = traits {
        if traits.traits.contains(&Trait::Lazy) {
            speed *= 0.85;
        }
        if traits.traits.contains(&Trait::Active) {
            speed *= 1.1;
        }
    }

    speed
}
