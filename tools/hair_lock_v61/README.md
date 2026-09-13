# Hair lock v61 — rounded lock sections and sealed shells

Re-authors the flat hair locks into rounded cords and closes every open hair and
collar shell. Reference for the target look: the archived Sims 4 hair studies
(`research/sims4/`, soft rounded lobes with tapered tips). The geometry itself is
original JustLife work and no reference pixel enters the shipped assets.

Run from the repository root:

```sh
python3 tools/hair_lock_v61/generate.py --repository . --output dist/hair_lock_v61 --apply
```

## The two defects

**Flat planks.** `hair_lock_v60` measures each lock's root-ring aspect
(depth/width) and holds that ratio constant down the whole strand. Locks are
authored flat at the scalp, so the measured median depth/width was **0.505** —
every lock read as a plank in profile and the free length had no volume at all.
v61 keeps the authored root aspect (roots must stay flat against the scalp) and
ramps the section toward circular along the lock, holding the cross-section
*area* constant so hair mass is unchanged. Measured on the adult source:
median depth/width **0.505 → 0.608**, with the middle and free length of every
lock at 1.0 (fully round). The scalp ring is still written byte-exactly.

**Zero-thickness sheets.** Twelve shells were open surfaces with no SOLIDIFY
modifier. glTF materials are single-sided by default, so Godot culls their back
faces and the inside of the garment shows through — this is the origin of the
collar/shoulder sliver that the iteration 60 review records, and of hair that
reads as see-through against a background. v61 gives each a closed 7 mm shell
inserted before the armature, so the finished closed surface is what deforms.

Sealing is chosen by material, because thickness must match the surface's scale.
`Hair` is the main shell (caps, back, knot, tail) and is sealed; `Hair_highlight`
ribbons are 3–6 mm decorative strips (`Hair_Bob_Strand` is 3 mm thick,
`Hair_Curls_Ridge` 6 mm) and a 7 mm shell would double them, so they are left
alone. The garment list is explicit: the hoodie hood and the three collar
bindings. Hem, cuff, placket, pocket, rib and drawstring trim are excluded for
the same reason.

## Ownership

The author fails unless exactly the declared set changes. Per family:

- **36 locks** (`Hair_{Bob,Long,Waves}_Lock*`) — re-sectioned.
- **12 shells** — 8 `Hair`-material caps/tail/back/knot plus 4 garment pieces
  (hoodie hood and three collar bindings) — given a closed shell.

That is 48 changed objects; every other object (412 in adult/child/teen, 420 in
elder) is byte-compared before and after across geometry, UVs, weights, shape
keys, modifiers, transforms, materials and visibility.

## Verification

The driver asserts the decoded glTF contract per family against that family's
own qualified baseline export, so face identity cannot drift silently:

| Family | Primitives | Morph primitives | Materials |
| --- | ---: | ---: | ---: |
| adult | 430 | 30 | 20 |
| child | 430 | 28 | 20 |
| teen | 430 | 28 | 20 |
| elder | 438 | 36 | 21 |

All nine morph target names (`Blink`, `Eye_Spacing`, `Face_Round`, `Hand_Grip_L`,
`Hand_Grip_R`, `Jaw_Strong`, `Nose_Wide`, `Sit`, `Smile`) and exactly one skin
must survive in all sixteen variants. Lock and cap nodes must survive LOD
decimation.

With `--apply` the driver copies the candidates into the working tree,
re-qualifies `art/source/character_production_hashes.json` and the adult decoded
PINS in `tools/verify_character_exports.py`, re-runs that verifier, and
reproduces the qualified adult bytes through the established
`tools/export_character_variant.py` path.

Unlike v60 the driver takes its baseline from the working tree, because the v60
artwork is the committed state, and it does not run the v60 evidence renderer
(that renderer takes ~20 minutes per family on this machine). Evidence captures
come from `tests/probe_character61.gd` in the real game, from
`tools/render_face_macro.py` in Blender, and — for the hair specifically — the
adult family's before/after set in `evidence/hair61/`. The other three families
are covered by the per-family contract assertions rather than by their own
renders, because they run the identical author code path and the author asserts
the same 48-object change set and the same twelve sealed shells for each.

## Known limitations

- The rounding ramp is a static authoring constant, not simulated cloth. Very
  flat roots still read slightly oval in extreme profile.
- The sealed shells have open borders where the original sheet was open; the
  solidify rim closes them but the rim is a hard edge rather than a rolled hem.
- Character GLBs grow about 3.6% (adult 16.7 MB → 17.3 MB) from the added shell
  geometry.
