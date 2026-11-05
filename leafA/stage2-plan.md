# F5 stage 2: `compileSource_correct` with homes (leafA, 11-03)

A plan for the proof that `compileSource` stays correct once stage 1's S6 gives it the reference
lowering. It is written against `lowering-spec.md` (same directory). It changes no `.lani` file.
New lemmas are open statements under `formal/Lanius/Open/F5/` (section 7).

## 1. Where the induction is today

- `sound_both` (`Mini/LowerEval.lean:4736`) proves `StmtSound sp mp fuel ∧ EvalSound sp mp fuel` by strong
  induction on Core's fuel.
  - One case lemma per `SrcStmt` constructor: the `stmt_*` lemmas in `LowerStmt.lean`, `ViewLower.lean` and
    `StrLower.lean`.
  - One case lemma per `SrcEff` constructor (`eval_*` in `LowerEval.lean`).
- `body_sound` and `call_sound` (`LowerStmt.lean:1290`, `:1375`) close a call. At entry they use
  `entry_corr` and `bodyStart`. At return they use `Matches.returned`, `restoreLocals` and `FrameCorr.back`.
- `compileSource_correct_from` (`SourceCorrect.lean:190`) is `body_sound` at the entry function, with
  `FrameCorr.start` and `places = []`.
- The stops side (`SourceStops`, `StopsCorrect`) runs the same invariant through `LowerStops.lean` and
  `EvalStops.lean`.

The invariant threaded through every case is:

    Corr sx places scope frame st env      -- every binding's value in its slots
    Layout scope frame base next, st.Fresh, base ≤ st.nextCell
    HeapCorr st.heap st.world hp
    FrameCorr sx bud places st hp           -- places = the caller's lent packed arrays
    ∀ x ∈ places, x.cell < base

The conclusion is `Simulates`: `Fresh`, `Keeps places base st st'`, and an `Exec` whose outcome `Matches`.
`Matches` repeats `Corr`, `HeapCorr` and `FrameCorr` for `next`, `broke` and `continued`, and gives
`RetHolds` against `places` for `returned`.

## 2. The new invariant

Replace `Corr` by `HomedCorr` and `FrameCorr` by `Homes`:

    HomedCorr sx places scope frame c st env   -- c : RCtx, from the scope (2.1)
    Layout scope frame base next, st.Fresh, base ≤ st.nextCell
    HeapCorr st.heap st.world hp
    Homes sx bud places st hp                   -- places = all live homes, youngest first
    ∀ x ∈ places, x.cell < st.nextCell          -- was `< base`: see 2.3

`Matches` carries the same pair, `HomedCorr` and `Homes`, in `next`, `broke` and `continued`. `returned`
keeps `RetHolds sx places ret v bits`, against the current places, which include the function's own homes.
`Simulates` keeps `Keeps places base st st'` unchanged. `Keeps` already exempts the homes' cells, and
writes through references only reach homes.

### 2.1 Where `c : RCtx` comes from (a spec point for leafC)

Recommendation: the lowering keeps homed-ness in the scope, `Binding.home : Option Nat` (the home's offset
in the frame block). The context is then a function of the scope:

    RCtx.ofScope (frameSlot : Nat) (scope : List Binding) : RCtx
      frame  := frameSlot
      homes  := the (id, offset, ty) of the homed bindings, innermost first
      slotOf := fun id => (lookup scope id).slot
      refTy  := fun id => referent of (lookup scope id).ty

With this definition:
- `c.homes.lookup id` agrees with `lookup scope id`, shadowing included. The context hypotheses of
  `HomedCorrPushPlain`, `HomedCorrPushHeld` and `HomedCorrPush` (`c'.homes.lookup id = none`, `c'` is `c`
  elsewhere, `c'.slotOf id = next`, `c'.refTy id = referent`) are then lemmas about `ofScope`.
- `HomedCorr.homedTy` (a home's type is its binding's type) holds by construction.
- `StmtSound`'s quantifiers do not grow: `c` is not a new variable.

If leafC keeps a separate `RCtx` beside the scope, `StmtSound` takes `c` and the five agreement
hypotheses instead. The case proofs are the same.

### 2.2 Reads must say which kind of local they read

`HomedCorr.values` holds only for unhomed bindings. So a pure read (`SrcExpr.local id`, lowered to
`.var slot`) needs `Unhomed places frame b` for the binding it reads. The lowering must:
- lower `.local id` to a slot read only when `(lookup scope id).home = none`;
- lower a homed local's read, and every dereference, to `PlaceLoad`'s statement shape (place code, then
  `loadSlots` into a temporary). That is a statement prefix, so these reads happen only where the lowering
  emits statements: the eval path, `SrcEff`, or a let head. Never inside a pure `SrcExpr` that becomes an
  `Expr`.

`lowerAs_some`, `lowerValue_sound` and the guards then get `home = none` from the lowering's success. They
turn it into `Unhomed` with `HomedCorr.unhomed`.

### 2.3 `under` and `Keeps` across homed lets

A homed let creates its home's cell at `st.nextCell`, which is at least `base`, inside the statement being
simulated. So `∀ x ∈ places, x.cell < base` fails for the let body's places, `x :: places`. It is
replaced by `x.cell < st.nextCell`, the hypothesis `HomedCorrPush` and `HomedCorrPushPlain` already take.

Inside, the body's `Keeps (x :: places) base` is the outer `Keeps places base`, because `x.cell ≥ base`
(`KeepsConsAbove`). Every use of `under` is a `Keeps`/`FrameCorr.below` fact about cells below `base`, so it
moves to `HomedCorr.below`. That is `Corr.below`'s analogue, from `Layout` and `Fresh`.

### 2.4 Calls

- **Arguments.** A reference argument's word holds at `.ref ty` (`BorrowHoldsAt`). Its arguments'
  `FieldsHold` give the callee's `RefsAgree` (`CallRefsHeld`).
- **Callee entry.** The steps are:
  1. `entry_corr` gives `Corr` at the callee's entry.
  2. `HomedCorrOfCorr` with `c.homes = []` turns it into `HomedCorr`.
  3. The callee's places are the caller's places. Lent arrays are homes already (`HomesLend`), so there
     is no `arrayPlaces` and no copy.
  4. `HomesFrame` places the callee's block below the caller's homes.
- **The callee's own homes** are pushed and popped by its homed lets (2.5). At its return the places are
  `own ++ caller places`.
- **Return.** `HomedCorrReturn` gives three things:
  - the caller's `HomedCorr` at the state after the call (`HomedCorrKeeps`, since the callee wrote only
    homes);
  - the caller's `Homes` with the frame pointer back (`HomesLeave`);
  - the result held against the caller's homes (`HoldsAtDropHomes`).
  The last needs the result to name none of `own`. That is the open design point 8a.
- `call_sound`'s `restoreLocals` and `FrameCorr.back` become `HomedCorrReturn`. The copy-back of lent
  arrays (`ArrayCall`'s loads) is deleted, as point 7 of SEMANTIC_DECISIONS "References: the memory model"
  says.

### 2.5 Homed lets, loops, and returns from inside a block

- **A homed let:**
  1. `HomesPush` and `HomedCorrPush` add the home.
  2. The initial value is stored with `storeSlots` into the home (`RefStoreV2`, then `HomesCongrV2`).
  3. The body runs at `x :: places` (the induction hypothesis, since `StmtSound` quantifies `places`).
  4. At the block's end, `HomesPopHome` and `HomedCorrPopHome` drop the home. Their `¬ Names x.cell`
     hypotheses come from the lifetime rule (8a).
- **A loop** whose body binds a homed local pushes and pops each iteration. `HomesPopHome`'s second half
  gives the next iteration the same block.
- **A `return` from inside a homed let's body** gives `Matches.returned` at `x :: places`. The let case
  turns it into `Matches.returned` at `places` with `HoldsAtDropHomes`. It needs the returned value to name
  none of `x`: 8a again. `HoldsAtNamesPlaces` reduces that to "the value names only the caller's places".
- **A plain let** uses `HomedCorrPushHeld` (its `RefTo` hypothesis from `HoldsAt.ref`) and
  `HomedCorrPopPlain`.

## 3. The new construct cases

| Source form | Mini shape (`lowering-spec.md`) | Core lemma | Mini lemma | Invariant after |
|---|---|---|---|---|
| `&p`, `&mut p` | `RPlace.code c t p` | CoreBorrow | BorrowHoldsAt (PlaceAddr) | HomedCorrPushHeld / CallRefsHeld |
| read of `*r`, `r.f`, `x` homed | `.seq (RPlace.code …) (ty.loadSlots t target)` | CoreRead, CorePlace | PlaceLoad, HomedCorrLocal | HomedCorrEnvCongr (temps only) |
| `p = e` | place code; `e`; `storeSlots` | CoreAssign | AssignAfterRhs, RefStoreV2 | HomedCorrCellsCongr (unhomed cells kept), HomesCongrV2 |
| `p op= e` | place code; `loadSlots`; `e`; op; `storeSlots` | CoreAssignOp | AssignAfterRhs | as `p = e` |
| a trapping place | place code up to `refTrap` | CorePlace | PlaceAddrTraps | stops side |
| `let x = e` with `x` borrowed | store into the home | — | HomesPush, HomedCorrPush, RefStoreV2 | HomedCorrPopHome, HomesPopHome at block end |
| call with `&p` arguments | argument words from `RPlace.code` | — | CallRefsHeld, HomesFrame | HomedCorrReturn |

The machine side is unchanged (`RefCodeWithin` and `RefCodeRuns`: the new code is `Stmt.within`, so
`compileStmt_correct` applies as it is).

## 4. The existing cases: a mechanical move

The cases that do not touch references move from `Corr` to `HomedCorr` through the API lemmas below. Each
`Corr.X` gets a `HomedCorr` analogue, and the case proofs change where they call these lemmas:

| `Corr` API (file:line) | `HomedCorr` analogue | status |
|---|---|---|
| `Corr.local`, `Corr.cellId` (LowerExpr:149,154) | `HomedCorrLocal` | proved |
| `Corr.env_congr` (LowerStmt:433) | `HomedCorrEnvCongr` | **new statement** |
| `Corr.cells_congr`, `sameCells` (LowerStmt:503,518) | `HomedCorrCellsCongr` | **new statement** |
| `Corr.keeps`, `Corr.after` (LowerStmt:525, LowerEval:185) | `HomedCorrKeeps` + `HomedCorrEnvCongr` | proved + new |
| `Corr.push` / `Corr.pop` (LowerStmt:546,596) | `HomedCorrPushHeld` / `HomedCorrPopPlain` | proved |
| `Corr.assign` (LowerStmt:1497) | `HomedCorrAssignPlain` | **new statement** |
| `Corr.alias`, `Corr.pushView` (LowerStmt:2053, ViewLower) | the same with `Unhomed` | in the files' move |
| `entry_corr` (LowerStmt:1145) | `entry_corr` + `HomedCorrOfCorr` + `CallRefsHeld` | proved parts |
| (functions with no homes) | `HomedCorrToCorr`: `HomedCorr` + scope apart from places ⇒ `Corr` | **new statement** |

Uses of `Corr`'s fields directly (counted 11-03): `.values` 30, `.apart` 34, `.unviewed` 40, `.viewed` 13,
`.locals` 19. Each `.values`, `.unviewed` and `.viewed` site gets an `Unhomed` argument from 2.2. The
`.apart` sites (lent arrays apart from locals) get theirs from `Unhomed` too.

`HomedCorrToCorr` gives the bridge for the move's first step (6, P2). While no function has a home, every
binding is unhomed, so the old case proofs can run unchanged inside the new `StmtSound`, through the
bridge. P3 then removes the bridge.

## 5. Files that change

| File | lines | `Corr sx` / `FrameCorr` occurrences | change |
|---|---|---|---|
| `Mini/LowerStmt.lean` | 5309 | 111 / 47 | `StmtSound`, `Matches`, `Simulates`, every `stmt_*`, `body_sound`, `call_sound`, the `Corr` API |
| `Mini/LowerEval.lean` | 4881 | 79 / 44 | `EvalSound`, `sound_both`, the `eval_*` cases; new eval cases for loads through places |
| `Mini/LowerStops.lean` | 2790 | 23 / 11 | the stops-side analogue of `StmtSound` |
| `Mini/EvalStops.lean` | 2653 | 25 / 11 | the stops-side analogue of `EvalSound` |
| `Mini/ArrayCall.lean` | 957 | 12 / 7 | lending without a copy: `arrayPlaces` becomes homes (`HomesLend`); the copy-in and copy-out go |
| `Mini/Borrowed.lean` | 375 | 8 / 9 | the callee's slice code against `Homes` (the general `HoldsAt.borrowed` of S2's note) |
| `Mini/ViewLower.lean`, `StrLower.lean` | 715, 433 | 10, 5 / 4, 4 | `Corr`→`HomedCorr` (views and strings are never homes) |
| `Mini/FrameCorr.lean` | 472 | — | deleted once nothing uses it (point 7); `FrameCorrHomes` is its bridge until then |
| `Mini/LowerExpr.lean` | 1310 | 3 / 1 | `Corr` stays as the no-homes special case (`HomedCorrToCorr`), or goes |
| `Mini/Guard.lean`, `Progress.lean` | 638, 787 | 1, 4 / 0 | signatures |
| `Mini/SourceCorrect.lean`, `SourceStops.lean`, `SourceOutcome.lean`, `Determinism.lean`, `Process.lean` | — | 0 / 1 each | `FrameCorr.start` → `Homes` with no homes |
| `Mini/Refs/*` | — | — | consumers only: the leaves above are stated over these definitions |

`compileStmt_correct` and the whole machine side (`CompileCorrect`, `Simulation`, x86) are untouched.

## 6. Order of work (each step keeps every top theorem proved)

- **P1, now, Lean only.** Prove the new open statements in section 7. None depends on S3 or S6 shapes.
- **P2, with S6a.** S6a is leafC's first S6 step: `Binding.home` or a context, every `home = none`, and
  lent arrays as homes without the copy.
  - Restate `StmtSound`, `EvalSound`, `Matches` and `Simulates` over `HomedCorr` and `Homes`.
  - Prove the new forms from the old proofs through `HomedCorrToCorr`, `HomedCorrOfCorr` and
    `FrameCorrHomes`.
  - Move `ArrayCall` and `Borrowed` onto `Homes`, and delete `FrameCorr`.
  - `compileSource`'s behaviour is unchanged apart from the lending.
- **P3, with S6b** (homed lets, borrows, dereference reads and assignments).
  - Move the case proofs to `HomedCorr` directly (section 4's table).
  - Add the new cases (section 3).
  - From here, `HomedCorrToCorr` is used only for functions without homes, if at all.
- **P4, with S6c** (reference arguments): `call_sound` with `CallRefsHeld`, `HomedCorrKeeps` and
  `HomedCorrReturn`.
- **P5.** The stops side (`LowerStops`, `EvalStops`) with `PlaceAddrTraps`.
- **P6.** `SourceRefsCorrect` from `compileSource_correct` (no `noRefs` left).

If S6 lands in one step, P2–P4 are one change, and stage 1's temporary `noRefs` hypothesis covers the gap.

## 7. New open statements (stated with this plan)

All are in `formal/Lanius/Open/F5/`, over existing definitions:
- `HomedCorrToCorr`: `HomedCorr` with every scope binding apart from the places is `Corr`.
- `HomedCorrEnvCongr`: `HomedCorr` survives an `env'` that agrees on the scope's slots, the frame slot and
  the unhomed reference locals' slots.
- `HomedCorrCellsCongr`: `HomedCorr` survives a state with the same locals and views, whose unviewed
  unhomed bindings' cells are as they were, and whose views hold. A write through a reference changes only
  homes, so this is the invariant after it.
- `HomedCorrAssignPlain`: `Corr.assign` for an unhomed binding of a non-reference type.
- `HoldsAtNamesPlaces`: a held value names only the places' cells (`Value.Names cell → ∃ x ∈ places,
  x.cell = cell`).
- `KeepsConsAbove`: `Keeps (x :: places) base` is `Keeps places base` when `base ≤ x.cell`.

Already proved and used here: `HomedCorrOfCorr`, `HomedCorrLocal`, `HomedCorrKeeps`, `HomedCorrPush`,
`HomedCorrPopHome`, `HomedCorrPushPlain`, `HomedCorrPushHeld`, `HomedCorrPopPlain`, `HomesPopHome`,
`HoldsAtDropHomes`, `HomedCorrReturn`, `CallRefsAgree`, `CallRefsHeld`, `BorrowRefHeld`, `BorrowHoldsAt`,
`AssignAfterRhs`, `PlaceLoad`, `PlaceAddr`, `PlaceAddrTraps`, `RefLoad`, `RefStoreV2`, `RefCodeWithin`,
`RefCodeRuns`, and RefsLemmasV2's leaves (`HomesPush`, `HomesFrame`, `HomesLeave`, `HomesLend`,
`FrameCorrHomes`, `HomesCongrV2`, Core*).

## 8. Open design points (for the coordinator and leafC)

a. **What a return may name.** `HoldsAtDropHomes` needs the returned value to name none of the dying homes.
   F5 already rejects reference results. A slice result can still name a home: for example, a function with
   a borrowed local array that returns a slice of it. Proposal: S5's lifetime check rejects a function that
   has homes and returns a type containing a slice, unless the slice comes from a parameter.
   - The proof gets the fact from a decidable check on the lowered function: "its return type has no
     slice, or it has no homes".
   - Then `HoldsAtNamesPlaces` with the caller's places closes it.
   - The same check covers a `return` from inside a homed let (2.5).
   - Outer locals naming a popped home (`HomedCorrPopHome`'s hypothesis) need the same rule for lets
     holding slices of inner homes. Point 9 of SEMANTIC_DECISIONS "References: the memory model" lists
     this rule.
b. **Homed reads only in statement positions** (2.2). The lowering must never put a homed local's read or
   a dereference into a pure `Expr`.
c. **`Binding.home`** versus a separate context (2.1). `Binding.home` makes the context hypotheses
   definitional.
d. **`under`** changes from `< base` to `< st.nextCell` (2.3). This is internal to the proof; nothing in
   the compiler changes.
