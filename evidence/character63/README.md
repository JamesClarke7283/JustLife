# Character evidence, iteration 63

Rendered from the real game by `tests/probe_character62.gd` in the isolated
character runner:

```
python3 tests/run_character_quality.py --render probe_character62
```

41 PNGs at the creator's native render quality (MSAA 4X, scale 1.0). The run
that produced them reports **5,178 checks, 0 failures**.

| Prefix | Shows |
| --- | --- |
| `identity_00_front` … `identity_05_three_quarter` | Six independently generated profiles in fixed neutral styling, so jaw/chin, cheek width, nose and eye set differ without styling or colour helping. |
| `styled_00` … `styled_05` | The same six as the real Surprise-me/Add-Lifelet methods create them. |
| `bob_front`, `bob_three_quarter`, `bob_back`, `bob_blonde`, `bob_red`, `bob_grey` | The continuous Bob from three angles plus recolours. |
| `combined_minimum`, `combined_maximum` and their `_blink` pairs | Every signed control at its extreme together, then with full Blink. |
| `age_{baby,child,teen,young_adult,adult,elder}_face` / `_body` | One face and one full-body frame per life stage, which is where the missing seven controls used to be silent. |
| `live_home` | The creator-to-home path in the actual live camera. |

These are runtime captures, not a quality score. They establish that every age
and every identity extreme now renders with the full eleven-control set; they do
not by themselves assert that the artwork is finished. The outstanding art
criticism and the unverified dimensions are listed in
[the iteration 63 review](../docs/REVIEWS/iteration_63_identity_controls.md).
