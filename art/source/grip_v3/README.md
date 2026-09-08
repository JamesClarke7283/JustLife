# Immutable hand sources

These four original Blender files supply the accepted continuous arm meshes, vertex weights and `Hand_Grip_L` / `Hand_Grip_R` morphs to `tools/create_characters.py -- --surface-repair`. The generator loads only the two arm mesh objects, preserving exact hand geometry across unrelated remeshing changes.

They were copied byte for byte from the approved local `art/iterations/grip_v3_frozen` archive during repository cleanup. `manifest.json` records their SHA-256 hashes. They are maintained source inputs, not disposable export output. Keep them when cloning or archiving the source project. Update them only after reviewing a new hand revision and recording its provenance.
