use bevy::ecs::event::EventWriter;
use bevy::prelude::*;

use crate::core::events::TimeTickEvent;
use crate::core::resources::{GameSpeed, GameTime};

pub fn tick_game_time(
    mut game_time: ResMut<GameTime>,
    game_speed: Res<GameSpeed>,
    mut writer: EventWriter<TimeTickEvent>,
    time: Res<Time>,
) {
    let speed = game_speed.multiplier();
    if speed == 0.0 {
        return;
    }

    let total_minutes = game_time.day * 24 * 60 + game_time.hour * 60 + game_time.minute;
    let new_minutes = total_minutes + (time.delta_seconds() * speed) as u32;

    game_time.day = new_minutes / (24 * 60);
    game_time.hour = (new_minutes % (24 * 60)) / 60;
    game_time.minute = new_minutes % 60;

    writer.send(TimeTickEvent {
        day: game_time.day,
        hour: game_time.hour,
        minute: game_time.minute,
    });
}
