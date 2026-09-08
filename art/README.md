# Artwork sources

Production artwork is original JustLife work. The runtime loads exported GLBs from `assets/models/`; Blender is only needed to author or regenerate them.

- `characters.blend`, `characters_child.blend`, `characters_teen.blend`, `characters_elder.blend`: accepted character sources for the four authored age families. Young adults use the adult sculpt.
- `furniture.blend`: the furniture collection.
- `furniture/desk_booster.blend`: the child's visible desk-seat support.
- `celebration/birthday_cake.blend`: the birthday cake, plate and candles.
- `meals/garden_supper.blend`: original serving dish, individual plate, food and fork; export hashes and regeneration instructions are in its README.
- `source/grip_v3/`: immutable hand and rig inputs used by the surface-repair generator. These are source dependencies, not disposable backups.
- `source/character_v18_production_hashes.json`: compact accepted-asset provenance.
- `experiments/hair_v19/`: editable, unpromoted hairstyle research. Its README explains how to regenerate the study.
- `ICON_PROMPT.md`, `SPLASH_PROMPT.md`, `BRANDING_PROMPTS.md`: provenance for the original home/heart/sprout icon and JustLife wordmark splash in `assets/ui/`.

See `docs/CHARACTER_ASSETS.md` for authoring commands. Large iteration archives, generated PNGs, raw test reports and playthrough screenshots remain local and ignored. They are not required by the exported game. Preserve a study's unique editable source and generator here before archiving its outputs.
