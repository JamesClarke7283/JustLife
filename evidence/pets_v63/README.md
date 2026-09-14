# Pet and pet-shop evidence

Rendered evidence for iteration 63's pet work, captured from the real game with
`tests/capture_pets.gd` at 1280×614 on the authoring machine:

```
JUSTLIFE_DATA_DIR=/tmp/jl_cap/save_data XDG_DATA_HOME=/tmp/jl_cap/xdg \
  godot --path . --audio-driver Dummy --script res://tests/capture_pets.gd
```

The harness drives only public paths: it opens the phone shop, opens the picker,
buys a cat and a dog through the real paid `prepare_pet`/`commit_pet` path and
photographs them in the home. It halts `_process` before the close-ups and calls
`_tick_pets` directly so the camera and the arrival walk are deterministic.
The close-ups temporarily stand each pet on clear open grass so the coat is not
occluded, then restore them; nothing about the pets or the household is faked.

| Shot | Shows |
| --- | --- |
| `01_pet_shop.png` | The phone's Juniper Pet Shop before any pet is owned: both species' prices, and the accessories available to a household with no pets. |
| `02_pet_picker_mixed_coat.png` | The pet picker on a long-haired, bicolour dog with a 0.8 mixed gradient — every control, the coat swatches and the live preview. |
| `03_pet_picker_solid_coat.png` | The same picker on a short-haired, plain charcoal cat at gradient 0, showing the solid end of the same control set. |
| `04_live_pets_in_home.png` | Both pets standing on clear floor inside the home after walking in; the wallet reads §1,700, exactly §800 down for a §320 cat and a §480 dog. |
| `05_cat_close.png` | The solid coat at three-quarter view: even colour, pointed ears, tail up, red collar. |
| `05_dog_close.png` | The mixed coat at three-quarter view: dark brown back blending to a pale muzzle, paws and tail tip, with folded ears. |
| `06_pet_card.png` | The pets screen built by the same control set the person picker uses, with the cat's portrait. |
| `07_pet_catalogue.png` | The **Pets** category in Build & buy with all three accessories and their prices. |
| `08_pet_shop_with_pets.png` | The shop once a cat and a dog are home: the roster ("Willow · Female cat, Bramble · Male dog") and all three accessories offered. |

These are runtime screenshots, not a quality score. They confirm the shipped
layout and that the coats are visibly different and natural; they do not
constitute a full independent review, and the models are original low-poly
geometry of the same order as the existing furnishings.
