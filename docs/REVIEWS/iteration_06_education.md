# Independent adversarial review — schooling and age transitions

8 September 2026. **The bounded component milestone is accepted after fixes: 62 checks passed, zero failures or runtime errors. Full-request score remains 7.0/10.** This result verifies simulation consistency; it does not establish the quality of the new school UI, child furniture poses, or a complete generational playthrough.

## Evidence and method

Critic-owned `tests/test_education_adversarial.gd` ran in a fresh isolated `/tmp/justlife-education-review-4o54mvvt` snapshot. The test uses actual `LifeSim.tick` processing, JSON save/restore, public action queue operations and target registration. Controller arrival is an explicit callback in this component test. Age-boundary fixtures place fractional progress immediately before a boundary, then cross it with actual ticks. No renderer, navigation, sound, or household-wide save controller is exercised here.

Logs, final result observations, initial/final source hashes and import output are preserved in `art/test_reports/education_iteration_06/`. The initial 49-check run found four failed assertions across three defects. A subsequent 55-check run exposed a separate birthday race. The final expanded 62-check suite was copied from current shared source into a new directory before the critic reran it independently. The developer reused the original scratch directory for an earlier fix check; its original log and source manifest remain preserved, but its overwritten result JSON is deliberately not presented as original evidence.

## Findings corrected and independently retested

1. **Expired restored classes could produce unloadable legitimate saves.** A class started at 14:00, saved partially complete at 16:30, then restored into furniture approach could linger beyond 17:00. Saving then failed its own subsequent restore validation. Clock processing now prunes the expired action; attendance and learning are not awarded.
2. **Active school could outlive its furniture.** Removing the desk or replacing its kind with a fridge still allowed the lesson to finish and award learning. Target reconciliation now cancels incompatible active schoolwork. A compatible replacement computer remains usable.
3. **Birthday cancellation could start the next unrelated action twice.** Birthday, school, homework and reading in one queue emitted two `action_started` callbacks for reading. Age-related removal is batched and starts the surviving action once.
4. **An automatic birthday could make a queued celebration skip another stage.** A teen's pending or active manual birthday remained after natural aging to young adult, then advanced again to adult. Birthday actions now retain their originating stage, and obsolete celebrations are canceled when that stage changes. Both approach and active variants pass.
5. **Birthday state changes needed atomic signals.** Static inspection found that age changed before lifecycle history was updated while queue cancellation could emit `changed`. Observers saving a Lifelet with earlier birthday history could capture a stage/history mismatch. Both automatic and manual second-stage birthdays now produce loadable states at every observed `changed` and `action_started` callback.
6. **Late enrollment could count an impossible absence.** A child becoming a teen at 18:00 previously entered secondary school for a day whose class-start deadline had already passed. The new first-class date preserves enrollment and evening homework while deferring the first attendance obligation. The 18:00 birthday and following midnight produce zero missed secondary days and a valid JSON round trip.

## Additional verified boundaries

- Automatic child→teen and teen→young-adult birthdays remove active and queued schoolwork without granting partial work benefits. Unrelated reading survives and completes; the immediately saved result reloads with matching age and school records.
- A class can start exactly 14:00 and finish 17:00. A slightly later start is refused. Reservations cannot duplicate classes at another desk.
- Midnight clears pending lessons and delayed restored homework without granting the next day's assignment. One uncompleted weekday records one absence.
- A fully missed week counts five weekdays, excludes both weekend days and yields the documented grade D/score 40. Repeated reconciliation does not duplicate penalties.
- Forging an adult school queue is rejected without modifying the current live state.

A rendered public-flow review is separate. These fixes strengthen save safety and temporal consistency without claiming that timers and validated records alone reproduce the wider family/school experience requested by the user.
