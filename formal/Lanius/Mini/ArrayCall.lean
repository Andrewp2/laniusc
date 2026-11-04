module

public import Lanius.Mini.LowerStmt
import all Lanius.Mini.Compiler.P.BinOp_folds
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.Expr_agrees
import all Lanius.Mini.Compiler.P.FArith_opcode
import all Lanius.Mini.Compiler.P.FloatTy_rex
import all Lanius.Mini.Compiler.P.Instr_pieces
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.UintTy_mask
import all Lanius.Mini.Compiler.P.Word_compute
import all Lanius.Mini.Compiler.P.Word_narrows
import all Lanius.Mini.Compiler.P.applyGuard
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.arithUint
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.armBodyScope
import all Lanius.Mini.Compiler.P.armPayload
import all Lanius.Mini.Compiler.P.armScope
import all Lanius.Mini.Compiler.P.assignFrom
import all Lanius.Mini.Compiler.P.binaryConstant
import all Lanius.Mini.Compiler.P.callAgrees
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.compileModules
import all Lanius.Mini.Compiler.P.conjunction
import all Lanius.Mini.Compiler.P.consArgs
import all Lanius.Mini.Compiler.P.declareFuncs
import all Lanius.Mini.Compiler.P.declareProgram
import all Lanius.Mini.Compiler.P.elementAddress
import all Lanius.Mini.Compiler.P.elementBase
import all Lanius.Mini.Compiler.P.enumVariants
import all Lanius.Mini.Compiler.P.equality
import all Lanius.Mini.Compiler.P.evalDivide
import all Lanius.Mini.Compiler.P.evalDivideSint
import all Lanius.Mini.Compiler.P.evalNot
import all Lanius.Mini.Compiler.P.evalSame
import all Lanius.Mini.Compiler.P.extentAfter
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.guardAnd
import all Lanius.Mini.Compiler.P.hostRandomCode
import all Lanius.Mini.Compiler.P.evalHost
import all Lanius.Mini.Compiler.P.roomFits
import all Lanius.Mini.Compiler.P.linkedSize
import all Lanius.Mini.Compiler.P.importOk
import all Lanius.Mini.Compiler.P.importsOk
import all Lanius.Mini.Compiler.P.indexOf
import all Lanius.Mini.Compiler.P.iteThen
import all Lanius.Mini.Compiler.P.killShared
import all Lanius.Mini.Compiler.P.leftTrue
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.longer
import all Lanius.Mini.Compiler.P.lowerAddress
import all Lanius.Mini.Compiler.P.lowerApply
import all Lanius.Mini.Compiler.P.lowerBody
import all Lanius.Mini.Compiler.P.lowerCallSig
import all Lanius.Mini.Compiler.P.lowerLoadType
import all Lanius.Mini.Compiler.P.lowerLocal
import all Lanius.Mini.Compiler.P.lowerReturn
import all Lanius.Mini.Compiler.P.lowerSetCallArgs
import all Lanius.Mini.Compiler.P.lowerSetValues
import all Lanius.Mini.Compiler.P.lowerShift
import all Lanius.Mini.Compiler.P.lowerSlice
import all Lanius.Mini.Compiler.P.lowerTagged
import all Lanius.Mini.Compiler.P.matchDst
import all Lanius.Mini.Compiler.P.matchVariants
import all Lanius.Mini.Compiler.P.moduleExports
import all Lanius.Mini.Compiler.P.moduleFirsts
import all Lanius.Mini.Compiler.P.modulesOk
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.repeatType
import all Lanius.Mini.Compiler.P.shortCircuit
import all Lanius.Mini.Compiler.P.withBudget
import all Lanius.Mini.Compiler.P.funcNeeds
import all Lanius.Mini.Compiler.P.sintToUint
import all Lanius.Mini.Compiler.P.storeArray
import all Lanius.Mini.Compiler.P.strStores
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.bindingBytes
import all Lanius.Mini.Compiler.P.needRound
import all Lanius.Mini.Compiler.P.needsAfter
import all Lanius.Mini.Compiler.P.storeEvalWord
import all Lanius.Mini.Compiler.P.storeType
import all Lanius.Mini.Compiler.P.storeWordElement
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.substAll
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.widthOf
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.wordStride
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.Types

/-! # Calls that pass arrays as slices (step 3.5 of array-to-slice arguments)

A statement-level call passing array locals at `[T]` parameters
(`array_call`, SEMANTIC_DECISIONS "Addressed locals"): the caller stores each
array into its block of frame memory in the slice layout, passes the
block's address and the length, and loads the elements back after the
return. In the callee the arrays are places (`arrayPlaces`), held by
`FrameCorr`; Core's call writes the arrays' cells through the slices, and
the loads bring the new values into the caller's slots. -/

@[expose] public section

namespace Lanius.Mini

variable {bud : Budget} {sx : Statics} {places : List Addressed}

open Lanius.Core (Value)
open Lanius.Semantics (State Cell Completion evalExpr evalExprs execStmt restoreLocals)

/-! ## The block's addresses -/

theorem blockAt_eval {env : Env} {t pos A : Nat} (at_ : (env t).toNat = A) (small : A + pos < 2 ^ 64) :
    ((blockAt t pos).eval env).toNat = A + pos := by
  simp only [blockAt, Expr.eval, Word.apply, BinOp.apply, BitVec.toNat_add, at_, BitVec.toNat_ofNat]
  rw [Nat.mod_eq_of_lt (by omega : pos < 2 ^ 64)]
  exact Nat.mod_eq_of_lt small

theorem lowByte_toNat (v : BitVec 64) : (lowByte v).toNat = v.toNat % 256 := by
  simp [lowByte, BitVec.toNat_setWidth, UInt8.toNat_ofNat]

/-! ## Storing and loading an array's elements -/

/-- The stores of `count` elements from `slot` on into the block at `pos`,
`width` (4 or 1) bytes apart: each element's low `width` bytes, nothing
outside, the limit, cursor, trace, frame pointer and top unchanged. -/
theorem elementStores_exec {mp : Program} {d width t A : Nat} (wide : width = 4 ∨ width = 1) :
    ∀ (count pos slot : Nat) {env : Env} {hp : Heap}, (env t).toNat = A → A + pos + width * count ≤ hp.top →
      A + pos + width * count < 2 ^ 64 →
      ∃ hp', Exec mp d env hp (elementStores width t pos slot count) (.normal env hp') ∧
        (∀ i < count, hp'.readLE (A + pos + width * i) width = (env (slot + i)).toNat % 256 ^ width) ∧
        (∀ a, a < A + pos ∨ A + pos + width * count ≤ a → hp'.bytes a = hp.bytes a) ∧
        hp'.limit = hp.limit ∧ hp'.cursor = hp.cursor ∧ hp'.io = hp.io ∧ hp'.fsp = hp.fsp ∧ hp'.top = hp.top := by
  intro count
  induction count with
  | zero =>
    intro pos slot env hp _ _ _
    refine ⟨hp, ?_, fun i lt => absurd lt (Nat.not_lt_zero _), fun _ _ => rfl, rfl, rfl, rfl, rfl, rfl⟩
    rw [elementStores, if_pos rfl]
    exact .skip
  | succ count ih =>
    intro pos slot env hp at_ room small
    rw [elementStores, if_neg (Nat.add_one_ne_zero _), Nat.add_sub_cancel]
    have addr := blockAt_eval (pos := pos) at_ (by omega)
    -- the first store
    obtain ⟨hp1, first, read1, outside1, limit1, cursor1, io1, fsp1, top1⟩ :
        ∃ hp1, Exec mp d env hp (blockStore width t pos slot) (.normal env hp1) ∧
          hp1.readLE (A + pos) width = (env slot).toNat % 256 ^ width ∧
          (∀ a, a < A + pos ∨ A + pos + width ≤ a → hp1.bytes a = hp.bytes a) ∧
          hp1.limit = hp.limit ∧ hp1.cursor = hp.cursor ∧ hp1.io = hp.io ∧ hp1.fsp = hp.fsp ∧ hp1.top = hp.top := by
      rcases wide with rfl | rfl
      · have e : Exec mp d env hp (.storeWord .m32 (blockAt t pos) (.var slot))
            (.normal env (hp.writeLE ((blockAt t pos).eval env).toNat ((Expr.var slot).eval env).toNat
              MemWidth.m32.bytes)) := .storeWord (by rw [addr]; simp only [MemWidth.bytes]; omega)
        rw [addr] at e
        simp only [Expr.eval, MemWidth.bytes] at e
        refine ⟨_, ?_, Heap.readLE_writeLE _ _ _ _, fun a out => Heap.writeLE_bytes_outside _ _ _ _ _ (by omega),
          (Heap.writeLE_limit _ _ _ _).1, (Heap.writeLE_limit _ _ _ _).2, Heap.writeLE_io _ _ _ _,
          (Heap.writeLE_top _ _ _ _).2, (Heap.writeLE_top _ _ _ _).1⟩
        rw [blockStore, if_pos rfl]
        exact e
      · have e : Exec mp d env hp (.storeByte (blockAt t pos) (.var slot))
            (.normal env (hp.write ((blockAt t pos).eval env).toNat (lowByte ((Expr.var slot).eval env)))) :=
          .storeByte (by rw [addr]; omega)
        rw [addr] at e
        refine ⟨hp.write (A + pos) (lowByte ((Expr.var slot).eval env)), ?_, ?_, fun a out => ?_,
          rfl, rfl, rfl, rfl, rfl⟩
        · rw [blockStore, if_neg (by decide)]
          exact e
        · simp only [Expr.eval, Heap.readLE, Heap.write_bytes, if_true, lowByte_toNat]
          omega
        · rw [Heap.write_bytes, if_neg (by omega)]
    obtain ⟨hp2, rest, read2, outside2, limit2, cursor2, io2, fsp2, top2⟩ :=
      ih (pos + width) (slot + 1) (env := env) (hp := hp1) at_ (by rw [top1]; rw [Nat.mul_succ] at room; omega)
        (by rw [Nat.mul_succ] at small; omega)
    refine ⟨hp2, .seq first rest, fun i lt => ?_, fun a out => ?_, limit2.trans limit1, cursor2.trans cursor1,
      io2.trans io1, fsp2.trans fsp1, top2.trans top1⟩
    · cases i with
      | zero =>
        simp only [Nat.mul_zero, Nat.add_zero]
        rw [Heap.readLE_congr fun a lo hi => outside2 a (.inl (by omega))]
        exact read1
      | succ i =>
        have := read2 i (by omega)
        rw [show A + (pos + width) + width * i = A + pos + width * (i + 1) by rw [Nat.mul_succ]; omega,
          show slot + 1 + i = slot + (i + 1) by omega] at this
        exact this
    · rw [outside2 a (by rw [Nat.mul_succ] at out; omega), outside1 a (by rw [Nat.mul_succ] at out; omega)]

/-- The loads of `count` elements into `slot` on from the block at `pos`,
`width` (4 or 1) bytes apart: each slot gets its element's bytes, the
other slots are unchanged, and so is the heap. -/
theorem elementLoads_exec {mp : Program} {d width t A : Nat} (wide : width = 4 ∨ width = 1) :
    ∀ (count pos slot : Nat) {env : Env} {hp : Heap}, (env t).toNat = A → (t < slot ∨ slot + count ≤ t) →
      A + pos + width * count ≤ hp.top → A + pos + width * count < 2 ^ 64 →
      ∃ env', Exec mp d env hp (elementLoads width t pos slot count) (.normal env' hp) ∧
        (∀ i < count, env' (slot + i) = BitVec.ofNat 64 (hp.readLE (A + pos + width * i) width)) ∧
        (∀ j, (j < slot ∨ slot + count ≤ j) → env' j = env j) := by
  intro count
  induction count with
  | zero =>
    intro pos slot env hp _ _ _ _
    refine ⟨env, ?_, fun i lt => absurd lt (Nat.not_lt_zero _), fun _ _ => rfl⟩
    rw [elementLoads, if_pos rfl]
    exact .skip
  | succ count ih =>
    intro pos slot env hp at_ away room small
    rw [elementLoads, if_neg (Nat.add_one_ne_zero _), Nat.add_sub_cancel]
    have addr := blockAt_eval (pos := pos) at_ (by omega)
    obtain ⟨env1, first, here1, same1⟩ :
        ∃ env1, Exec mp d env hp (blockLoad width t pos slot) (.normal env1 hp) ∧
          env1 slot = BitVec.ofNat 64 (hp.readLE (A + pos) width) ∧ ∀ j, j ≠ slot → env1 j = env j := by
      rcases wide with rfl | rfl
      · have e : Exec mp d env hp (.loadWord .m32 slot (blockAt t pos))
            (.normal (env.set slot (BitVec.ofNat 64 (hp.readLE ((blockAt t pos).eval env).toNat MemWidth.m32.bytes)))
              hp) := .loadWord (by rw [addr]; simp only [MemWidth.bytes]; omega)
        rw [addr] at e
        refine ⟨env.set slot (BitVec.ofNat 64 (hp.readLE (A + pos) 4)), ?_, by simp [Env.set],
          fun j ne => by simp [Env.set, ne]⟩
        rw [blockLoad, if_pos rfl]
        exact e
      · have e : Exec mp d env hp (.loadByte slot (blockAt t pos))
            (.normal (env.set slot (BitVec.ofNat 64 (hp.bytes ((blockAt t pos).eval env).toNat).toNat)) hp) :=
          .loadByte (by rw [addr]; omega)
        rw [addr] at e
        refine ⟨env.set slot (BitVec.ofNat 64 (hp.bytes (A + pos)).toNat), ?_, by simp [Env.set, Heap.readLE],
          fun j ne => by simp [Env.set, ne]⟩
        rw [blockLoad, if_neg (by decide)]
        exact e
    have at1 : (env1 t).toNat = A := by rw [same1 t (by omega)]; exact at_
    obtain ⟨env2, rest, here2, same2⟩ :=
      ih (pos + width) (slot + 1) (env := env1) (hp := hp) at1 (by omega)
        (by rw [Nat.mul_succ] at room; omega) (by rw [Nat.mul_succ] at small; omega)
    refine ⟨env2, .seq first rest, fun i lt => ?_, fun j out => ?_⟩
    · cases i with
      | zero =>
        rw [Nat.add_zero, same2 slot (.inl (Nat.lt_succ_self _)), here1, Nat.mul_zero, Nat.add_zero]
      | succ i =>
        have := here2 i (by omega)
        rw [show A + (pos + width) + width * i = A + pos + width * (i + 1) by rw [Nat.mul_succ]; omega,
          show slot + 1 + i = slot + (i + 1) by omega] at this
        exact this
    · rw [same2 j (by omega), same1 j (by omega)]


/-! ## The arguments -/

/-- What `arrayArgs` gives for one more argument: a pure value before the
rest, or an array local passed as a slice, its block before the rest's. -/
theorem arrayArgs_cons {scope : List Binding} {arg : SrcEff} {rest : List SrcEff} {ty : SrcType}
    {more : List SrcType} {t offset : Nat} {a : ArrayArgs}
    (ok : arrayArgs scope (arg :: rest) (ty :: more) t offset = some a) :
    (∃ e vs r, arg = .ePure e ∧ lowerValue scope e ty = some vs ∧
      arrayArgs scope rest more t offset = some r ∧
      a = { stores := r.stores, args := vs ++ r.args, loads := r.loads, guard := guardAnd (e.guard scope) r.guard,
            bytes := r.bytes, ids := r.ids }) ∨
    (∃ element id b r, arg = .arraySlice element id ∧ lookup scope id = some b ∧
      arrayArgs scope rest more t (offset + 8 * b.ty.size) = some r ∧
      0 < packedWidth element ∧ b.ty = .array element b.ty.size ∧ ty = .slice element ∧
      b.ty.size < 2147483648 ∧ idAbsent r.ids id = true ∧
      a = { stores := .seq (elementStores (packedWidth element) t offset b.slot b.ty.size) r.stores,
            args := blockAt t offset :: .lit (BitVec.ofNat 64 b.ty.size) :: r.args,
            loads := .seq (elementLoads (packedWidth element) t offset b.slot b.ty.size) r.loads,
            guard := r.guard, bytes := 8 * b.ty.size + r.bytes, ids := id :: r.ids }) := by
  simp only [arrayArgs] at ok
  cases arg
  case ePure e =>
    left
    simp only [arrayArg, arrayArgPure] at ok
    split at ok
    · simp at ok
    rename_i vs hv
    split at ok
    · simp at ok
    rename_i r hr
    simp only [Option.some.injEq] at ok
    exact ⟨e, vs, r, rfl, hv, by simpa [argBytes] using hr, ok.symm⟩
  case arraySlice element id =>
    right
    simp only [arrayArg, arrayArgSlice] at ok
    split at ok
    · simp at ok
    rename_i b found
    simp only [arrayArgLocal] at ok
    split at ok
    · simp at ok
    rename_i r hr
    simp only [arrayArgChecked] at ok
    split at ok
    · rename_i checks
      simp only [Bool.and_eq_true, decide_eq_true_eq] at checks
      obtain ⟨⟨⟨⟨w, arr⟩, sl⟩, small⟩, absent⟩ := checks
      simp only [Option.some.injEq] at ok
      exact ⟨element, id, b, r, rfl, found, by simpa [argBytes, bindingBytes, found] using hr, w,
        SrcType.same_eq arr, SrcType.same_eq sl, small, absent, ok.symm⟩
    · simp at ok
  all_goals simp [arrayArg] at ok

theorem idAbsent_not_mem : ∀ {ids : List Nat} {id : Nat}, idAbsent ids id = true → id ∉ ids
  | [], _, _ => by simp
  | other :: rest, id, h => by
    simp only [idAbsent, Bool.and_eq_true, decide_eq_true_eq] at h
    simp only [List.mem_cons, not_or]
    exact ⟨fun e => h.1 e.symm, idAbsent_not_mem h.2⟩

/-- An element passed: an `i32` in 4 bytes or a `u8` in 1. -/
theorem packedWidth_cases {element : SrcType} (pos : 0 < packedWidth element) :
    (element = .i32 ∧ packedWidth element = 4) ∨ (element = .uint .uint8 ∧ packedWidth element = 1) := by
  by_cases h1 : SrcType.same element .i32 = true
  · exact .inl ⟨SrcType.same_eq h1, by simp [packedWidth, h1]⟩
  · by_cases h2 : SrcType.same element (.uint .uint8) = true
    · exact .inr ⟨SrcType.same_eq h2, by simp [packedWidth, h1, h2]⟩
    · simp [packedWidth, h1, h2] at pos

/-- The place an argument lends its callee: an array local passed as a
slice, its block at `offset` in the block at `A`. -/
def argPlaces (scope : List Binding) (frame : Nat → Nat) (A offset : Nat) : SrcEff → List Addressed
  | .ePure _ => []
  | .eCall _ _ => []
  | .eApply _ _ _ => []
  | .eNeg _ => []
  | .eNot _ => []
  | .eCast _ _ => []
  | .eIndex _ _ => []
  | .eStruct _ _ => []
  | .eVariant _ _ _ => []
  | .eMatch _ _ _ _ _ => []
  | .eDivide _ _ _ => []
  | .eStride _ => []
  | .arraySlice _ id => (lookup scope id).toList.map fun b => ⟨frame b.slot, [], b.ty, A + offset, true⟩
  | .eIf _ _ _ _ => []
  | .eLet _ _ _ _ _ => []
  | .eLen _ => []
  | .eStr _ _ => []
  | .eBorrow _ _ => []
  | .eDeref _ _ => []
  | .eField _ _ => []
  | .eAt _ _ => []

/-- The places a call's arguments lend, their blocks from `offset` in the
block at `A` on. -/
def arrayPlaces (scope : List Binding) (frame : Nat → Nat) (A : Nat) : List SrcEff → Nat → List Addressed
  | [], _ => []
  | arg :: rest, offset => argPlaces scope frame A offset arg ++ arrayPlaces scope frame A rest (offset + argBytes scope arg)

/-- The places lent: packed arrays of the scope's bindings passed, in their
blocks within the arguments' bytes, one after another, with different
cells. -/
theorem arrayPlaces_shape {scope : List Binding} {frame : Nat → Nat} {base next : Nat}
    (fr : Layout scope frame base next) {A t : Nat} :
    ∀ {args : List SrcEff} {types : List SrcType} {offset : Nat} {a : ArrayArgs},
      arrayArgs scope args types t offset = some a →
      (∀ x ∈ arrayPlaces scope frame A args offset, x.Packed ∧ x.ty.size < 2 ^ 31 ∧
        (∃ b ∈ scope, x.cell = frame b.slot ∧ x.ty = b.ty ∧ b.id ∈ a.ids) ∧
        A + offset ≤ x.address ∧ x.address + 8 * x.ty.size ≤ A + offset + a.bytes) ∧
      (arrayPlaces scope frame A args offset).Pairwise
        (fun x y => x.cell ≠ y.cell ∧ x.address + 8 * x.ty.size ≤ y.address) := by
  intro args
  induction args with
  | nil =>
    intro types offset a ok
    cases types with
    | nil => exact ⟨fun x mem => by simp [arrayPlaces] at mem, by simp [arrayPlaces]⟩
    | cons => simp [arrayArgs] at ok
  | cons arg rest ih =>
    intro types offset a ok
    cases types with
    | nil => simp [arrayArgs] at ok
    | cons ty more =>
      rcases arrayArgs_cons ok with ⟨e, vs, r, rfl, -, hr, rfl⟩ |
        ⟨element, id, b, r, rfl, found, hr, w, bty, -, small, absent, rfl⟩
      · simp only [arrayPlaces, argPlaces, argBytes, List.nil_append, Nat.add_zero]
        exact ih hr
      · obtain ⟨all, pairwise⟩ := ih hr
        have bmem := lookup_mem found
        simp only [arrayPlaces, argPlaces, argBytes, bindingBytes, found, Option.toList_some, List.map_cons,
          List.map_nil, List.cons_append, List.nil_append]
        refine ⟨fun x mem => ?_, List.pairwise_cons.mpr ⟨fun y ymem => ?_, pairwise⟩⟩
        · rcases List.mem_cons.mp mem with rfl | there
          · refine ⟨⟨rfl, rfl, element, b.ty.size, bty, ?_⟩, small, ⟨b, bmem.1, rfl, rfl, by simp [bmem.2]⟩,
              Nat.le_refl _, by simp only; omega⟩
            rcases packedWidth_cases w with ⟨h, -⟩ | ⟨h, -⟩
            · exact .inl h
            · exact .inr h
          · obtain ⟨packed, sz, ⟨b', b'mem, cell, ty', ids⟩, lo, hi⟩ := all x there
            exact ⟨packed, sz, ⟨b', b'mem, cell, ty', List.mem_cons_of_mem _ ids⟩, by omega, by omega⟩
        · obtain ⟨-, -, ⟨b', b'mem, cell, -, ids⟩, lo, -⟩ := all y ymem
          refine ⟨fun same => ?_, by simp only; omega⟩
          have eq := fr.inj b bmem.1 b' b'mem (by rw [← cell]; exact same)
          subst eq
          exact idAbsent_not_mem absent (bmem.2 ▸ ids)

/-- A packed array place's slot `s`: its element's `w` bytes, `w * s`
above the address. -/
theorem Addressed.view_packed {x : Addressed} (sliced : x.sliced = true) {element : SrcType} {n w : Nat}
    (ty : x.ty = .array element n) (el : (element = .i32 ∧ w = 4) ∨ (element = .uint .uint8 ∧ w = 1))
    (hp : Heap) (s : Nat) : x.view hp s = BitVec.ofNat 64 (hp.readLE (x.address + w * s) w) := by
  rcases el with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
  · rw [x.view_i32 sliced ty, x.pointer_i32 ty]
  · rw [x.view_u8 sliced ty, x.pointer_u8 ty, Nat.one_mul]

/-- The slots of an array of `i32` or `u8` hold no more bits than an
element's bytes. -/
theorem replicate_small {element : SrcType} {w : Nat}
    (el : (element = .i32 ∧ w = 4) ∨ (element = .uint .uint8 ∧ w = 1)) {n : Nat} {vs : List Value} {E : Env}
    {slot : Nat} (h : FieldsHold sx places (List.replicate n element) vs E slot) :
    ∀ i < n, (E (slot + i)).toNat < 256 ^ w := by
  intro i lt
  have len := h.length
  rw [List.length_replicate] at len
  obtain ⟨v, found⟩ : ∃ v, vs[i]? = some v := ⟨vs[i], List.getElem?_eq_getElem (by omega)⟩
  have held := fieldsHold_replicate_get h found
  rcases el with ⟨rfl, rfl⟩ | ⟨rfl, rfl⟩
  · simp only [SrcType.size, Nat.mul_one] at held
    obtain ⟨-, bits⟩ := (SrcType.holdsAt_scalar (by rfl)).mp held
    rw [bits]
    simp only [widen, BitVec.toNat_setWidth]
    have := (low (E (slot + i))).isLt
    omega
  · simp only [SrcType.size, Nat.mul_one] at held
    obtain ⟨-, bits⟩ := (SrcType.holdsAt_scalar (by rfl)).mp held
    simpa [UintTy.width] using bits

/-- Core's slice of an array local: of the whole array in its cell. -/
theorem arraySlice_run {scope frame st E} {prog : Core.Program} (corr : Corr sx places scope frame st E) {id : Nat}
    {b : Binding} (found : lookup scope id = some b) {element : SrcType} {n : Nat} (ty : b.ty = .array element n)
    {fuel : Nat} {core : Core.Ty} {v : Value} {st' : State}
    (run : evalExpr fuel prog st (.arrayToSlice core (.local id)) = .done v st') :
    st' = st ∧ v = .slice core (frame b.slot) [] 0 n := by
  cases fuel with
  | zero => simp [evalExpr] at run
  | succ fuel =>
    cases fuel with
    | zero => simp [evalExpr, Semantics.expressionPlace?, Semantics.evalPlace] at run
    | succ fuel =>
      obtain ⟨vb, place, holds⟩ := corr.readPlace found fuel prog
      rw [ty] at holds
      cases holds with
      | array elems =>
        simp only [evalExpr, Semantics.expressionPlace?, place, Semantics.Outcome.done.injEq] at run
        refine ⟨run.2.symm, ?_⟩
        rw [← run.1, elems.length, List.length_replicate]

/-- The arguments: Core's evaluation changes nothing, the checks pass, and
the values are in the arguments' slots, an array passed as the slice of its
lent place. -/
theorem arrayArgs_sound {scope frame st E} {prog : Core.Program} (corr : Corr sx places scope frame st E)
    (target : prog.target = .x86_64) {A t : Nat} :
    ∀ {args : List SrcEff} {types : List SrcType} {offset : Nat} {a : ArrayArgs} {fuel : Nat} {vs : List Value}
      {st' : State}, arrayArgs scope args types t offset = some a →
      evalExprs fuel prog st (SrcEff.toCoreList args) = .done vs st' →
      st' = st ∧ a.args.length = sizes types ∧ a.guard.eval E = 1 ∧
      ((E t).toNat = A → A + offset + a.bytes < 2 ^ 64 → ∀ {places' : List Addressed},
        (∀ x ∈ places, x ∈ places') → (∀ x ∈ arrayPlaces scope frame A args offset, x ∈ places') →
        FieldsHold sx places' types vs (Func.entry (Expr.evalAll E a.args)) 0) := by
  intro args
  induction args with
  | nil =>
    intro types offset a fuel vs st' ok run
    cases types with
    | cons => simp [arrayArgs] at ok
    | nil =>
      simp only [arrayArgs, Option.some.injEq] at ok
      subst ok
      cases fuel with
      | zero => simp [evalExprs] at run
      | succ fuel =>
        simp only [SrcEff.toCoreList, evalExprs, Semantics.Outcome.done.injEq] at run
        obtain ⟨rfl, rfl⟩ := run
        exact ⟨rfl, rfl, rfl, fun _ _ _ _ _ => .nil⟩
  | cons arg rest ih =>
    intro types offset a fuel vs st' ok run
    cases types with
    | nil => simp [arrayArgs] at ok
    | cons ty more =>
    cases fuel with
    | zero => simp [evalExprs] at run
    | succ fuel =>
    simp only [SrcEff.toCoreList, evalExprs] at run
    split at run
    rotate_left
    all_goals try (simp at run; done)
    rename_i v mid argRun
    split at run
    rotate_left
    all_goals try (simp at run; done)
    rename_i rvs fin restRun
    simp only [Semantics.Outcome.done.injEq] at run
    obtain ⟨rfl, rfl⟩ := run
    rcases arrayArgs_cons ok with ⟨e, xs, r, rfl, hv, hr, rfl⟩ |
      ⟨element, id, b, r, rfl, found, hr, w, bty, tyEq, small, absent, rfl⟩
    · have g := lowerValue_guard corr target hv argRun
      obtain ⟨rfl, flat, -⟩ := lowerValue_sound corr target hv argRun
      obtain ⟨rfl, len, g', holds⟩ := ih hr restRun
      refine ⟨rfl, by simp [sizes, len, flat.length], guardAnd_one g g', fun at_ room places' sub lent => ?_⟩
      have restHolds := holds at_ room sub fun x mem => lent x (by
        simpa [arrayPlaces, argPlaces, argBytes] using mem)
      have lenAll := evalAll_length E xs
      refine .cons ?_ ?_
      · refine (flat.holds.mono sub).congr fun i below => ?_
        simp only [evalAll_append, Nat.zero_add]
        rw [entry_append_left _ _ (by rw [lenAll, flat.length]; exact below)]
      · refine restHolds.congr_all fun i => ?_
        simp only [evalAll_append, Nat.zero_add]
        rw [← flat.length, ← lenAll, entry_append_right]
    · subst tyEq
      obtain ⟨rfl, rfl⟩ := arraySlice_run corr found bty argRun
      obtain ⟨rfl, len, g', holds⟩ := ih hr restRun
      refine ⟨rfl, by simp [sizes, len, SrcType.size]; omega, g', fun at_ room places' sub lent => ?_⟩
      have restHolds := holds at_ (by simp only at room; omega) sub fun x mem => lent x (by
        simp only [arrayPlaces, argPlaces, argBytes, bindingBytes, found, Option.toList_some, List.map_cons,
          List.map_nil, List.cons_append, List.nil_append]
        exact List.mem_cons_of_mem _ mem)
      have here : (⟨frame b.slot, [], b.ty, A + offset, true⟩ : Addressed) ∈ places' := lent _ (by
        simp [arrayPlaces, argPlaces, found])
      have el : element = .i32 ∨ element = .uint .uint8 := by
        rcases packedWidth_cases w with ⟨h, -⟩ | ⟨h, -⟩
        · exact .inl h
        · exact .inr h
      have pointer : (⟨frame b.slot, [], b.ty, A + offset, true⟩ : Addressed).pointer = A + offset := by
        rcases el with rfl | rfl
        · exact Addressed.pointer_i32 (x := ⟨frame b.slot, [], b.ty, A + offset, true⟩) bty
        · exact Addressed.pointer_u8 (x := ⟨frame b.slot, [], b.ty, A + offset, true⟩) bty
      refine .cons (.borrowed here rfl rfl bty el ?_ ?_ small) ?_
      · simp only [Expr.evalAll, Func.entry, List.getD_cons_zero, pointer]
        exact blockAt_eval at_ (by simp only at room; omega)
      · simp only [Expr.evalAll, Func.entry, Nat.zero_add, List.getD_cons_succ, List.getD_cons_zero, Expr.eval,
          BitVec.toNat_ofNat]
        omega
      · refine restHolds.congr_all fun i => ?_
        simp [Expr.evalAll, Func.entry, SrcType.size, Nat.add_comm 2 i]


/-! ## The stores and the loads -/

/-- The stores put each array lent into its block in the slice layout,
where it represents the array's value; nothing outside the arguments'
bytes changes. -/
theorem arrayStores_exec {mp : Program} {d : Nat} {scope frame st E} (corr : Corr sx places scope frame st E)
    {A t : Nat} (at_ : (E t).toNat = A) :
    ∀ {args : List SrcEff} {types : List SrcType} {offset : Nat} {a : ArrayArgs} {hp : Heap},
      arrayArgs scope args types t offset = some a → A + offset + a.bytes ≤ hp.top → A + offset + a.bytes < 2 ^ 64 →
      ∃ hp', Exec mp d E hp a.stores (.normal E hp') ∧
        (∀ c, c < A + offset ∨ A + offset + a.bytes ≤ c → hp'.bytes c = hp.bytes c) ∧
        hp'.limit = hp.limit ∧ hp'.cursor = hp.cursor ∧ hp'.io = hp.io ∧ hp'.fsp = hp.fsp ∧ hp'.top = hp.top ∧
        ∀ x ∈ arrayPlaces scope frame A args offset, ∀ places', x.Holds sx places' st hp' := by
  intro args
  induction args with
  | nil =>
    intro types offset a hp ok _ _
    cases types with
    | cons => simp [arrayArgs] at ok
    | nil =>
      simp only [arrayArgs, Option.some.injEq] at ok
      subst ok
      exact ⟨hp, .skip, fun _ _ => rfl, rfl, rfl, rfl, rfl, rfl, fun x mem => by simp [arrayPlaces] at mem⟩
  | cons arg rest ih =>
    intro types offset a hp ok room small
    cases types with
    | nil => simp [arrayArgs] at ok
    | cons ty more =>
    rcases arrayArgs_cons ok with ⟨e, xs, r, rfl, -, hr, rfl⟩ |
      ⟨element, id, b, r, rfl, found, hr, w, bty, -, -, -, rfl⟩
    · obtain ⟨hp', exec, out, limit, cursor, io, fsp, top, holds⟩ := ih hr room small
      exact ⟨hp', exec, out, limit, cursor, io, fsp, top, fun x mem => holds x (by
        simpa [arrayPlaces, argPlaces, argBytes] using mem)⟩
    · have el := packedWidth_cases w
      have wide : packedWidth element = 4 ∨ packedWidth element = 1 := by
        rcases el with ⟨-, h⟩ | ⟨-, h⟩
        · exact .inl h
        · exact .inr h
      have wn : packedWidth element * b.ty.size ≤ 8 * b.ty.size :=
        Nat.mul_le_mul_right _ (by rcases wide with h | h <;> omega)
      simp only at room small
      obtain ⟨hp1, e1, read1, out1, l1, c1, io1, f1, t1⟩ :=
        elementStores_exec (mp := mp) (d := d) wide b.ty.size offset b.slot (env := E) (hp := hp) at_
          (by omega) (by omega)
      obtain ⟨hp2, e2, out2, l2, c2, io2, f2, t2, holds2⟩ :=
        ih hr (hp := hp1) (by rw [t1]; omega) (by omega)
      refine ⟨hp2, .seq e1 e2, fun c out => ?_, l2.trans l1, c2.trans c1, io2.trans io1, f2.trans f1, t2.trans t1,
        fun x mem places' => ?_⟩
      · simp only at out
        rw [out2 c (by omega), out1 c (by omega)]
      · simp only [arrayPlaces, argPlaces, argBytes, bindingBytes, found, Option.toList_some, List.map_cons,
          List.map_nil, List.cons_append, List.nil_append] at mem
        rcases List.mem_cons.mp mem with rfl | there
        · obtain ⟨v, entry, held⟩ := corr.values b (lookup_mem found).1
          have tyx : (⟨frame b.slot, [], b.ty, A + offset, true⟩ : Addressed).ty = .array element b.ty.size := bty
          have read : Semantics.readCellProjection st (frame b.slot) [] = .ok v := by
            simp [Semantics.readCellProjection, entry, Semantics.projectedValue]
          rw [bty] at held
          cases held with
          | array elems =>
            refine ⟨_, read, ?_⟩
            have scalar : element.isScalar = true := by
              rcases el with ⟨rfl, -⟩ | ⟨rfl, -⟩ <;> rfl
            rw [tyx]
            refine .array ((fieldsHold_replicate_scalar scalar elems).congr fun i lt => ?_)
            have lt' : i < b.ty.size := by
              rw [sizes_replicate] at lt
              rcases el with ⟨rfl, -⟩ | ⟨rfl, -⟩ <;> simpa [SrcType.size] using lt
            rw [Nat.zero_add, Addressed.view_packed rfl tyx el]
            simp only
            rw [Heap.readLE_congr fun c lo hi => out2 c (.inl (by
                have := Nat.mul_le_mul_left (packedWidth element) (Nat.succ_le_of_lt lt')
                rw [Nat.mul_succ] at this
                omega)),
              read1 i lt', Nat.mod_eq_of_lt (replicate_small el elems i lt')]
            simp
        · exact holds2 x there places'

/-- The loads bring each lent array's slots back from its block; no other
slot changes. -/
theorem arrayLoads_exec {mp : Program} {d : Nat} {scope : List Binding} {frame : Nat → Nat} {base next : Nat}
    (fr : Layout scope frame base next) {A t : Nat} (tAbove : next ≤ t) :
    ∀ {args : List SrcEff} {types : List SrcType} {offset : Nat} {a : ArrayArgs} {E : Env} {hp : Heap},
      arrayArgs scope args types t offset = some a → (E t).toNat = A →
      A + offset + a.bytes ≤ hp.top → A + offset + a.bytes < 2 ^ 64 →
      ∃ E', Exec mp d E hp a.loads (.normal E' hp) ∧
        (∀ x ∈ arrayPlaces scope frame A args offset, ∃ b ∈ scope, x.cell = frame b.slot ∧ x.ty = b.ty ∧
          ∀ i < b.ty.size, E' (b.slot + i) = x.view hp i) ∧
        (∀ j, (∀ x ∈ arrayPlaces scope frame A args offset, ∀ b ∈ scope, x.cell = frame b.slot →
          j < b.slot ∨ b.slot + b.ty.size ≤ j) → E' j = E j) := by
  intro args
  induction args with
  | nil =>
    intro types offset a E hp ok _ _ _
    cases types with
    | cons => simp [arrayArgs] at ok
    | nil =>
      simp only [arrayArgs, Option.some.injEq] at ok
      subst ok
      exact ⟨E, .skip, fun x mem => by simp [arrayPlaces] at mem, fun _ _ => rfl⟩
  | cons arg rest ih =>
    intro types offset a E hp ok at_ room small
    cases types with
    | nil => simp [arrayArgs] at ok
    | cons ty more =>
    have shape := (arrayPlaces_shape fr (A := A) ok).2
    rcases arrayArgs_cons ok with ⟨e, xs, r, rfl, -, hr, rfl⟩ |
      ⟨element, id, b, r, rfl, found, hr, w, bty, -, -, -, rfl⟩
    · obtain ⟨E', exec, loaded, same⟩ := ih hr at_ room small
      exact ⟨E', exec, fun x mem => loaded x (by simpa [arrayPlaces, argPlaces, argBytes] using mem),
        fun j away => same j fun x mem => away x (by simpa [arrayPlaces, argPlaces, argBytes] using mem)⟩
    · have el := packedWidth_cases w
      have wide : packedWidth element = 4 ∨ packedWidth element = 1 := by
        rcases el with ⟨-, h⟩ | ⟨-, h⟩
        · exact .inl h
        · exact .inr h
      have wn : packedWidth element * b.ty.size ≤ 8 * b.ty.size :=
        Nat.mul_le_mul_right _ (by rcases wide with h | h <;> omega)
      have bmem := (lookup_mem found).1
      have slots := fr.slots b bmem
      simp only at room small
      obtain ⟨E1, e1, here1, same1⟩ :=
        elementLoads_exec (mp := mp) (d := d) wide b.ty.size offset b.slot (env := E) (hp := hp) at_
          (.inr (by omega)) (by omega) (by omega)
      have at1 : (E1 t).toNat = A := by rw [same1 t (.inr (by omega))]; exact at_
      obtain ⟨E2, e2, loaded2, same2⟩ := ih hr (hp := hp) at1 (by omega) (by omega)
      simp only [arrayPlaces, argPlaces, argBytes, bindingBytes, found, Option.toList_some, List.map_cons,
        List.map_nil, List.cons_append, List.nil_append, List.pairwise_cons] at shape ⊢
      refine ⟨E2, .seq e1 e2, fun x mem => ?_, fun j away => ?_⟩
      · rcases List.mem_cons.mp mem with rfl | there
        · refine ⟨b, bmem, rfl, rfl, fun i lt => ?_⟩
          rw [same2 _ fun y ymem b' b'mem cell => ?_, here1 i lt,
            Addressed.view_packed (x := ⟨frame b.slot, [], b.ty, A + offset, true⟩) rfl bty el]
          have ne : b ≠ b' := fun eq => (shape.1 y ymem).1 (by rw [cell, ← eq])
          rcases fr.apart b bmem b' b'mem ne with h | h <;> omega
        · exact loaded2 x there
      · rw [same2 j fun x mem => away x (List.mem_cons_of_mem _ mem)]
        exact same1 j (away _ (List.mem_cons_self ..) b bmem rfl)

theorem pairwise_either {α : Type} {R : α → α → Prop} :
    ∀ {l : List α}, l.Pairwise R → ∀ x ∈ l, ∀ y ∈ l, x ≠ y → R x y ∨ R y x
  | [], _, x, mem, _, _, _ => by simp at mem
  | a :: l, h, x, xm, y, ym, ne => by
    rw [List.pairwise_cons] at h
    rcases List.mem_cons.mp xm with rfl | xl <;> rcases List.mem_cons.mp ym with rfl | yl
    · exact absurd rfl ne
    · exact .inl (h.1 y yl)
    · exact .inr (h.1 x xl)
    · exact pairwise_either h.2 x xl y yl ne

/-- The callee's places: the arrays lent, in the caller's block, and the
caller's places, above it; the callee's budget is the caller's room and no
block. -/
theorem FrameCorr.lend {st : State} {hp hpS : Heap} (fc : FrameCorr sx bud places st hp)
    {scope : List Binding} {frame : Nat → Nat} {base next : Nat} (fr : Layout scope frame base next)
    (apart : ∀ x ∈ places, ∀ b ∈ scope, x.cell ≠ frame b.slot)
    (unviewed : ∀ v ∈ st.i32ArrayViews, ∀ b ∈ scope, viewedType b.ty = false → v.root ≠ frame b.slot)
    {args : List SrcEff} {types : List SrcType} {t : Nat} {a : ArrayArgs}
    (ok : arrayArgs scope args types t 0 = some a) (blockPos : 0 < bud.block) (bytesLe : a.bytes ≤ bud.block)
    (lentHold : ∀ x ∈ arrayPlaces scope frame hp.fsp args 0, ∀ places', x.Holds sx places' st hpS)
    (out : ∀ c, hp.fsp + a.bytes ≤ c → hpS.bytes c = hp.bytes c)
    (fsp : hpS.fsp = hp.fsp) (limit : hpS.limit = hp.limit) (top : hpS.top = hp.top)
    (statics : hpS.staticBase = hp.staticBase ∧ hpS.statics = hp.statics) :
    FrameCorr sx ⟨bud.room, 0⟩ (arrayPlaces scope frame hp.fsp args 0 ++ places) st hpS := by
  obtain ⟨shapeAll, pairwise⟩ := arrayPlaces_shape fr (A := hp.fsp) ok
  have pos : 0 < bud.room + bud.block := by omega
  have room := fc.room pos
  have ceiling := fc.ceiling pos
  have bounded := fc.bounded pos
  refine ⟨fun x mem => ?_, fun x mem => ?_, fun x mem => ?_, fun x mem y ymem ne => ?_, fun x mem => ?_,
    fun v vmem x mem => ?_, fun _ => by simp only; rw [fsp, limit]; exact room, fun _ => by simp only; rw [fsp, top]; omega,
    fun _ => by rw [top]; exact bounded, fc.statics.congr statics.1 statics.2 top⟩
  · rcases List.mem_append.mp mem with lent | old
    · exact lentHold x lent _
    · obtain ⟨v, read, holds⟩ := fc.holds x old
      refine ⟨v, read, (fc.packed x old).holdsAt (holds.congr (Addressed.view_congr fun c covers => out c ?_))⟩
      have := (fc.inside x old).1
      unfold Addressed.Covers at covers
      omega
  · simp only
    rw [fsp, limit, top]
    rcases List.mem_append.mp mem with lent | old
    · obtain ⟨-, -, -, lo, hi⟩ := shapeAll x lent
      omega
    · have := fc.inside x old
      omega
  · rcases List.mem_append.mp mem with lent | old
    · obtain ⟨-, -, -, lo, hi⟩ := shapeAll x lent
      omega
    · exact fc.small x old
  · rcases List.mem_append.mp mem with xl | xo <;> rcases List.mem_append.mp ymem with yl | yo
    · rcases pairwise_either pairwise x xl y yl ne with ⟨c, h⟩ | ⟨c, h⟩
      · exact ⟨c, .inl h⟩
      · exact ⟨fun e => c e.symm, .inr h⟩
    · obtain ⟨-, -, ⟨b, bmem, cell, -, -⟩, -, hi⟩ := shapeAll x xl
      have := (fc.inside y yo).1
      exact ⟨fun e => apart y yo b bmem (by rw [← cell, e]), .inl (by omega)⟩
    · obtain ⟨-, -, ⟨b, bmem, cell, -, -⟩, -, hi⟩ := shapeAll y yl
      have := (fc.inside x xo).1
      exact ⟨fun e => apart x xo b bmem (by rw [← cell, ← e]), .inr (by omega)⟩
    · exact fc.apart x xo y yo ne
  · rcases List.mem_append.mp mem with lent | old
    · exact (shapeAll x lent).1
    · exact fc.packed x old
  · rcases List.mem_append.mp mem with lent | old
    · obtain ⟨packed, -, ⟨b, bmem, cell, xty, -⟩, -⟩ := shapeAll x lent
      obtain ⟨-, -, e, n, hx, -⟩ := packed
      rw [cell]; exact unviewed v vmem b bmem (by rw [← xty, hx]; rfl)
    · exact fc.unviewed v vmem x old


/-! ## The call -/

theorem readCell_entry {st : State} {c : Nat} {v : Value} (read : Semantics.readCellProjection st c [] = .ok v) :
    st.cellEntry? c = some ⟨c, some v⟩ := by
  unfold Semantics.readCellProjection at read
  cases h : st.cellEntry? c with
  | none => rw [h] at read; simp at read
  | some e =>
    rw [h] at read
    obtain ⟨id, value⟩ := e
    cases value with
    | none => simp at read
    | some root =>
      simp only [Semantics.projectedValue, Except.ok.injEq] at read
      have := (cellEntry_mem h).2
      simp only at this
      subst this
      subst read
      rfl

/-- The call's code up to the call: the arguments change nothing in Core
and pass their checks; the block's address goes into slot `t`, the stores
put the arrays lent into it, and the callee's correspondence holds, the
arrays lent its places. -/
theorem arrayCall_setup {sp : SrcProgram} {mp : Program} {d : Nat} {scope : List Binding} {frame : Nat → Nat}
    {base next : Nat} {st : State} {env : Env} {hp : Heap}
    (corr : Corr sx places scope frame st env) (fr : Layout scope frame base next)
    (hc : HeapCorr st.heap st.world hp) (fc : FrameCorr sx bud places st hp) (within : st.heap.nextAddress ≤ hp.limit)
    {args : List SrcEff} {types : List SrcType} {t : Nat} {a : ArrayArgs} (tAbove : next ≤ t)
    (ok : arrayArgs scope args types t 0 = some a) (blockPos : 0 < bud.block) (bytesLe : a.bytes ≤ bud.block)
    {k : Nat} {values : List Value} {afterArgs : State}
    (argsRun : evalExprs k sp.toCore st (SrcEff.toCoreList args) = .done values afterArgs) :
    afterArgs = st ∧ a.guard.eval env = 1 ∧ a.args.length = sizes types ∧
      ∃ EC, (EC t).toNat = hp.fsp ∧ (∀ j, j ≠ t → EC j = env j) ∧
        Exec mp d env hp (.frame t 0) (.normal EC hp) ∧
        ∃ hpS, Exec mp d EC hp a.stores (.normal EC hpS) ∧
          HeapCorr st.heap st.world hpS ∧ FrameCorr sx ⟨bud.room, 0⟩ (arrayPlaces scope frame hp.fsp args 0 ++ places) st hpS ∧
          FieldsHold sx (arrayPlaces scope frame hp.fsp args 0 ++ places) types values (Func.entry (Expr.evalAll EC a.args)) 0 ∧
          hpS.limit = hp.limit ∧ hpS.fsp = hp.fsp ∧ hpS.top = hp.top := by
  have pos : 0 < bud.room + bud.block := by omega
  have room := fc.room pos
  have ceiling := fc.ceiling pos
  have bounded := fc.bounded pos
  have target := SrcProgram.target_toCore sp
  obtain ⟨rfl, len, g, -⟩ := arrayArgs_sound (A := hp.fsp) corr target ok argsRun
  have agree : ∀ j, j ≠ t → (env.set t (BitVec.ofNat 64 hp.fsp)) j = env j := fun j ne => by
    simp [Env.set, ne]
  have corrC := corr.env_congr (fr.agree fun j lt => agree j (by omega))
  have at_ : ((env.set t (BitVec.ofNat 64 hp.fsp)) t).toNat = hp.fsp := by
    simp only [Env.set, if_pos rfl, BitVec.toNat_ofNat]
    exact Nat.mod_eq_of_lt (by omega)
  obtain ⟨-, -, -, holds⟩ := arrayArgs_sound (A := hp.fsp) corrC target ok argsRun
  obtain ⟨hpS, stores, out, limitS, cursorS, ioS, fspS, topS, lent⟩ :=
    arrayStores_exec (mp := mp) (d := d) corrC at_ ok (hp := hp) (by omega) (by omega)
  refine ⟨rfl, g, len, _, at_, agree, .frame (by omega), hpS, stores,
    hc.high within (fun c lt => out c (.inl (by omega))) cursorS limitS ioS,
    fc.lend fr corr.apart corr.unviewed ok blockPos bytesLe lent (fun c hi => out c (.inr (by omega))) fspS limitS topS
      stores.statics,
    holds at_ (by omega) (fun x mem => List.mem_append_right _ mem) (fun x mem => List.mem_append_left _ mem),
    limitS, fspS, topS⟩

/-- A call passing arrays as slices that Core evaluates: the mini code runs
to a state where the scope, the arrays lent among them with their new
values, still corresponds, and the result is in the slots from `next`. -/
theorem arrayCall_sound {sp : SrcProgram} [StaticsOf sp sx] {mp : Program}
    (lowered : lowerFuncs (sigs sp.funcs) (sigs sp.funcs) sp.decls sp.funcs = some mp.funcs) {k : Nat}
    (ih : StmtSound sp mp k) {scope : List Binding} {frame : Nat → Nat} {base next : Nat} {st : State}
    {env : Env} {hp : Heap} {callee : Nat} {args : List SrcEff} {ev : Evaluated}
    (ok : arrayCall (sp.sigsAt bud) scope next callee args = some ev)
    (corr : Corr sx places scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell) (hc : HeapCorr st.heap st.world hp) (fc : FrameCorr sx bud places st hp)
    {v : Value} {st' : State}
    (run : evalExpr (k + 1) sp.toCore st (.call callee (SrcEff.toCoreList args)) = .done v st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    st'.Fresh ∧ Keeps places base st st' ∧ st'.locals = st.locals ∧ 0 < ev.ty.size ∧
      ∃ d env' hp', Exec mp d env hp ev.stmt (.normal env' hp') ∧ Corr sx places scope frame st' env' ∧
        ev.ty.HoldsAt sx places v env' next ∧ HeapCorr st'.heap st'.world hp' ∧ FrameCorr sx bud places st' hp' := by
  simp only [arrayCall] at ok
  split at ok
  · simp at ok
  rename_i sig sigFound
  obtain ⟨f, values, afterArgs, completed, c, argsRun, found, _, bodyRun, result, rfl⟩ :=
    call_inv (sigsAt_inside sigFound) run
  rw [sigsAt_get, found] at sigFound
  simp only [Option.map_some, Option.some.injEq] at sigFound
  subst sigFound
  simp only [arrayCallSig] at ok
  split at ok
  · simp at ok
  rename_i a argsOk
  simp only [arrayCallCode] at ok
  split at ok
  case isFalse => simp at ok
  rename_i checks
  simp only [Bool.and_eq_true, decide_eq_true_eq] at checks
  obtain ⟨⟨⟨⟨pos, scalar⟩, fits⟩, blockPos⟩, bytesLe⟩ := checks
  simp only [Option.some.injEq] at ok
  subst ok
  have room := fc.room (by omega)
  have ceiling := fc.ceiling (by omega)
  have bounded := fc.bounded (by omega)
  -- the arguments change nothing, so the body's growth bounds the start
  obtain ⟨hst, -⟩ := arrayArgs_sound (A := 0) corr (SrcProgram.target_toCore sp) argsOk argsRun
  subst afterArgs
  have entry := bindLocals_same (paramBindings f.params values) { st with locals := [] }
  have bodyGrown := (Grows.same entry.1 entry.2).trans (grows sp (k + 1) k (Nat.lt_succ_self k) bodyRun)
  have bound' : completed.heap.nextAddress ≤ hp.limit := bound
  have within : st.heap.nextAddress ≤ hp.limit := Nat.le_trans (bodyGrown).next bound'
  have tAbove : next ≤ next + f.ret.size := Nat.le_add_right _ _
  obtain ⟨-, g, len, EC, atC, sameC, frameExec, hpS, storesExec, hcS, fcS, holdsS, limitS, fspS, topS⟩ :=
    arrayCall_setup (sp := sp) (mp := mp) (d := 0) corr fr hc fc within tAbove argsOk blockPos bytesLe argsRun
  obtain ⟨freshDone, keeps, d, rs, hp', bud', ⟨g', gFound, arity, exec⟩, holdsRet, rsLen, hcDone, fcDone⟩ :=
    body_sound lowered ih found (hp := hpS) fresh hcS fcS fits (fcS.below fresh) holdsS
      (by rw [evalAll_length, len, paramsSize_eq]) bodyRun result (by rw [limitS]; exact bound')
  have limit' : hp'.limit = hp.limit := exec.limit.trans limitS
  have top' : hp'.top = hp.top := exec.top.trans topS
  have callExec : Exec mp (d + 1) EC hpS (.call next f.ret.size callee a.args)
      (.normal (EC.setMany next rs) { hp' with fsp := hpS.fsp }) :=
    .call gFound (by rw [← arity, evalAll_length]) rsLen (Nat.lt_succ_self d) exec
  rw [fspS] at callExec
  have frame2 : Exec mp (d + 1) (EC.setMany next rs) { hp' with fsp := hp.fsp } (.frame (next + f.ret.size) 0)
      (.normal ((EC.setMany next rs).set (next + f.ret.size) (BitVec.ofNat 64 hp.fsp)) { hp' with fsp := hp.fsp }) :=
    .frame (by show hp'.limit + 0 ≤ hp.fsp; omega)
  have at3 : (((EC.setMany next rs).set (next + f.ret.size) (BitVec.ofNat 64 hp.fsp)) (next + f.ret.size)).toNat =
      hp.fsp := by
    simp only [Env.set, if_pos rfl, BitVec.toNat_ofNat]
    exact Nat.mod_eq_of_lt (by omega)
  have top2 : ({ hp' with fsp := hp.fsp } : Heap).top = hp.top := top'
  obtain ⟨E4, loadsExec, loaded, same4⟩ :=
    arrayLoads_exec (mp := mp) (d := d + 1) fr tAbove argsOk at3 (by rw [top2]; omega) (by omega)
  have shape := (arrayPlaces_shape fr (A := hp.fsp) argsOk).1
  have notLent : ∀ b ∈ scope, (¬∃ x ∈ arrayPlaces scope frame hp.fsp args 0, x.cell = frame b.slot) →
      ∀ i < b.ty.size, E4 (b.slot + i) = env (b.slot + i) := by
    intro b bmem passed i lt
    have apartC : ∀ x ∈ arrayPlaces scope frame hp.fsp args 0, x.cell ≠ frame b.slot :=
      fun x mem e => passed ⟨x, mem, e⟩
    have slotB := fr.slots b bmem
    rw [same4 _ fun x xmem b' b'mem cell => ?_]
    · simp only [Env.set]
      rw [if_neg (by omega), setMany_eq, if_neg (by omega), sameC _ (by omega)]
    · have ne : b ≠ b' := fun e => apartC x xmem (by rw [cell, e])
      rcases fr.apart b bmem b' b'mem ne with h | h <;> omega
  refine ⟨restore_fresh freshDone, ?_, rfl, pos, d + 1, E4, { hp' with fsp := hp.fsp },
    Exec.checkThen g (.seq (frameExec.mono (Nat.zero_le _)) (.seq (storesExec.mono (Nat.zero_le _))
      (.seq callExec (.seq frame2 loadsExec)))), ⟨corr.locals, corr.apart, fun b bmem => ?_,
      fun v vmem b bmem nv => keeps.unrooted (corr.below fresh b bmem) (fun w wm => corr.unviewed w wm b bmem nv) v vmem,
      fun b bmem n hty => ?_⟩, ?_,
    hcDone.withFsp _, ((fcDone.restrict fun x mem => List.mem_append_right _ mem).back fc limit' top').restoreLocals _⟩
  · refine Keeps.trans ⟨fun c below apart unrooted => keeps.cells c (by omega) (fun x mem => ?_) unrooted, keeps.next,
      fun v m => (keeps.views v m).imp_right (fun h => by omega), fun v m => keeps.persist v m,
      fun v m h => keeps.arrays v m h⟩ (restore_keeps _ _ _)
    rcases List.mem_append.mp mem with lent | old
    · obtain ⟨-, -, ⟨b, bmem, cell, -, -⟩, -⟩ := shape x lent
      have := fr.above b bmem
      rw [cell]
      omega
    · exact apart x old
  · by_cases passed : ∃ x ∈ arrayPlaces scope frame hp.fsp args 0, x.cell = frame b.slot
    · obtain ⟨x, xmem, xcell⟩ := passed
      obtain ⟨b', b'mem, cell, xty, slotsEq⟩ := loaded x xmem
      have same : b' = b := fr.inj b' b'mem b bmem (by rw [← cell, xcell])
      subst same
      obtain ⟨packed, -⟩ := shape x xmem
      obtain ⟨v', read, held⟩ := fcDone.holds x (List.mem_append_left _ xmem)
      rw [packed.2.1] at read
      refine ⟨v', by rw [← xcell]; exact readCell_entry read, ?_⟩
      have := (packed.holdsAt (places' := places) held).congr (env' := E4) (slot' := b'.slot) fun i lt => by
        rw [Nat.zero_add, slotsEq i (xty ▸ lt)]
        have := Addressed.view_congr (x := x) (hp := hp') (hp' := { hp' with fsp := hp.fsp }) (fun _ _ => rfl) i lt
        simpa using this
      rwa [xty] at this
    · obtain ⟨v0, entry0, held⟩ := corr.values b bmem
      cases nv : viewedType b.ty
      · refine ⟨v0, ?_, held.congr (notLent b bmem passed)⟩
        show completed.cellEntry? (frame b.slot) = _
        rw [keeps.cells _ (corr.below fresh b bmem) (fun x mem => ?_) fun v vm => corr.unviewed v vm b bmem nv]
        · exact entry0
        · rcases List.mem_append.mp mem with lent | old
          · exact fun e => passed ⟨x, lent, e⟩
          · exact corr.apart x old b bmem
      · obtain ⟨n, hty⟩ := viewedType_true nv
        obtain ⟨w, wm, root, -, wlen, -⟩ := corr.viewed b bmem n hty
        rw [hty] at held
        cases held with
        | view len i32s =>
        obtain ⟨vs, entry', len', i32s'⟩ := keeps.arrays w wm ⟨_, root ▸ entry0, len.trans wlen.symm, i32s⟩
        exact ⟨_, root ▸ entry', by rw [hty]; exact .view (len'.trans wlen) i32s'⟩
  · obtain ⟨w, wm, root, address, length, npos⟩ := corr.viewed b bmem n hty
    refine ⟨w, keeps.persist w wm, root, ?_, length, npos⟩
    have passed : ¬∃ x ∈ arrayPlaces scope frame hp.fsp args 0, x.cell = frame b.slot := by
      rintro ⟨x, xmem, xcell⟩
      obtain ⟨b', b'mem, cell, xty, -⟩ := loaded x xmem
      have same : b' = b := fr.inj b' b'mem b bmem (by rw [← cell, xcell])
      subst same
      obtain ⟨packed, -⟩ := shape x xmem
      obtain ⟨-, -, e, m, hx, -⟩ := packed
      rw [xty, hty] at hx
      cases hx
    have := notLent b bmem passed 0 (by rw [hty]; exact npos)
    simp only [Nat.add_zero] at this
    rw [this]
    exact address
  · have h1 := setMany_holds (sx := sx) (places := places) ((SrcType.holdsAt_scalar scalar).mpr ((SrcType.holdsAt_scalar scalar).mp holdsRet))
      rsLen EC next
    refine h1.congr fun i lt => ?_
    rw [same4 _ fun x xmem b bmem cell => .inr (by have := fr.slots b bmem; omega)]
    simp only [Env.set]
    rw [if_neg (by omega)]

end Lanius.Mini
