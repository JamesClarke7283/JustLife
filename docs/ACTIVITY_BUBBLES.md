# Live speech presentation

`scripts/activity_bubbles.gd` projects short actor messages into the live interface using each animated head landmark. Text keeps approximately 16 physical pixels at the tested window sizes, independently of camera zoom. Each card names its speaker. Placement avoids visible heads, HUD controls and other cards; the selected Lifelet has priority. Excess crowd messages may be omitted when no nearby clear position fits.

LifeActor still owns the text, wordless voice and pause-aware lifetime. `speech_presentation()` exposes transient text and remaining time. The live layer enables `screen_speech` to suppress the older Label3D; standalone actors keep that fallback. Modal menus hide the cards, and normal play resumes their lifetime. Clearing or expiring a message removes its card. Messages are transient presentation and do not create or complete simulation actions.

The independent review accepted the normal, near and far camera views, an actual 960×600 window, simultaneous messages, pause/modal restoration and natural expiry. Its evidence and limits are in [iteration_11_speech.md](REVIEWS/iteration_11_speech.md). The crowded sample shows three of four speakers, with the selected Lifelet retained. General HUD sizing, every camera/age/window ratio, perceived audio and full-game dialogue breadth remain separate work.

Run `python tests/run_playthrough.py --suite supported_homework` for the connected creation, routed pair, cancellation, named restart, completion and speech views. Run `python tests/run_playthrough.py --suite speech_lifetime` for the shorter real-frame pause, menu and expiry check. The latter supplies presentation text explicitly and does not claim an activity completed. Both runners isolate project imports and user data.

Godot's [Camera3D projection](https://docs.godotengine.org/en/4.7/classes/class_camera3d.html) and [Viewport screen transform](https://docs.godotengine.org/en/4.7/classes/class_viewport.html) define the coordinate mapping used here.
