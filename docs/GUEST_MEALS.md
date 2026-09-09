# Meals with a welcomed guest

At home, select a fresh placed serving dish and choose **Call everyone to eat**. A welcomed guest can collect one serving alongside available hungry household members. They use a free dining chair or a supported standing place, eat their actual portion, and return to the visit. The visit's original six-hour limit keeps running.

A household Lifelet eating at the same table records shared company through the existing meal system. A completed meal leaves a dirty plate that the household can wash at a sink. **Say goodbye** asks the guest to release their current plate before walking home. If no supported setdown is available, the guest retains the plate and retries after five game minutes.

The initial feature covers one invited guest, one active portion, and fresh serving dishes placed on the ground floor. It uses the existing household food ledger and physical dining reservations. It does not add a household member or a separate guest needs simulation.

## Persistence and ownership

Home-visit and food records now use version 2. Earlier version-1 visitors and household meals remain readable. A guest-owned portion binds its owner to the active visit serial and meal token; pickup changes the serving count and creates that portion once. Restore reconstructs the saved route, carrying or eating pose, and remaining progress without claiming food or advancing time.

Ordinary paused Live presentation leaves authoritative food positions unchanged. Explicit Build move/delete operations still reconcile supported placement, and resumed Live simulation continues normal reconciliation.

The installed Godot 4.7.2 decimal parser changes some full-precision serialized floats by one ULP. Checks compare the loaded authoritative ledger exactly to decoded data on disk, separately from typed physical projection. They do not claim bit-identical float round trips across the engine's JSON codec.

## Focused checks

Run `python3 tests/run_guest_meals.py` for isolated Linux gameplay checks, or add `--capture` for actual Forward+ seated and standing images. `--import-only` checks the curated dependency snapshot. The runner retains its source hashes, commands, logs, phase receipts and saves under a new ignored `dist/test-work/guest-meal-check-*` directory, using private XDG, config, cache, temporary and save directories.

Coverage includes actual Call/Welcome flow, chair and standing reservations, serving races, eligible eating time, expiry and visit deadlines, Goodbye custody and retry, exact paused fresh restore, older save versions, shared company, concurrent paid cooking, ordinary cleanup, and paused Build reconciliation. The complete-setdown-failure control supplies a temporary oversized obstruction to the real geometry queries; that artificial obstruction is removed before testing persistence of the pending custody/retry state.
