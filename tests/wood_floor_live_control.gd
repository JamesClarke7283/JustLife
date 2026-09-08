extends "res://tests/test_live_floor_view.gd"
## Preserve every existing floor/view/motion assertion while using the already
## qualified actual-scene preload order. No production code or cache teardown.
const MainScene=preload("res://scenes/main.tscn")
