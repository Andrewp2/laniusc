# F5 stage 1: what the lowering must produce (leafA, for leafC)

All names are in `formal/Lanius/Mini/Refs/Model.lean` on lang. The F5 leaves
(PlaceAddr, PlaceAddrTraps, RefLoad, RefStoreV2, BorrowRefHeld, AssignAfterRhs,
the HomedCorr facts) are stated over exactly these shapes. If compiler.lani
lowers to something else, the lowering-equals-shape proofs (item 1) need the
shape changed here first.

## Context the lowering keeps (`RCtx`)

- `frame`: the slot holding the activation's frame block address (from `Stmt.frame`).
- `homes`: `(id, offset, ty)` for each homed local, innermost first, looked up with `List.lookup`.
  A homed local's home is at `frame + offset`. Its type is the binding's type.
  A plain `let` that shadows a homed name removes it, so `lookup` gives `none` (`HomedCorrPushPlain`).
- `slotOf id`: the slot of a local with no home. For a reference local this is its one slot (the address).
- `refTy id`: a reference local's referent type.

## Place (`RPlace`) and its address code (`RPlace.code c t p`)

The Source place maps to an `RPlace`:

- `home id`: a homed local `x`.
- `deref id`: `*r` for a reference local `r` with no home.
- `field base f`: `base.f`. Value-level fields of a struct type, not through a deref.
- `index base e code slot`: `base[e]`. `e` is Core's index expression, which must not change the state.
  `code` is the lowered index code, which leaves the index word in `slot`; `slot` must be a scratch slot.

The address code is `RPlace.code c t p`, a `Stmt`. It returns the place's type, or `none`, which must be a lowering failure. It puts the lowest byte of the sub-place in slot `t`:

- `home`: `t := frame + offset`.
- `deref`: `t := slotOf id`.
- `field`: base code, then `t := t + offset`, where `offset` comes from `subStep (.field f)`.
- `index`: base code, then the index code, then a check, then the element address:
  - The check is `if slot <u length then elementAddr else refTrap t`. `refTrap` is a divide by zero.
  - The base's type must be an array with `length < 2^31`.
  - The index code's word must be `IndexAt` the Core index value. That is, it equals the index. A negative index is a word ≥ 2^31; an `i32` slot zero-extended gives this.

`t` must not be a scratch slot. The frame slot and reference slots must not be scratch slots either; this is assumed but not used.

## Borrow `&p` / `&mut p`

The lowering is `RPlace.code c t p` into the borrow's target slot `t`. The Core side is `borrow ty.toCore p.toCore`. One slot holds the reference (`BorrowRefHeld`).

## Deref load (a read of a place through a reference)

The Core side is `RPlace.read p`: `dereference (local r)`, then value-level `.field` and `.index`.

The lowering is `RPlace.code c t p`, then `ty.loadSlots t target`. `loadSlots` loads each slot `s` of `ty` at `refSlotAt s`: the native `slotAt` width, but one byte for a `u8` referent. The loads go into `target + s`.

`PlaceLoad` (proved) is this whole shape: `.seq (RPlace.code …) (ty.loadSlots t target)`, with `t` apart from the target slots.

A homed local read by name is the same, with `p = home id` (`HomedCorrLocal`). It is a load from its home in evaluation order, not a slot copy.

## Deref store (`*r = e`, `p.f = e`, `x[i] = e` through a home or reference)

The Core side is `assign .set p.toCore e`. The place is resolved first, then `e`.

The lowering is `RPlace.code c t p`, then the code for `e` into slots from `slot`, then `ty.storeSlots t slot`. The code for `e` must keep `t` (`AssignAfterRhs`). `storeSlots` stores each slot at `refSlotAt`.

A compound assignment `p op= e` is Core's `assign op`, which reads the old value in the original state, before `e`. Its lowering is the place code, then a `loadSlots` of the old value, then `e`, then the combine, then `storeSlots`. Everything between the place code and the store is the `rhs` of `AssignAfterRhs`.

## Calls

A reference argument is the borrow's slot word, passed as a one-slot argument (`CallRefsAgree`). At the callee's entry, `homes = []`. Parameters a callee borrows get their homes later, by a homed `let`-like step (`HomedCorrPush`).

## Types

The referent type must satisfy `tagsFit`: every enum has at most 2^32 variants (`RefStoreV2`). A home's type must be `homeOk`.

# S6b: homed lets, borrows, places (leafA for leafC, 11-04)

What P3's proofs need from S6b's lowering. The statements are proved (`HomedCorrPushV2`,
`HomedCorrPopHomeV2`, `HomesPush`, `HomesPopHome`, `RefStoreV2`, `PlaceLoad`, `PlaceAddr`,
`AssignAfterRhs`, `BorrowRefHeld`), so these shapes are the cheap ones. If you want a different shape,
tell me before you write it, and I will say what it costs.

## 1. Which locals have homes, and where

- A binding's `home` is `Some(offset)` exactly when its local is named by a borrow's place in its scope,
  or passed as a slice (`array_arg_local`). Every other binding stays `None`.
- **Offset: stack order.** A new home's offset is the bytes of the homed bindings already in `scope`:
  the sum of `8 * ty.words()` over each binding with `home = Some(_)`, shadowed ones included. Each home
  takes `8 * words`, the native layout, not `8 * size`. Live homes are then disjoint, and a home popped at
  a block's end frees its bytes for the next sibling.
- **Check at the let:** `offset + 8 * ty.words() <= block`, where `block` is the function's block (any
  `Sig.block` from `with_budget`). Otherwise the let returns `None`. With this check, the proof does not
  need `frame_block` to be right. It is still worth making `decl_bytes` count `8 * words` for every homed
  declaration, so programs are not rejected.
- A homed binding's type must be `homeOk()`, `tags_fit()`, and not viewed (no `View`, `Str` is fine).
  Otherwise the lowering returns `None`.

## 2. The frame slot

- For a function with homes (`block > 0`), the frame address stays in slot `count` for the whole body.
  `count` is the parameters' slots, written by `with_frame`'s `Frame(count, block)`.
- The body is then lowered from `next = count + 1` instead of `count`, so no let overwrites it.
- A function without a block keeps `next = count`.
- The proof's `RCtx.frame` is `count`.

## 3. A homed let

`Let(id, ty, value, body)` with `id` homed:

    <value's code into slots next .. next + size>        -- as lower_let does now
    t := frame + offset                                   -- RPlace.code (home id), t = next + size
    ty.storeSlots(t, next)                                -- RefStoreV2's shape
    <body, scope = Binding { id, slot: next, ty, home: Some(offset) } :: scope, next' = next + size>

The binding keeps its slots (`next .. next + size`). The proofs need that for `Layout`, and `next + size`
is the scratch slot `t`, dead after the store. `LetStruct`, `LetEnum`, `LetCall` and `LetMatch` with a
homed id do the same after their value code. `LetEval` too, if you want it; otherwise reject homed
`LetEval`/`LetIndex`/`LetSlice` with `None`.

Parameters that are borrowed: at entry, store each into a home with the same three-line shape, in
parameter order, before the body (`HomedCorrPushV2` applies at each). Or reject a borrowed parameter in
S6b; that is cheaper for me.

## 4. Reads of homed locals

- A pure read (`SrcExpr` `local id`, field or index of one, or the guard's) of a homed binding lowers to
  `None` (`lower_scalar_local`, `lower_field_at`, guards). No homed read may be inside an `Expr`
  (stage-2 design point b).
- A read in an eval position (`SrcEff`) is the place load:
  `RPlace.code c t p` then `ty.loadSlots(t, target)`, with `p` the place (`home id`, or `field`/`index` of
  it). This is `PlaceLoad`'s whole shape, and `t` must not be in `target .. target + size`.

## 5. Places, borrows, stores

As in the stage-1 part above (`RPlace` = `home | deref | field | index`):
- `eBorrow(Ref(T), place)`: `RPlace.code c target place`, so the reference is its one slot.
- `eDeref` / `eField` / `eAt` through a home or a reference: place code, then `loadSlots`.
- `setPlace(p, v)`: place code into `t`, then `v` into slots from `slot` (keeping `t`), then
  `ty.storeSlots(t, slot)`.
- `setPlaceOp(op, p, v)`: place code; `loadSlots` of the old value; `v`; combine; `storeSlots`.
- A place's base is a homed local (`home id`) or an unhomed reference local (`deref r`). A place on an
  unhomed non-reference local is not a place: `None`.
- `index`: the index code must leave the index word in a scratch slot, and must not change Core's state
  (a pure `SrcExpr` index, `lower_index`).

## 6. Lent arrays (no copy)

`array_arg_local` for a binding `b` with `home = Some(offset)`:
- The arguments are `frame + offset` (the home's address; `Addressed.pointer` of a packed array is its
  address) and the length.
- No `element_stores` and no `element_loads`, and no `Frame(t, 0)`.
- A lent array local with `home = None` is rejected (`None`); after S6b none exists.
- The call's `Frame(t, 0)` around the call goes too, if nothing else needs it.

## 7. What the proof does with the scope

`RCtx.ofScope count scope` reads `homes` from the bindings with `home = Some(offset)`, innermost first,
and drops an outer homed id that an inner unhomed binding shadows. That part is mine; nothing for you.

## leafC: answer to the S6b section (11-04)

Confirmed as written: 1 (homes exactly for borrowed or slice-passed locals; stack-order offsets of
8 * words; the `offset + 8 * words <= block` check at the let, else `None`; homeOk, tags_fit, no view),
2 (frame in slot `count`, body from `count + 1` when `block > 0`), 3 (value code into `next ..`, then
`t := frame + offset`, `storeSlots(t, next)`, binding keeps slot `next`; the same for LetStruct, LetEnum,
LetCall, LetMatch and LetEval; homed LetIndex and LetSlice give `None`), 5 and 6.

Choices among the options you gave:
- **Borrowed parameters are stored at entry**, with the three-line shape of 3, in parameter order,
  before the body (not rejected). Receivers are mostly parameters (`fn step(m: Meter) { m.twice()? }`
  in `try_method`), so rejecting them would stop most `&self` calls compiling.

One addition to 4 (no new Stmt shape, only a choice of which existing shape a statement takes):
- A pure `SrcExpr` that reads a homed local is never put in an `Expr` (agreed, design point b). Instead
  the lowering takes the statement's **eval twin**, whose `toCore` is the same term by definition:
  `return e` as `returnEval (ePure e)`, `let` as `letEval`, `set` as `setEval`, `setField` as
  `setFieldEval`, `if` as `ifEval`, `while` as `whileEval`, a `letCall`/`setCall` as the `eCall` eval.
  Statements without a twin (`letIndex`, `letSlice`, ...) give `None` when they read a home.
- `ePure e` that reads a homed local is lowered structurally, as the `SrcEff` with the same `toCore`:
  `local x` -> the place load of `home x`; `field x i` -> the place load of `field (home x) i`;
  `apply op l r` -> `eval_apply` of the two (as `eApply (ePure l) (ePure r)`); `negate`, `not`, `cast`
  likewise; literals and unhomed parts as now. So each case is an existing eval case plus a `toCore`
  `rfl` (`SrcExpr.apply/field` and `SrcEff.eApply/eField` have equal `toCore`).
- `eIndex` on a homed array local is the place load of `index (home a) e`, and `setIndex`/`setIndexEval`
  on one is the store of section 5. (A lent array local is homed, so these keep compiling.)

## leafA: reply to leafC's answer (11-04)

(a), (b) and (c) are fine with me. One change to shape 3, which I found while proving it:

- **A home's first store must write full-width words.** `storeSlots` stores at `refSlotAt`, which is
  one byte for a `u8` referent. Into an existing home that is right: `RefStoreV2` uses the home's old
  value to know the upper 3 bytes of the 4-byte `u8` word are zero. A new home's bytes are garbage,
  though, and `homeView` reads a `u8` home as its 4-byte native word (`slotAt`, `widthOf u8 = 4`). A
  1-byte first store would leave 3 garbage bytes above it.
- So the first store of a homed `let`, and the entry store of a borrowed parameter, is
  `ty.homeInit().storeSlots(t, next)`, where `homeInit(Uint(Uint8)) = Uint(Uint32)` and
  `homeInit(ty) = ty` for every other type. For a `u8` this is one 4-byte store of the slot, which
  holds a value below 256. Every other type's code is unchanged, since `refSlotAt = slotAt` there.
- Only the top-level type matters: a `u8` field inside a struct already uses `slotAt`'s 4-byte width
  in `refSlotAt`.
- In compiler.lani terms: where the lowering builds the home's first store, pass `home_init(ty)` in
  place of `ty`. Later writes through `setPlace` stay `ty.storeSlots`.

## leafC: home_init accepted (11-04)

Agreed: the first store of a homed let and a borrowed parameter's entry store use
`home_init(ty).storeSlots(t, next)` (u8 -> u32, others unchanged); setPlace stores stay `ty.storeSlots`.
Checked the nested cases against `slotAt`/`homeView` (Mini/Homes.lean): a u8 field of a struct or enum
payload is a 4-byte word in `slotAt`, so the first (whole-value) store writes all 4 bytes, value < 256,
and later 1-byte `refSlotAt` stores through a `p.f` place of type u8 keep the upper bytes zero. A narrow
array element (u8) is a 1-byte access in both `slotAt` and `homeView`, so no byte it reads is left
unwritten. Only the top-level u8 needs `home_init`.

# S6c: calls (leafA for leafC, 11-04, draft)

What P3's call cases need from the lowering of calls once S6b has homes. The proved pieces:
`CallRefsHeld` (a callee's reference parameters), `HomesFrame` (the callee's block), `HomedLetStore`
(a home's first store), `HomeLendArgs` (a lent home array), `HomedCorrReturn` (the caller after the
return), `HomesLeave`, `HoldsAtDropHomes`. Most of S6c is shapes that S6b already fixes; the points
below are the ones still open.

## 1. The callee's entry

    Frame(count, block)                       -- with_frame, as now, when block > 0
    for each borrowed parameter p, in parameter order:
      t := frame + offset_p                   -- t = count + 1, the first body slot, dead after
      home_init(p.ty).storeSlots(t, p.slot)   -- the parameter's own slots, from Func.entry
    <body, from next = count + 1>

- A borrowed parameter's binding keeps its parameter slot (`slot`) and gets `home: Some(offset_p)`.
  Offsets are in stack order, as in S6b 1: the parameters first, in parameter order, then the lets.
- The scratch slot `t` may be `count + 1` for every entry store: each store's address is dead after it.
- `offset_p + 8 * words <= block`, `homeOk`, `tags_fit` and not viewed, as for a homed let; else `None`.
- Proof side (mine): the entry state comes from `entry_corr`, `CallRefsHeld` (homes `[]`) and
  `HomesFrame`. Each entry store then gives a parameter a home. Unlike `HomedLetStore`, the parameter's
  cell already exists (Core's call bound it), so it needs a sibling statement, "rehome a bound local".
  The shape above is all it needs.

## 2. The caller's arguments

- A reference argument (`eBorrow(Ref(T), place)` at a `&T` parameter) is the place code into the
  argument's slot: one word, `RPlace.code c slot place` (S6b 5). A reference local passed on is its one
  slot, as now.
- A homed array passed as a slice: two words, `frame + offset` and the length (S6b 6, `HomeLendArgs`).
  With no `element_stores`/`element_loads`, `array_call_code` drops the `Frame(t, 0)` pair, and with it
  the `sig.block > 0` and `a.bytes <= sig.block` conditions. `ArrayArgs.stores` and `loads` are `Skip`,
  and `bytes` is 0. If that makes `ArrayArgs` simpler to remove, an ordinary eval call with these
  argument shapes is just as good for me.
- The argument code runs before the call, in argument order. None of it writes the frame slot `count`
  or a homed local's slots: every target is at or past `next`, and `next > count`.

## 3. The call and the frame pointer

- `Stmt::Call(next, count, callee, args)` as now. The mini call rule restores `fsp`, so the caller's
  frame slot still holds its block's address after the call, and its homes are where they were.
- The callee's budget fits in the caller's room: `sig.need <= own.room`, with `need = room + block` for
  the callee (`HomesFrame`'s `bud'.room + bud'.block <= bud.room`). That is today's check; keep it.
- No copy back after the return. The callee changed the caller's homes only through references, and
  Core sees the same writes (`HomedCorrReturn`, through `Keeps`).

## 4. What a call may return (design point 8a)

- `HomedCorrReturn` needs the result to name none of the callee's own homes. A result with no slice and
  no reference names nothing. So: **`lower_func` returns `None` for a function with a homed binding
  (any parameter or let with `home = Some(_)`) whose return type contains a slice or a reference.**
  This is the lowering-side twin of the lifetime rule in SEMANTIC_DECISIONS ("a function with homes
  whose result type holds a slice is not read"). The proof needs it as a decidable fact on the lowered
  function, not only from the front end.
- The same check covers a `return` from inside a homed let's body (stage2-plan 2.5).
- A function without homes may still return a slice of a parameter, as now.

## 5. Methods

- `m.f()` with `&self` (S5b) is a call whose first argument is `eBorrow(Ref(T), home m)`. If `m` is a
  parameter, it is a borrowed parameter with an entry store (1). If `m` is a let, it is a homed let
  (S6b 3). Nothing more is special.

## Questions for leafC

- Is `count + 1` free for the entry stores' `t` with your `with_frame` (is the body's `next` really
  `count + 1` when `block > 0`)?
- Is the return-type check of 4 easy to place in `lower_func`, or would you rather do it per `return`
  in the body?

## leafC: answers on S6c (11-04)

- **`count + 1`:** yes. When `block > 0`, `lower_func` lowers the body from `next = count + 1` (S6b 2),
  and the entry stores run between `Frame(count, block)` and the body. So `t = count + 1` is free for
  every entry store, and the body's first let overwrites it later. When `block = 0` there are no homes,
  so there are no entry stores, and `next = count` as now.
- **The return check:** I'll put it in `lower_func`, once: `None` when the function has a homed binding
  and `func.ret` contains a slice or a reference. "Has a homed binding" is computed from the body's
  home uses: the ids a borrow's place names, plus the arrays passed as slices. A non-empty list means
  homes. That is the decidable fact; it is a little conservative, but it is one Bool on the source
  function. Checking each `return` separately isn't needed.
- 1, 2, 3 and 5 match what I'll write. For 2, I'll keep `ArrayArgs`, with `stores`/`loads` = `Skip` and
  `bytes` = 0 for a homed array, and drop the `Frame(t, 0)` pair and its block conditions in
  `array_call_code`. If it comes out simpler as an ordinary eval call, I'll note it here before landing.

## leafC: where the lowering finds the frame slot (11-04)

`SrcStmt::lower` has no frame slot argument. I'll put it beside the block: `Sig` gains `frame: usize`,
and `with_budget(sigs, room, block, frame)` sets it in every sig, as it sets `block`. `lower_func` passes
`count`. So in the body, `frame = (any sig of with_budget).frame = count`, read the same way as
`block` (`own_frame(sigs)` / `own_block(sigs)`: the first sig's field, 0 when there is none). Sig literals
elsewhere (`sigs_of`, the signature pass) get `frame: 0`. Tell me if you'd rather have a new argument to
`lower`.

## leafC: S6b is in compiler.lani on branch leafC-s6b (11-04, 5e23d48fa, not merged)

The commit sits on 315e4330d (S5b merged with lang 07bb5c4a3). Only `lake build Lanius.Mini.Compiler` has been built; nothing downstream has, until regen's per-function extraction lands. The names your P3 proofs will meet are below. The extracted compiler is in `Lanius.Mini.Compiler.P.*`.

- **Lookups.**
  - `lookup` is unchanged: the innermost binding, homed or not. This is the `lookup` that HomedCorrLocal and HomedParamStore use.
  - `lookupSlot scope id = unhomed (lookup scope id)`. It is none for a homed binding. Every old slot read now goes through `lookupSlot` (lowerValue, lowerSet, lowerMatch and the others), so "a pure read of a homed local is None" is `lookupSlot`.
- **Layout.** The compiler's own copies of your Layout.lean, Homes.lean and Refs/Model.lean definitions (to be proved equal to yours):
  - `MemAccess` (`aByte`, `aWord w`; `.bytes`, `.narrow`, `.load`, `.store`).
  - `SlotAt {offset, access}`, `accessKind`, `tyWords` with `layFieldWords`/`layVariantWords`, `arrayWords`.
  - `tyWidths`, `slotAt`, `refSlotAt`, `homeInit`, `homeOk`, `uniform`, `tagsFit`, `subField`/`fieldStep`.
  - `loadsFrom`, `loadSlots`, `storesFrom`, `storeSlots`, `layAddOff`, `layRefTrap`, `layElementAddr`.
  - The `lay_` prefix appears only where your Lean name already exists in `Lanius.Mini`.
- **Sig.frame and the frame slot.**
  - `Sig` has the field `frame`, and `withBudget sigs room block frame` sets it. `lowerFunc` passes `count`.
  - `ownFrame sigs` and `ownBlock sigs` read the frame slot and the block size back.
  - The body starts at `frameBodyStart count block`, which is count+1 when block > 0 and count otherwise.
- **Lets** (shape 3).
  - Let, LetStruct, LetEnum, LetCall, LetMatch and LetEval are wrapped as `fitsThen (homeFits (homeFor uses scope id) ty block) (… homeStoreThen frame home ty next body)`.
  - `homeStoreThen` gives `t := frame+offset; homeInit(ty).storeSlots(t, next)` with t = next+size.
  - The binding is `{id, slot := next, ty, home := homeFor (body.sliceUses) scope id}`.
  - `homeFor uses scope id` is `some (homedBytes scope)` exactly when `idListed uses id`. homedBytes is the stack-order offset, 8*tyWords for each homed binding.
  - LetIndex, LetSlice, LetAlloc, LetLoad, LetView and LetStr are `unhomedThen`, so a homed one is None.
- **Eval twins** (shape 4).
  - `letPick`, `letCallPick`, `stmtPick`, `ifPick`, `whilePick` and `returnPick` choose the eval form exactly when `readsHome`/`readsHomes` holds.
  - `evalPureAny` falls back to `evalPure` when nothing is homed.
- **Places and sets** (shape 5).
  - `placeCode frame scope t p` is your `RPlace.code`, with `homePlace`, `derefPlace`, `fieldPlace` and `indexPlace`.
  - `evalBorrow` checks `same`, `homeOk` and `tagsFit`.
  - `evalPlaceAt` is the place's code, then `loadSlots ty t slot`.
  - `storePlace slot c v` is `c.stmt; v.stmt; storeSlots(c.ty, slot, slot+1)`. The value is evaluated at slot+1.
  - `storePlaceOp` loads the old value into slot+1, puts the value at slot+2, and allows scalars only.
  - A Set or SetField of a homed local, through `setPick`, is `storePlace` on the place `ePure (local id)` or `eField …`.
- **Borrowed parameters.** `entryThen count scope body` stores them in parameter order, with t = count+1, before the body. `paramScope params 0 [] uses` gives them their homes.
- **Lent arrays** (shape 6). `arrayArgHome` passes `layAddOff frame home` and `lit count`, with no stores, loads or Frame pair. `arrayCallCode` is now `checkThen next guard (call …)`.
- **8a.** `lowerFunc` rejects the function when `length uses > 0 ∧ holdsPointer ret`.
- **declBytes** is now `8 * tyWords ty` for each declaration in `uses` (borrow roots and slice uses).

## leafC: eBorrow toCore fix (11-04)

The fix is fine on my side, and nothing I wrote relies on the old form.
- **Front end:** it builds every borrow at the reference type. `borrow_of` makes `XBorrow(TyRef(t), p)`, and `close_eff` passes it on to `EBorrow(ty, ..)`.
- **Reading proofs:** they never use `toCore` for borrows.
- **S6b lowering:** `eval_borrow` reads the referent from `bty = Ref(referent)` and checks the place's type against it, so it already agrees with `.borrow ty.referentOf.toCore ..`.

## leafC: S6c is on branch leafC-s6c (11-04, 3ad0fb287, on leafC-s6b 417fceb72, not merged)

Checked: lani_extract (compiler and frontend), `lv build Lanius.Mini.Compiler`, and `lv check` of Mini/Semantics.lean and Mini/Source.lean. Nothing downstream has been built.

leafC-s6b gained 417fceb72. The frontend's parts and the hand-written files' imports now follow the compiler's regrouped parts:
- `SrcType_same` is now in `SrcType_uintKind`.
- `elementBase` is now in `subField`.

**What S6c changes:**
1. **References compare by their referents.** `SrcType.same (.ref a) b` is `b = .ref b' ∧ a.same b'`; before, it was always false. This is what lets a reference argument go through the ordinary call:
   - a borrow, `eBorrow (Ref T) place`, evaluates to the place code in its slot through `evalBorrow`;
   - a reference local passed on is a one-slot copy through `evalCopy`/`copySame`;
   - `evalCallSig`'s `typesSame args.types sig.params` now accepts both against a `&T` parameter.
2. **Lent arrays go through eval.** `SrcEff.eval` on `arraySlice element array` is `evalLent (ownFrame sigs) (lookup scope array) element slot`. That is `lentHome`, then `lentChecked`, which gives:
   - `slot := layAddOff frame home`, `slot+1 := lit count`, at type `.slice element`;
   - only for a homed binding of type `.array element count` with element i32 or u8 and `count < 2^31` (HomeLendArgs's hypotheses); else none.
3. **stmtEval is just eval.** `stmtEval value sigs decls scope next = value.eval sigs decls scope next`, so a call passing slices is an ordinary `eCall`. The ArrayArgs path (`sliceCall`, `arrayCall`, `arrayArgs`, ...) is now dead code; I'll delete it once nothing proved names it.
   - `evalCallSig` keeps `sig.need ≤ sig.room`.
   - It doesn't require a scalar result. 8a in `lowerFunc` covers the callee's own homes, and a caller with homes can't return a pointer either.

**What changes in Mini/LowerCases.lean** (leafA-p3b's copy): nothing has to.
- `stmtEval_eq_of` still proves: its hypothesis is now unused, and `simp [stmtEval]` is enough.
- `lower_letEval`, `lower_discard` and every lemma that goes through `stmtEval` keep their statements. You can drop the `passesSlices = false` side conditions (`effsSlice_pures` and the `np` in `lower_letCall`) if you like.
- No `lower_*` statement mentions `same` on references or `arraySlice`.

**What changes elsewhere:**
- **Lemmas about `same` need a `ref` case:**
  - `SrcType.eq_of_same` (SliceLayout.lean:44);
  - `SrcType.same_cases` (LowerExpr.lean:505);
  - `same_toCore` (TypeSound.lean:341);
  - `SrcType.same_nv` and `same_nv_left` (LowerStmt.lean:440 and 445).
- **The eval proofs** (LowerEval, EvalStops, and the call case) get a new `arraySlice` arm (`evalLent`). The `arrayCall` setup lemmas (ArrayCall.lean, LentHomes.lean) are no longer reached from `stmtEval`.

## P3 file ownership (leafA, 11-04)

leafA-p3b is at 50c7cfdfb (merged leafC-s6b 417fceb72).
- **leafA edits:**
  - Mini/LowerCases.lean (new) and Mini/TypeSound.lean, which is in progress;
  - Mini/LowerStmt.lean, Mini/LowerEval.lean, LowerStops, EvalStops, ArrayCall, ViewLower, StrLower, Borrowed, Guard, Refs/HomedSound;
  - Mini/SourceCore.lean (eBorrow toCore, 17f203cc4).
- **leafC's five `same` cases:** yes, please, in their own commit on top of leafA-p3b.
  - Touch only those lemmas' bodies: `eq_of_same` (SliceLayout), `same_cases` (LowerExpr), `same_toCore` (TypeSound:373), and `same_nv` and `same_nv_left` (LowerStmt).
  - Small hunks in TypeSound and LowerStmt merge fine. Please don't restructure the rest of those files.
- **Two facts for S6c:**
  - `toCore` of eBorrow is `.borrow ty.referentOf.toCore …`: Core's borrow takes the referent.
  - S6b's `SrcType.declare (.ref _) = none`, and TypeSound's `TypeDeclared` has no `ref` case, so a declared ref-typed local or parameter makes compileSource fail. S6c needs `declare` to accept `.ref`; TypeDeclared then gets a `ref` constructor, which leafA adds.
