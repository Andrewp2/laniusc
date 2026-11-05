# F5 S6a: homes in the scope, lending onto `Homes` (leafA, 11-03)

Branch `leafA-s6a` from lang `bae54365e`. Builds on stage2-plan.md (sections 2.1, 2.4, 4, 5).

## What S6a was meant to hold

1. `Binding.home` in the scope, every home `None`.
2. Lending an array local to a callee without the copy (`array_arg_local`'s `element_stores` before the
   call and `element_loads` after it).
3. `ArrayCall` and `Borrowed` moved onto `Homes`.
4. `FrameCorr` gone from the simulation.

## The catch in item 2

The copy is there because the array local lives in slots. Removing the copy means the lent local lives in
its frame block for its whole scope: its `let` stores it there, and every read, index and write of it goes
through memory. That is a homed let, the S6b machinery (`HomesPush`, `HomedCorrPush`, `RefStoreV2`,
`HomesPopHome`, `HomedCorrPopHome`, homed reads only in statement positions: stage2-plan 2.2, 2.5),
restricted to arrays lent as slices. `frame_block` already reserves each lent local's bytes
(`decl_bytes uses id ty`), so the block layout is ready for it.

Doing item 2 in S6a would build the homed-let lowering and its proofs twice: once for lent arrays, and
again in S6b for borrowed locals in general. **Proposal: item 2 moves to S6b.** A lent array is a borrowed
local (`&mut a[..]` is a borrow of `a`), so S6b's homed lets cover it. The copy goes away when S6b gives the
lent local a home, and `array_arg_local` then passes the home's address.

## Decided (11-03, coordinator)

Approved: item 2 moves to S6b (recorded in SEMANTIC_DECISIONS "S6's steps"); S6a-1 with `Lent places`
as the side fact; S6a-2 folded into leafA-slots' round.

## S6a as proposed

### S6a-1 (Lean only, no regeneration): the simulation over `Homes`

The copy buffers in the caller's block are the callee's places. They are blocks in frame memory whose
bytes represent the caller's array cells, which is what `Homes` says about a home. So `Homes` can replace
`FrameCorr` while the copy stays.

- `StmtSound`, `EvalSound`, `Matches`, `Evaluates`, `Simulates` and the stops-side forms
  (`LowerStops`, `EvalStops`) take `Homes sx bud places st hp` in place of `FrameCorr sx bud places st hp`.
- Each `FrameCorr` API lemma gets a `Homes` analogue with the same name and shape, so the case proofs
  change by a rename. The API in use (uses counted 11-03):
  `unviewed` 32, `inside` 18, `below` 16, `congr` 12, `room`/`ceiling`/`bounded` 25, `holds` 9,
  `packed` 9, `small` 8, `apart` 8, `statics` 8, `congrViews` 3, `write`/`writeLE`/`low`/`lowOnly`/
  `withHeap` 9, and `frame`, `restore`, `back`, `callee`, `lend`, `start`, `nil`, `empty` once or twice each.
- The two differences that need real proofs:
  - `inside`. `FrameCorr` puts the places above the activation's block (`hp.fsp + bud.block ≤ x.address`).
    `Homes` only puts them above the frame pointer (`hp.fsp ≤ x.address`), because a function's own homes
    are in its block. A caller's lent buffers are above the callee's block. So the callee's `Homes` needs a
    fact `FrameCorr` had for free: a write to the callee's own block misses the places. The fix is to keep
    an `above` fact, `hp.fsp + bud.block ≤ x.address` for the places of the callers (all places, until S6b).
    It goes in `StmtSound` beside `under`, and `Homes.frame` / `Homes.callee` carry it.
  - `packed`. `FrameCorr.packed` says every place is a packed array passed as a slice. `Borrowed`'s slice
    code uses it 9 times. `Homes` has `sliced` and `layout`. Until S6b every place is still a lent packed
    array, so `packed` goes in the same side fact as `above`, a `Lent places` predicate:
    `∀ x ∈ places, x.Packed ∧ hp.fsp + bud.block ≤ x.address`. S6b's own homes are not `Lent`, and the
    cases that use `packed` (slice code on a lent array) then take it from the slice's place.
  - `holds`. `FrameCorr.holds` is `x.Holds sx places st hp` for every place. `Homes.holds` is age-ordered
    (`places.drop (i + 1)`). A packed array names nothing, so the two agree on lent arrays
    (`FrameCorrHomes` proves one direction; the other is the same fact for packed places).
- `FrameCorr.lean` loses `FrameCorr` and its API, but not the definition: the open statements
  `FrameCorrHomes`, `RefsLemmas` and `RefsLemmasV2` name `FrameCorr`, and statements on lang are immutable.
  The structure stays, with a note that the simulation no longer uses it. The heap lemmas in the file
  (`Heap.words`, `storeSlots`, `Addressed.view`, `LowOnly`) move to a file of their own or stay.
- `HomedSound.lean`'s `HMatches` and the `.homed`/`.plain` bridges change to `Homes` at the same time.
- `SourceCorrect`, `SourceStops`, `SourceOutcome`, `Determinism`, `Process`: `FrameCorr.start` becomes
  `Homes.start` (no homes).

Size: about 130 `FrameCorr` uses in 10 files, plus the analogues, about 40 lemmas. Lean only, so it can
merge as soon as it is green. It touches the same files as P3's case moves, so it goes before P3.

### S6a-2 (.lani, folded into leafA-slots' round): `Binding.home`

- `compiler.lani`: `Binding { id, slot, ty, home: core::option::Option<usize> }`. Every construction
  passes `None` (16 sites: `param_scope`, the lets, `arm_bind`, `arm_scope`, the views and strings).
  `lookup` is unchanged.
- `RCtx.ofScope`'s `homes` reads the homed bindings from the scope (`scopeHomes`). With every home `None`
  it is `[]`, and `RCtx.ofScope_homes` becomes a lemma, not `rfl`.
- The proofs: about 13 hand-written `Binding` constructions and every `simp` over `paramScope`, `armScope`
  and `lookup` that unfolds a binding's fields. The change is mechanical. The generated certificates
  regenerate.
- No behaviour changes, so nothing goes into SEMANTIC_DECISIONS beyond a line that the field exists and
  is `None` until S6b.

## Order

1. S6a-1 now (Lean only). Merge when green.
2. S6a-2 on top of leafA-slots, in the round after S5 (one regeneration for both).
3. S6b (leafC's lowering of borrows and homed lets, with lent arrays homed and the copy gone); P3 (my
   proof cases, including the lent-array cases that stop copying).
