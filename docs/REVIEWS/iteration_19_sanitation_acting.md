# Iteration 19 — sanitation acting

The independent critic accepts the pot and accident reactions as an incremental
improvement: **8/10 for this feature, 7.5/10 for visual execution**. This does not
replace the last full-game assessment of 7.2/10 or earn the requested 10/10.

Pot use now includes a brief privacy glance, bent knees and an exhale. An idle
Lifelet who has an accident briefly looks down and raises a hand to their temple.
Walking, active tasks, carried meals and fading hand props discard that reaction;
it cannot interrupt them or play late. Pausing freezes the pose. No simulation
queue, need, actor root, charge, food identity or route changes with the gesture.
No character, clothing, hair, audio or mop geometry is replaced.

The frozen producer handoff is
`dist/test-work/sanitation-acting-a9jf4ykc/acting_handoff`. Root and critic verified
156 source inputs, six promotion files, 56 matched before/after screenshots and
27 evidence files. The final producer records pass 61 portable acting checks,
61 rendered candidate checks and the existing 207 sanitation checks without
engine warnings or errors. The matched baseline capture passes 28 checks.
These counts include individual assertions, not separate gameplay scenarios.

The independent review is
`dist/test-work/sanitation-acting-critic-s1n3m83y/evidence/ACTING_CRITIC_REVIEW.md`,
SHA-256 `37df750f0630c6c9641857e68f7ca3fc044a5856e937910a669d141183858277`.
The critic inspected 21 final frames and ran two additional 80-check transition
probes. Each preserves eight strict continuous-contact failures: the final
walking frame precedes the owned pot pose, and the first actual pot pose settles
by 23–33 mm during roughly the first tenth of a second. From 0.20 seconds onward,
maximum measured foot-contact error is about five micrometres. The other 72
checks pass, including pause, root immobility, natural completion and reaction
lifetime. This is a disclosed entry transition limit, not an 80/0 passing suite
or a guarantee of perfect contact throughout the action.

The gestures remain shared and restrained; foliage can hide them, and the wet
patch is subtle under rugs and shadows. The HUD may show an idle caption during
the accident message. An extra measured mop probe also exposed an existing
337 mm lower-hand reach error on both the old and acting source.

The separate mop repair now fits the rendered hips, hands and planted feet to
the unchanged shaft. Its independent critic accepts the bounded repair at
**8.5/10 for function and 7/10 visually**. A pronounced fixed bend and brisk entry
remain visible. The frozen producer tested 65 updates of the eight-minute action;
that is a sampled interval, despite its original full-duration wording. The
independent maintained-test extension measures all 80 held frames through actual
completion, pauses at a held midpoint and verifies puddle removal and prop release.
It passes **112 assertions with zero failures or engine warnings**, over fourteen
frame/age/body configurations. Maximum hand error is 14.49 mm and ankle error
4.82 mm, within the unchanged 25 mm and 12 mm limits. All 151 production inputs
match the frozen repair. Root also recorded a clean 98-assertion run before
adopting that test extension.

The independent mop review is
`dist/test-work/sanitation-mop-critic-rqvjzb0y/MOP_REACH_REVIEW.md`, SHA-256
`9a65217b095f7f36fb081796f4d1d2bd708ca6ee55aeab17ddfd24593c61697a`.
Its frozen receipt, full-duration trace and one-test handoff remain beside it.
The separate two-storey sanitation port requires combined verification because
its measured floor contact can differ from the legacy mop origin. These results
do not qualify that integration or raise the whole-game rating.
