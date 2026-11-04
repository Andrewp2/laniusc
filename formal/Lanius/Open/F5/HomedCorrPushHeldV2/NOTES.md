# HomedCorrPushHeldV2

- 11-03 (leafA): HomedCorrPushPlainV2 with its `RefTo` hypothesis derived from `HoldsAt` (stage 1's `HoldsAt.ref`):
  a value that is a reference is held only at `.ref referent`, by `RefHeld`, whose `RefTo` is at `referent`.

11-03 (leafA): replaces `HomedCorrPushHeld` (deleted), whose binding `⟨id, next, ty⟩` stopped
elaborating when `Binding` gained `home` (S6a-2). The binding has any home here.
