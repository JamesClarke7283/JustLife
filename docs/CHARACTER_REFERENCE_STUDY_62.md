# Character reference study — iteration 62

The reference is the polished character-creation experience, not permission to
ship copied characters, meshes, textures, branding or interface artwork.
JustLife's character sources and new procedural surfaces remain original.

## Inspected material

The browser capture of [Interface In Game's Sims 4 gallery](https://interfaceingame.com/games/the-sims-4/)
is retained locally in `research/sims4/browser_capture_20260914/`, with its
download manifest and source URLs. This capture contains six gameplay/creation
screenshots plus cover/banner images; it is not eight distinct gameplay images.
The earlier full-resolution archive and two contact sheets were also inspected,
including `research/sims4/full/the-sims-4-eyebrows.png`. Reference downloads are
research-only and excluded from the game export.

## Observations that changed the work

- An eye reads as an opening in a continuous face. A smaller iris cannot fix a
  globe sitting in front of the cheek. This led to the separate orbital/lid
  construction pass and full-Blink checks, not further cosmetic iris resizing.
- Hair has a readable large silhouette, a part and directional secondary flow.
  This led to replacing the bob's detached rods with an uninterrupted shell,
  then authoring original strand tone, normal and roughness detail.
- Distinct characters require different proportions, not simply palettes.
  Six same-styled Godot portraits revealed that the initial eight controls
  still produced close relatives. Face length, mouth width and bridge profile
  are being added as genuinely coupled geometry controls, with transported
  mouth-contact landmarks for eating/drinking.
- Skin, eyes, hair and garments need different surface responses. This remains
  a quality requirement; improving the bob does not prove the skin or wardrobe
  is finished.
- Face editing needs uncluttered, immediate visual feedback. The new controls
  are grouped into Shape, Eyes, Nose and Mouth, preserving the connected
  creator → home choice → live household flow.

These are our art/design conclusions from the viewed images. They are not
claims about the reference game's implementation.

## Current review boundary

The independent candidate review is in
`docs/REVIEWS/iteration_62_candidate_critic.md`: character art 6/10, facial
individuality 5/10 and creator presentation 8/10. The controlled profiles are
retained in `evidence/portrait_v62/controlled_identity_receipt.json`.
Those scores do not cover unseen subsequent candidates, motion, every age or
every hairstyle. Current candidate files are not a completed release.
