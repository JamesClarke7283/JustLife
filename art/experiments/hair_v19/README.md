# Unpromoted hair study

This is revision 3 of the original Bob/Curls study for character revision 19. It has not passed final critic review and is not used by the game. The editable adult and child candidates were copied unchanged from the local historical study; the older revision 2 remains in the ignored archive.

From the repository root, regenerate one age with:

```sh
blender --background -t 4 --python art/experiments/hair_v19/create_hair_v19.py -- --age adult
```

Use `--age child` for the other existing candidate. The script supports teen and elder proportions, but no reviewed candidates for those stages are supplied here. Add `--export` to write an excluded `assets/models/character_<age>_hair_v19_grip.glb` candidate; the script does not promote it.

The generator resolves paths from its own location. It reads the standard editable character source and the age helper functions in `tools/create_characters.py`, requiring the source's hash to match `art/source/character_v18_production_hashes.json`. If the production baseline changes, review the experiment before updating the pinned baseline. Historical iteration directories are not required.

The script verifies that non-hair geometry, morphs, skin weights and transforms are unchanged. It saves the editable candidate beside the script; preview PNGs and preservation reports are generated local output. `source_manifest.json` records the initial retained candidates and original study provenance.
