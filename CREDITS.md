# JustLife credits

JustLife is an original life simulation. Its characters are Lifelets; its homes, furniture, clothing, UI emblem, layouts, palettes, story writing and wordless character sounds were created for this project. Blender authoring sources and generators are in `art/` and `tools/` in the source project. The Sims gameplay screenshots are reference research stored separately in Downloads and are not included in the game.

The application icon and matching JustLife launch splash were created for JustLife with the built-in image generation tool. Their home, heart and sprout symbolize home-making, relationships and growth; the final prompts are recorded in `art/ICON_PROMPT.md` and `art/SPLASH_PROMPT.md` in the source project.

The field maple trees are original Blender artwork, with their editable source in `art/vegetation/` and generator in `tools/create_vegetation.py`. The cats, dogs and pet accessories are original Blender artwork too, built from primitives by `tools/create_pets.py`, with their source scene in `art/pets.blend`; their mixed coats are drawn by `assets/shaders/pet_coat.gdshader`. Character face controls are authored natively from each age family's own measured geometry by `tools/portrait_v62/identity.py`, `tools/identity_shape_v62/` and `tools/ensure_candidate_uvs.py`. Camera and menu icons are original SVG drawings in `assets/ui/`.

The background theme **Summit Dawn** (`assets/audio/Summit Dawn.wav`) is the game's own supplied music, used under the project's ownership; it is not a third-party or licensed track. All other audio is synthesized for JustLife by `tools/create_audio.py`.

Godot Engine is distributed under the MIT license. Its license text, component copyright notices and third-party license texts are included in `licenses/`. Blender is an authoring tool and is not included in the game.

Roboto Regular (`assets/fonts/Body.ttf`): Copyright 2011 Google Inc. Apache License 2.0; see `licenses/Roboto-Apache-2.0.txt`. Unmodified font.

GNU FreeSerif (`assets/fonts/Display.otf`): Copyright 2002–2012 GNU FreeFont contributors. GPL version 3 with the font embedding exception; see `licenses/FreeSerif-notice.txt` and `licenses/GNU-GPL-3.0.txt`. Unmodified font. Corresponding font source and releases: https://www.gnu.org/software/freefont/ and https://ftp.gnu.org/gnu/freefont/.
