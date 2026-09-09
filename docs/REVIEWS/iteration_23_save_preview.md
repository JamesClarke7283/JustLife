# Save previews after closing a panel

9 September 2026. Saving immediately after closing a drawn adoption review could put the canceled review in the save thumbnail. A later save could similarly retain the overwrite-confirmation screen. The household itself saved correctly.

`capture_save_preview()` now redraws the current scene before reading its image, using a zero frame step and no buffer swap. Saving still returns its final result synchronously. The save writer, slot ownership, storage format and headless path are unchanged. This costs one immediate render at an existing preview-capture site.

The maintained `tests/run_save_preview.py --capture` reproduces the problem in a private two-adult household through public creator and panel callbacks. It cancels the drawn review and saves without an intervening process tick. The unchanged baseline has **35 checks and four expected thumbnail failures**. The repaired Forward+ run has **35 checks and zero failures, errors or warnings**. Its four PNGs exactly match the settled Live crop; the baseline errors were 0.459 for direct/save-as-new/overwrite and 0.300 for the subsequent save. The expected Live PNG is byte-identical between runs. Root inspected the wrong thumbnail, the corrected home thumbnail and the real final save picker.

Both runs preserve the clock, funds, transforms, appearance, family, queues and meal ledger. This fixture's queues and meal ledger are empty; it does not repeat paid-cooking custody tests. Overwriting retains the selected slot, and deleting then immediately saving a new slot does not recreate the deleted save or preview. Callbacks are scripted, not native pointer input.

The baseline headless run passes 18 checks cleanly. The fixed headless run passes the same 18 state checks but retains an intermittent two-ObjectDB shutdown warning; the strict runner correctly reports failure for that warning. Initial fixture failures from an unsettled shared pause also remain recorded. The final fixture settles the normal pause with a zero-time app tick before asserting unchanged state. No runtime warning suppression or relaxed image tolerance was introduced.

Evidence is retained at `dist/test-work/save-preview-source-ljzunwho/handoff/HANDOFF.md`. The frozen handoff SHA-256 is `f9e12bbc9f8c6f62b192ce4aa178b623790ec59fd8f9acea5224647cc36aa634`; its comparison receipt is `566e5aba33a7d352453d2f3a2b97eb25a08a2ea597632e27f4033e4a96bf6dd6`. Integrated `scripts/main.gd` matches the reviewed hash `37bd57064fa1bd5975abe292daca9e23377fe722c268938b24742d75ff4bb898`.

**Decision:** accept the bounded preview correction. This adds no new full-game rating or cross-platform qualification. Packaged verification is recorded separately in [release verification](../RELEASE_VERIFICATION.md).
