# PreCompileWords

- 11-03 (leafA): red4 is red3 with FrontEndStmtDepthV2 (`depth <= 2 ^ 40`, the front end's check) in place of
  FrontEndStmtDepth.
- 11-03 (leafB): red5 is red4 with PreCompileSourceV4 (V3 is probably false, V3/NOTES.md) and leafA's
  FrontEndParamSlots for V4's parameter premise.
- 11-04 (leafA): red6 is red5 with PreCompileSourceV5 (V4 lacks `nb p ≤ M` and the slot-nesting premise,
  V4/NOTES.md) and the two front-end statements for V5's new premises, FrontEndSlotNest and
  FrontEndNumbersSmall (both to be proved from front-end checks `lim_nest`/`lim_nums`, queued).
