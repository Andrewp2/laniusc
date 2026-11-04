module

public import Lanius.Mini.LowerStmt
public import Lanius.Mini.WorldTrace
public import Lanius.Mini.Stops
public import Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.FArith_opcode
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcType_same
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.assignFrom
import all Lanius.Mini.Compiler.P.compileModules
import all Lanius.Mini.Compiler.P.conjunction
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.lowerApply
import all Lanius.Mini.Compiler.P.lowerTagged
import all Lanius.Mini.Compiler.P.matchDst
import all Lanius.Mini.Compiler.P.matchVariants
import all Lanius.Mini.Compiler.P.needCapped
import all Lanius.Mini.Compiler.P.needsAfter
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.repeatType
import all Lanius.Mini.Compiler.P.storeArray
import all Lanius.Mini.Compiler.P.wordStride
import all Lanius.Mini.Compiler.Types
public import Lanius.Mini.Compiler.P.SrcExpr_guard
public import Lanius.Mini.Compiler.P.SrcType_same
public import Lanius.Mini.Compiler.P.UintTy_half
public import Lanius.Mini.Compiler.P.UintTy_isWide
public import Lanius.Mini.Compiler.P.armScope
public import Lanius.Mini.Compiler.P.consArgs
public import Lanius.Mini.Compiler.P.elementBase
public import Lanius.Mini.Compiler.P.evalDivide
public import Lanius.Mini.Compiler.P.evalDivideSint
public import Lanius.Mini.Compiler.P.evalNot
public import Lanius.Mini.Compiler.P.evalSame
public import Lanius.Mini.Compiler.P.hostRandomCode
public import Lanius.Mini.Compiler.P.longer
public import Lanius.Mini.Compiler.P.lowerBody
public import Lanius.Mini.Compiler.P.lowerCallSig
public import Lanius.Mini.Compiler.P.lowerLoadType
public import Lanius.Mini.Compiler.P.lowerLocal
public import Lanius.Mini.Compiler.P.matchDst
public import Lanius.Mini.Compiler.P.matchVariants
public import Lanius.Mini.Compiler.P.shortCircuit
public import Lanius.Mini.Compiler.P.withBudget
public import Lanius.Mini.Compiler.P.funcNeeds
public import Lanius.Mini.Compiler.P.storeArray
public import Lanius.Mini.Compiler.P.strStores
public import Lanius.Mini.Compiler.P.arrayCallSig
public import Lanius.Mini.Compiler.P.bindingBytes
public import Lanius.Mini.Compiler.P.needCapped
public import Lanius.Mini.Compiler.P.needsAfter
public import Lanius.Mini.Compiler.P.storeEvalWord
public import Lanius.Mini.Compiler.P.wordElement
public import Lanius.Mini.Compiler.P.wordStride

@[expose] public section
/-! A viewed array (`LetView`, SEMANTIC_DECISIONS "Addressed locals" point
5): `let id: [i32; n] = [...]; let p = core::mem::i32_array_data_ptr(id);`.
Core binds the array, then maps its encoding into a fresh borrowed heap block
and views the cell there (`mapI32ArrayView`). The verified compiler stores
the elements into slots, bump-allocates a block of `4 n` bytes, stores the
elements packed into it, and puts the block's address in the pointer's slot
and the array's first slot. -/

namespace Lanius.Mini

variable {bud : Budget} {sx : Statics} {places : List Addressed}

open Lanius.Core (Value)
open Lanius.Semantics (State Cell Completion evalExpr evalExprs execStmt restoreLocals)

/-! ## The elements' bytes -/

/-- The low four bytes of each of the `n` slots from `slot`. -/
def slotBytes (env : Env) : Nat → Nat → List UInt8
  | _, 0 => []
  | slot, n + 1 => Semantics.encodeNatLE 4 (env slot).toNat ++ slotBytes env (slot + 1) n

theorem slotBytes_length (env : Env) : ∀ (slot n : Nat), (slotBytes env slot n).length = 4 * n
  | _, 0 => rfl
  | slot, n + 1 => by
    simp only [slotBytes, List.length_append, slotBytes_length env (slot + 1) n, Semantics.encodeNatLE,
      List.length_map, List.length_range]
    omega

theorem encodeNatLE_four (v : Nat) : Semantics.encodeNatLE 4 v = Semantics.encodeNatLE 4 (v % 2 ^ 32) := by
  simp only [Semantics.encodeNatLE]
  apply List.map_congr_left
  intro i mem
  simp only [List.mem_range] at mem
  congr 1
  rcases i with _ | _ | _ | _ | i
  all_goals simp only [Nat.reducePow, Nat.reduceAdd] at *
  all_goals omega

theorem i32_toNat_emod (x : BitVec 32) : Int.toNat (x.toInt % 2 ^ 32) = x.toNat := by
  rw [BitVec.toInt_eq_toNat_cond]
  have := x.isLt
  split <;> omega

/-- Slots that hold `n` `i32`s hold in-range `i32`s whose encoding is the
slots' low four bytes. -/
theorem fields_i32 : ∀ (n : Nat) {vs : List Value} {env : Env} {slot : Nat},
    FieldsHold sx places (List.replicate n .i32) vs env slot →
      vs.length = n ∧ (∀ x ∈ vs, Views.IsI32 x) ∧ Semantics.encodeI32Array vs = .ok (slotBytes env slot n)
  | 0, _, _, _, .nil => ⟨rfl, by simp, rfl⟩
  | n + 1, _, env, slot, .cons (.i32 holds) rest => by
    obtain ⟨len, i32s, enc⟩ := fields_i32 n rest
    obtain ⟨rfl, bits⟩ := holds
    refine ⟨by simp [len], fun x mem => ?_, ?_⟩
    · simp only [List.mem_cons] at mem
      rcases mem with rfl | mem
      · exact ⟨_, rfl, BitVec.le_toInt _, BitVec.toInt_lt⟩
      · exact i32s x mem
    · simp only [SrcType.size] at enc
      simp only [Semantics.encodeI32Array, enc, slotBytes, i32Bytes_eq, i32_toNat_emod]
      congr 2
      have : (low (env slot)).toNat = (env slot).toNat % 2 ^ 32 := by
        simp [low, BitVec.toNat_setWidth]
      rw [encodeNatLE_four (env slot).toNat, this]

theorem slotBytes_congr {env env' : Env} : ∀ (slot n : Nat), (∀ i < n, env' (slot + i) = env (slot + i)) →
    slotBytes env' slot n = slotBytes env slot n
  | _, 0, _ => rfl
  | slot, n + 1, same => by
    simp only [slotBytes]
    have h1 := same 0 (by omega)
    have h2 := slotBytes_congr (env := env) (env' := env') (slot + 1) n fun i lt => by
      have := same (i + 1) (by omega)
      rw [show slot + (i + 1) = slot + 1 + i by omega] at this
      exact this
    simp only [Nat.add_zero] at h1
    rw [h1, h2]

/-! ## The stores -/

/-- The heap after storing the low four bytes of the `n` slots from `slot`
packed from `address`. -/
def storeWords (hp : Heap) (address : Nat) (env : Env) (slot : Nat) : Nat → Heap
  | 0 => hp
  | n + 1 => storeWords (hp.writeLE address (env slot).toNat 4) (address + 4) env (slot + 1) n

theorem Heap.writeBytes_append : ∀ (hp : Heap) (address : Nat) (xs ys : List UInt8),
    hp.writeBytes address (xs ++ ys) = (hp.writeBytes address xs).writeBytes (address + xs.length) ys
  | _, _, [], _ => rfl
  | hp, address, x :: xs, ys => by
    simp only [List.cons_append, Heap.writeBytes, List.length_cons]
    rw [Heap.writeBytes_append _ (address + 1) xs ys, show address + 1 + xs.length = address + (xs.length + 1) by omega]

theorem storeWords_eq (env : Env) : ∀ (n : Nat) (hp : Heap) (address slot : Nat),
    storeWords hp address env slot n = hp.writeBytes address (slotBytes env slot n)
  | 0, _, _, _ => rfl
  | n + 1, hp, address, slot => by
    simp only [storeWords, slotBytes, storeWords_eq env n, writeLE_eq_writeBytes, Heap.writeBytes_append,
      Semantics.encodeNatLE, List.length_map, List.length_range]

theorem storeWords_top (env : Env) : ∀ (n : Nat) (hp : Heap) (address slot : Nat),
    (storeWords hp address env slot n).top = hp.top
  | 0, _, _, _ => rfl
  | n + 1, hp, address, slot => by
    simp only [storeWords, storeWords_top env n]
    exact (Heap.writeLE_top _ _ _ _).1

/-- The stores of `viewStores`: the slots' low four bytes, packed from the
address in `pointer`. -/
theorem viewStores_exec {mp : Program} {d : Nat} {env : Env} {pointer p : Nat} {rest : Stmt} {out : Outcome}
    (at_ : (env pointer).toNat = p) :
    ∀ (n : Nat) {slot offset : Nat} {hp : Heap}, p + offset + 4 * n ≤ hp.top → p + offset + 4 * n < 2 ^ 64 →
      Exec mp d env (storeWords hp (p + offset) env slot n) rest out →
      Exec mp d env hp (viewStores pointer slot offset n rest) out
  | 0, slot, offset, hp, _, _, exec => by
    rw [viewStores, if_pos rfl]; exact exec
  | n + 1, slot, offset, hp, top, small, exec => by
    rw [viewStores, if_neg (by omega)]
    have addr : ((Expr.binary Word.u64 BinOp.add (Expr.var pointer) (Expr.lit (BitVec.ofNat 64 offset))).eval
        env).toNat = p + offset := by
      simp only [Expr.eval, Word.apply, BinOp.apply, BitVec.toNat_add, at_, BitVec.toNat_ofNat]
      rw [Nat.mod_eq_of_lt (show offset < 2 ^ 64 by omega), Nat.mod_eq_of_lt (by omega)]
    refine .seq (.storeWord (by rw [addr]; simp only [MemWidth.bytes]; omega)) ?_
    rw [addr]
    simp only [MemWidth.bytes, Expr.eval, Nat.add_sub_cancel]
    refine viewStores_exec at_ n (by rw [(Heap.writeLE_top _ _ _ _).1]; omega) (by omega) ?_
    rw [show p + (offset + 4) = p + offset + 4 by omega]
    exact exec

/-! ## Core's heap: a borrowed block -/

/-- Mapping `bytes` into a borrowed block of Core's heap, 4-aligned: the
block is at the mini cursor rounded up to 4, and the mini heap with its
cursor past the block and the bytes written there corresponds. -/
theorem HeapCorr.mapView {h : Memory.Heap} {w : Lanius.World.State} {hp : Heap} (corr : HeapCorr h w hp)
    {bytes : List UInt8} {p : Nat} {h' : Memory.Heap} (ok : h.mapBorrowed bytes 4 = .allocated p h') :
    p = alignUp hp.cursor 2 ∧ h'.nextAddress = p + max bytes.length 1 ∧
      (p + max bytes.length 1 ≤ hp.limit →
        HeapCorr h' w (({ hp with cursor := p + max bytes.length 1 } : Heap).writeBytes p bytes)) := by
  obtain ⟨hpEq, rfl⟩ := Views.mapBorrowed_four ok
  have one : max h.nextAddress 1 = hp.cursor := by rw [corr.cursor]; have := corr.pos; addr_omega
  have pEq : p = alignUp hp.cursor 2 := by rw [hpEq, one, alignUp_eq]
  have ge : hp.cursor ≤ p := by
    rw [pEq, alignUp_eq]
    exact memAlignUp_ge _ _ (Nat.two_pow_pos _)
  refine ⟨pEq, rfl, fun roomBound => ?_⟩
  rw [Heap.writeBytes_eq_writeAll]
  have curs := corr.cursor
  refine ⟨rfl, by addr_omega, corr.unbounded, corr.small, ?_, ?_, ?_, ?_, ?_, ?_, corr.out, corr.err,
    corr.closed, corr.input, corr.streams⟩
  · intro b m
    simp only [List.mem_append, List.mem_singleton] at m
    rcases m with m | rfl
    · exact corr.sized b m
    · rfl
  · intro b m
    simp only [List.mem_append, List.mem_singleton] at m
    rcases m with m | rfl
    · have := corr.below b m
      addr_omega
    · exact Nat.le_refl _
  · intro b m b' m' less
    simp only [List.mem_append, List.mem_singleton] at m m'
    rcases m with m | rfl <;> rcases m' with m' | rfl
    · exact corr.apart b m b' m' less
    · have := corr.below b m
      simp only
      addr_omega
    · have := corr.below b' m'
      simp only at less
      addr_omega
    · exact absurd less (Nat.lt_irrefl _)
  · intro b m b' m' same
    simp only [List.mem_append, List.mem_singleton] at m m'
    rcases m with m | rfl <;> rcases m' with m' | rfl
    · exact corr.unique b m b' m' same
    · have := corr.below b m
      simp only at same
      addr_omega
    · have := corr.below b' m'
      simp only at same
      addr_omega
    · rfl
  · intro b m bl i inside
    simp only [List.mem_append, List.mem_singleton] at m
    rcases m with m | rfl
    · have := corr.below b m
      have sized := corr.sized b m
      have := Nat.le_max_left b.size 1
      simp only [Heap.writeAll]
      rw [if_neg (by addr_omega)]
      exact corr.bytes b m bl i inside
    · simp only [Heap.writeAll]
      rw [if_pos ⟨by addr_omega, by simp only at inside; addr_omega⟩, Nat.add_sub_cancel_left,
        List.getD_eq_getElem?_getD, List.getElem?_eq_getElem (by simpa using inside)]
      rfl
  · intro a above below
    have := Nat.le_max_left bytes.length 1
    simp only [Heap.writeAll]
    rw [if_neg (by simp only at above; addr_omega)]
    exact corr.zero a (by simp only at above; addr_omega) below

/-! ## Core's run -/

/-- `i32_array_data_ptr` of an array local just bound, of cell
`st.nextCell`: the cell is no view's root yet, so Core maps the array's
encoding into a new borrowed block and views the cell there. -/
theorem viewPtr_run {P : Core.Program} {k : Nat} {st : State} (fresh : st.Fresh) {id : Nat} {vs : List Value}
    {w : Value} {st3 : State}
    (run : evalExpr k P (st.bindLocal id (.array vs)) (.i32ArrayDataPtr (.local id)) = .done w st3) :
    ∃ bytes p heap', Semantics.encodeI32Array vs = .ok bytes ∧ st.heap.mapBorrowed bytes 4 = .allocated p heap' ∧
      w = .pointer p ∧
      st3 = { (st.bindLocal id (.array vs)) with
        heap := heap'
        i32ArrayViews := st.i32ArrayViews ++ [{ address := p, root := st.nextCell, projections := [], length := vs.length }] } := by
  cases k with
  | zero => simp [evalExpr] at run
  | succ k =>
    simp only [evalExpr, Semantics.expressionPlace?] at run
    cases placeRun : Semantics.evalPlace k P (st.bindLocal id (.array vs)) .read (.local id) with
    | done r s =>
      obtain ⟨rfl, cell, hcell, hroot, hproj, e, he, hval⟩ := evalPlace_local_read placeRun
      have cellEq : cell = st.nextCell := by
        simp [State.cellId?, State.bindLocal, State.bindCell] at hcell
        exact hcell.symm
      subst cellEq
      rw [bindLocal_self fresh id _] at he
      cases he
      cases r
      simp only at hroot hproj hval
      subst hroot hproj hval
      simp only [placeRun] at run
      have none : (st.bindLocal id (.array vs)).i32ArrayView? st.nextCell [] = none := by
        simp only [State.i32ArrayView?, List.find?_eq_none]
        intro v mem
        have := fresh.2.root_lt fresh.1 v mem
        simp only [decide_eq_true_eq, not_and]
        intro same; simp only [Lanius.CellId] at *; omega
      simp only [Semantics.mapI32ArrayView, none] at run
      split at run
      · simp at run
      rename_i bytes enc
      split at run
      · rename_i p heap' map
        simp only [Semantics.Outcome.done.injEq] at run
        obtain ⟨rfl, rfl⟩ := run
        exact ⟨bytes, p, heap', enc, map, rfl, rfl⟩
      · simp at run
      · simp at run
    | trapped => simp [placeRun] at run
    | exited => simp [placeRun] at run
    | outOfFuel => simp [placeRun] at run

/-- With two ticks of fuel, `i32_array_data_ptr` of an array local just bound
completes. -/
theorem viewPtr_done {P : Core.Program} {st : State} (fresh : st.Fresh) (id : Nat) {vs : List Value}
    {bytes : List UInt8} (enc : Semantics.encodeI32Array vs = .ok bytes) (k : Nat) :
    ∃ w st3, evalExpr (k + 2) P (st.bindLocal id (.array vs)) (.i32ArrayDataPtr (.local id)) = .done w st3 := by
  have cell : (st.bindLocal id (.array vs)).cellId? id = some st.nextCell := by
    simp [State.cellId?, State.bindLocal, State.bindCell]
  have place : Semantics.evalPlace (k + 1) P (st.bindLocal id (.array vs)) .read (.local id) =
      .done { root := st.nextCell, projections := [], value := some (.array vs) } (st.bindLocal id (.array vs)) := by
    simp [Semantics.evalPlace, cell, bindLocal_self fresh id (.array vs)]
  have none : (st.bindLocal id (.array vs)).i32ArrayView? st.nextCell [] = none := by
    simp only [State.i32ArrayView?, List.find?_eq_none]
    intro v mem
    have := fresh.2.root_lt fresh.1 v mem
    simp only [decide_eq_true_eq, not_and]
    intro same; simp only [Lanius.CellId] at *; omega
  simp only [evalExpr, Semantics.expressionPlace?, place, Semantics.mapI32ArrayView, none, enc]
  have valid : Lanius.Memory.validAlignment 4 = true := by decide
  cases m : (st.bindLocal id (.array vs)).heap.mapBorrowed bytes 4 with
  | allocated a h => exact ⟨_, _, rfl⟩
  | exhausted h => simp [Lanius.Memory.Heap.mapBorrowed, valid] at m
  | trapped r h => simp [Lanius.Memory.Heap.mapBorrowed, valid] at m

/-! ## The viewed array's binding -/

/-- Like `Corr.push`, for the viewed array: Core's state after binding the
array and viewing its new cell at `p`, the address in the binding's first
slot. -/
theorem Corr.pushView {scope frame st env base next} (corr : Corr sx places scope frame st env)
    (fr : Layout scope frame base next) (fresh : st.Fresh) {env' : Env} (agree : ScopeAgree scope env env')
    {id length : Nat} {vs : List Value} (i32s : ∀ x ∈ vs, Views.IsI32 x) (pos : 0 < length)
    (len : vs.length = length) {p : Nat} (addr : (env' next).toNat = p)
    (under : ∀ x ∈ places, x.cell < st.nextCell) (heap : Lanius.Memory.Heap) :
    Corr sx places (⟨id, next, .view length, none⟩ :: scope) (upd frame next st.nextCell)
      { (st.bindLocal id (.array vs)) with
        heap := heap
        i32ArrayViews := st.i32ArrayViews ++ [{ address := p, root := st.nextCell, projections := [], length := vs.length }] }
      env' := by
  have same := upd_scope fr st.nextCell
  refine ⟨?_, ?_, ?_, ?_, ?_⟩
  · simp only [State.bindLocal, State.bindCell, List.map_cons, corr.locals, upd, if_pos]
    congr 1
    apply List.map_congr_left
    intro b mem
    rw [← upd, same b mem]
  · intro x xmem b mem
    simp only [List.mem_cons] at mem
    rcases mem with rfl | mem
    · simp only [upd, if_pos]
      exact Nat.ne_of_lt (under x xmem)
    · rw [same b mem]
      exact corr.apart x xmem b mem
  · intro b mem
    simp only [List.mem_cons] at mem
    rcases mem with rfl | mem
    · refine ⟨.array vs, ?_, .view len fun x m => i32s x m⟩
      simp only [upd, if_pos]
      exact bindLocal_self fresh id _
    · obtain ⟨w, entry, holdsb⟩ := corr.values b mem
      refine ⟨w, ?_, holdsb.congr (agree b mem)⟩
      rw [same b mem]
      exact (bindLocal_entry (corr.below fresh b mem) id _).trans entry
  · intro w wmem b mem bnv
    simp only [List.mem_cons] at mem
    rcases mem with rfl | mem
    · simp [viewedType] at bnv
    · rw [same b mem]
      simp only [List.mem_append, List.mem_singleton] at wmem
      rcases wmem with wmem | rfl
      · exact corr.unviewed w wmem b mem bnv
      · exact Nat.ne_of_gt (corr.below fresh b mem)
  · intro b mem n hty
    simp only [List.mem_cons] at mem
    rcases mem with rfl | mem
    · simp only [SrcType.view.injEq] at hty
      subst hty
      refine ⟨_, List.mem_append_right _ (List.mem_singleton_self _), by simp [upd], addr.symm, len, pos⟩
    · obtain ⟨w, wm, root, address, length, wpos⟩ := corr.viewed b mem n hty
      refine ⟨w, List.mem_append_left _ wm, by rw [same b mem]; exact root, ?_, length, wpos⟩
      have := agree b mem 0 (by rw [hty]; exact wpos)
      simp only [Nat.add_zero] at this
      rw [this]
      exact address

/-! ## The statement -/

theorem Stops.assignFrom {prog : Program} {d : Nat} {hp : Heap} {rest : Stmt} {n : Nat} :
    ∀ (xs : List Expr) (slot : Nat) {env : Env}, Stops prog d (env.setFrom slot xs) hp rest n →
      Stops prog d env hp (assignFrom slot xs rest) n
  | [], _, _, stops => stops
  | _ :: more, slot, _, stops => .seqSecond .assign (Stops.assignFrom more (slot + 1) stops)

/-- The stores of `viewStores`, then a stop. -/
theorem viewStores_stops {mp : Program} {d : Nat} {env : Env} {pointer p : Nat} {rest : Stmt} {n : Nat}
    (at_ : (env pointer).toNat = p) :
    ∀ (count : Nat) {slot offset : Nat} {hp : Heap}, p + offset + 4 * count ≤ hp.top →
      p + offset + 4 * count < 2 ^ 64 →
      Stops mp d env (storeWords hp (p + offset) env slot count) rest n →
      Stops mp d env hp (viewStores pointer slot offset count rest) n
  | 0, slot, offset, hp, _, _, stops => by
    rw [viewStores, if_pos rfl]; exact stops
  | count + 1, slot, offset, hp, top, small, stops => by
    rw [viewStores, if_neg (by omega)]
    have addr : ((Expr.binary Word.u64 BinOp.add (Expr.var pointer) (Expr.lit (BitVec.ofNat 64 offset))).eval
        env).toNat = p + offset := by
      simp only [Expr.eval, Word.apply, BinOp.apply, BitVec.toNat_add, at_, BitVec.toNat_ofNat]
      rw [Nat.mod_eq_of_lt (show offset < 2 ^ 64 by omega), Nat.mod_eq_of_lt (by omega)]
    refine .seqSecond (.storeWord (by rw [addr]; simp only [MemWidth.bytes]; omega)) ?_
    rw [addr]
    simp only [MemWidth.bytes, Expr.eval, Nat.add_sub_cancel]
    refine viewStores_stops at_ count (by rw [(Heap.writeLE_top _ _ _ _).1]; omega) (by omega) ?_
    rw [show p + (offset + 4) = p + offset + 4 by omega]
    exact stops

/-- What a `LetView` emits after the elements' slots: the block, the stores,
the address into the array's first slot, then `rest`. -/
abbrev viewPrefix (next length : Nat) (rest : Stmt) : Stmt :=
  .seq (.alloc (next + length) 2 (.lit (BitVec.ofNat 64 (4 * length))))
    (viewStores (next + length) next 0 length (.seq (.assign next (.var (next + length))) rest))

section Statements

variable {sp : SrcProgram} {mp : Program} {fuel : Nat} {ret : SrcType} {scope : List Binding}
  {next : Nat} {stmt : Stmt} {frame : Nat → Nat} {base : Nat} {st : State} {env : Env}
  {c : Completion} {st' : State} {hp : Heap}
variable [StaticsOf sp sx]

/-- Entering a `LetView`'s body: Core bound the array (whose elements the
slots from `next` hold) and its pointer, the block within the limit; the
mini code before the body runs to a state that corresponds for the body's
scope, and leaving the body's scope again corresponds for the outer one. -/
theorem view_entered {P : Core.Program} {id length pointer k : Nat} {xs : List Expr} {vs : List Value}
    {w : Value} {st3 : State}
    (corr : Corr sx places scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell) (hc : HeapCorr st.heap st.world hp) (fc : LentHomes sx bud places st hp)
    (under : ∀ x ∈ places, x.cell < base) (pos : 0 < length)
    (fh : FieldsHold sx places (List.replicate length .i32) vs (env.setFrom next xs) next)
    (ptrRun : evalExpr k P (st.bindLocal id (.array vs)) (.i32ArrayDataPtr (.local id)) = .done w st3)
    (room : st3.heap.nextAddress ≤ hp.limit) :
    ∃ p frame' envB hp3, w = .pointer p ∧
      Corr sx places (viewScope id length pointer next scope) frame' (st3.bindLocal pointer (.pointer p)) envB ∧
      Layout (viewScope id length pointer next scope) frame' base (next + length + 1) ∧
      (st3.bindLocal pointer (.pointer p)).Fresh ∧ base ≤ (st3.bindLocal pointer (.pointer p)).nextCell ∧
      HeapCorr (st3.bindLocal pointer (.pointer p)).heap (st3.bindLocal pointer (.pointer p)).world hp3 ∧
      LentHomes sx bud places (st3.bindLocal pointer (.pointer p)) hp3 ∧ hp3.limit = hp.limit ∧
      Keeps places base st (st3.bindLocal pointer (.pointer p)) ∧
      (∀ {s4 : State} {c : Completion} {out : Outcome},
        Matches sx bud places ret (viewScope id length pointer next scope) frame' s4 c out →
        Matches sx bud places ret scope frame (restoreLocals st (restoreLocals st3 s4)) c out) ∧
      (∀ {rest : Stmt} {d : Nat} {out : Outcome}, Exec mp d envB hp3 rest out →
        Exec mp d env hp (assignFrom next xs (viewPrefix next length rest)) out) ∧
      (∀ {rest : Stmt} {d n : Nat}, Stops mp d envB hp3 rest n →
        Stops mp d env hp (assignFrom next xs (viewPrefix next length rest)) n) := by
  obtain ⟨vlen, i32s, enc⟩ := fields_i32 length fh
  obtain ⟨bytes, p, heap', enc', map, rfl, st3Eq⟩ := viewPtr_run fresh ptrRun
  rw [enc] at enc'
  cases enc'
  have tail : heap'.nextAddress ≤ hp.limit := by subst st3Eq; exact room
  obtain ⟨pEq, nextEq, hcRoom⟩ := hc.mapView map
  have maxEq : max (slotBytes (env.setFrom next xs) next length).length 1 = 4 * length := by
    rw [slotBytes_length]; addr_omega
  rw [maxEq] at nextEq hcRoom
  have room : p + 4 * length ≤ hp.limit := nextEq ▸ tail
  have small := hc.small
  let env1 := env.setFrom next xs
  let env2 := env1.set (next + length) (BitVec.ofNat 64 p)
  let envB := env2.set next (env2 (next + length))
  let hp3 := ({ hp with cursor := p + 4 * length } : Heap).writeBytes p (slotBytes (env.setFrom next xs) next length)
  have hc3 : HeapCorr heap' st.world hp3 := hcRoom room
  have pBits : (BitVec.ofNat 64 p).toNat = p := Nat.mod_eq_of_lt (by have := room; have := small; addr_omega)
  have envB_next : envB next = BitVec.ofNat 64 p := by
    simp only [envB, env2, Env.set, if_pos]
  have envB_ptr : envB (next + length) = BitVec.ofNat 64 p := by
    have : next + length ≠ next := by addr_omega
    simp [envB, env2, Env.set]
  have agree : ScopeAgree scope env envB := fr.agree fun j below => by
    simp only [envB, env2, env1, Env.set]
    rw [if_neg (by addr_omega), if_neg (by addr_omega)]
    exact setFrom_outside xs next env j (.inl below)
  have fresh3 : st3.Fresh := by
    subst st3Eq
    exact ⟨(bindLocal_fresh fresh id (.array vs)).1, Views.ViewsHold.mapView fresh.2 fresh.1 hc.below i32s enc map id⟩
  have next3 : st3.nextCell = st.nextCell + 1 := by subst st3Eq; rfl
  have corr1 : Corr sx places (⟨id, next, .view length, none⟩ :: scope) (upd frame next st.nextCell) st3 envB := by
    subst st3Eq
    exact corr.pushView fr fresh agree i32s pos vlen (by rw [envB_next, pBits])
      (fun x m => Nat.lt_of_lt_of_le (under x m) le) heap'
  have fr1 : Layout (⟨id, next, .view length, none⟩ :: scope) (upd frame next st.nextCell) base (next + length) :=
    fr.push (corr.below fresh) le id (ty := .view length) pos
  have corrB := corr1.push fr1 fresh3 (fun _ _ _ _ => rfl) (id := pointer) (v := .pointer p)
    (SrcType.HoldsAt.ptr (by simp only [SrcType.Holds, envB_ptr, pBits]))
    (fun x m => by rw [next3]; have := under x m; addr_omega)
  have frB := fr1.push (corr1.below fresh3) (by rw [next3]; addr_omega) pointer (ty := .ptr) (by decide)
  have hcB : HeapCorr (st3.bindLocal pointer (.pointer p)).heap (st3.bindLocal pointer (.pointer p)).world
      hp3 := by subst st3Eq; exact hc3
  have fcB : LentHomes sx bud places (st3.bindLocal pointer (.pointer p)) hp3 := by
    refine fc.congrViews (fun x m => ?_) (fun x m a covers => ?_) ?_ ?_ ?_ ?_ ?_
    · have := under x m
      rw [bindLocal_entry (by rw [next3]; addr_omega)]
      subst st3Eq
      exact bindLocal_entry (by addr_omega) id _
    · have := fc.inside x m
      unfold Addressed.Within at covers
      simp only [hp3, Heap.writeBytes_eq_writeAll, Heap.writeAll, slotBytes_length]
      rw [if_neg (by addr_omega)]
    · simp only [hp3, Heap.writeBytes_eq_writeAll, Heap.writeAll]
    · simp only [hp3, Heap.writeBytes_eq_writeAll, Heap.writeAll]
    · simp only [hp3, Heap.writeBytes_eq_writeAll, Heap.writeAll, Heap.top]
    · intro v vm x xm
      subst st3Eq
      simp only [State.bindLocal, State.bindCell, List.mem_append, List.mem_singleton] at vm
      rcases vm with vm | rfl
      · exact fc.unviewed v vm x xm
      · have := under x xm
        exact Nat.ne_of_gt (by simp only; addr_omega)
    · constructor <;> simp only [hp3, Heap.writeBytes_eq_writeAll, Heap.writeAll]
  have keeps3 : Keeps places base st st3 := by
    subst st3Eq
    refine ⟨fun c below _ _ => bindLocal_entry (by addr_omega) id _, Nat.le_succ _, fun v mem => ?_,
      fun v mem => List.mem_append_left _ mem, fun v _ h => bindLocal_held h id _⟩
    simp only [List.mem_append, List.mem_singleton] at mem
    rcases mem with mem | rfl
    · exact .inl mem
    · exact .inr le
  have heapEq : ∀ hp2 : Heap, hp2 = { hp with cursor := p +
      ((Expr.lit (BitVec.ofNat 64 (4 * length))).eval env1).toNat } →
      storeWords hp2 (p + 0) env2 next length = hp3 := by
    intro hp2 h2
    subst h2
    simp only [Expr.eval, BitVec.toNat_ofNat]
    rw [Nat.mod_eq_of_lt (show 4 * length < 2 ^ 64 by addr_omega), storeWords_eq, Nat.add_zero,
      slotBytes_congr (env := env1) next length fun i lt => by simp only [env2, Env.set]; rw [if_neg (by addr_omega)]]
  have allocRoom : alignUp hp.cursor 2 + ((Expr.lit (BitVec.ofNat 64 (4 * length))).eval env1).toNat ≤ hp.limit := by
    simp only [Expr.eval, BitVec.toNat_ofNat]
    rw [Nat.mod_eq_of_lt (by addr_omega), ← pEq]
    exact room
  have ptrAt : (env2 (next + length)).toNat = p := by simp only [env2, Env.set, if_pos]; exact pBits
  have top2 : p + 0 + 4 * length ≤ ({ hp with cursor := alignUp hp.cursor 2 +
      ((Expr.lit (BitVec.ofNat 64 (4 * length))).eval env1).toNat } : Heap).top := by
    simp only [Heap.top]; have := hp.limit_le_top; simp only [Heap.top] at this; addr_omega
  refine ⟨p, _, envB, hp3, rfl, corrB, frB, bindLocal_fresh fresh3 pointer _,
    by show base ≤ st3.nextCell + 1; rw [next3]; addr_omega, hcB, fcB,
    by simp only [hp3, Heap.writeBytes_eq_writeAll, Heap.writeAll],
    keeps3.trans (bindLocal_keeps (by rw [next3]; addr_omega) pointer _), ?_, ?_, ?_⟩
  · intro s4 c out matched
    cases matched with
    | next corr'' hc'' fc'' =>
      exact .next (((corr''.pop (st' := restoreLocals st3 s4) fr1 corr1.locals rfl).pop
        (st' := restoreLocals st (restoreLocals st3 s4)) fr corr.locals rfl)) hc''
        ((fc''.restoreLocals _).restoreLocals _)
    | returned holdsRet len hc'' fc'' =>
      exact .returned holdsRet len hc'' ((fc''.restoreLocals _).restoreLocals _)
    | broke corr'' hc'' fc'' =>
      exact .broke (((corr''.pop (st' := restoreLocals st3 s4) fr1 corr1.locals rfl).pop
        (st' := restoreLocals st (restoreLocals st3 s4)) fr corr.locals rfl)) hc''
        ((fc''.restoreLocals _).restoreLocals _)
    | continued corr'' hc'' fc'' =>
      exact .continued (((corr''.pop (st' := restoreLocals st3 s4) fr1 corr1.locals rfl).pop
        (st' := restoreLocals st (restoreLocals st3 s4)) fr corr.locals rfl)) hc''
        ((fc''.restoreLocals _).restoreLocals _)
  · intro rest d out exec
    refine assignFrom_exec xs next (.seq (.alloc (target := next + length) allocRoom) ?_)
    refine viewStores_exec (p := p) ?_ length (offset := 0) top2 (by addr_omega) ?_
    · rw [← pEq]; exact ptrAt
    rw [← pEq, heapEq _ rfl]
    exact .seq .assign exec
  · intro rest d n stops
    refine Stops.assignFrom xs next (.seqSecond (.alloc (target := next + length) allocRoom) ?_)
    refine viewStores_stops (p := p) ?_ length (offset := 0) top2 (by addr_omega) ?_
    · rw [← pEq]; exact ptrAt
    rw [← pEq, heapEq _ rfl]
    exact .seqSecond .assign stops

theorem stmt_letView (ih : ∀ m ≤ fuel, StmtSound sp mp m) {id length pointer : Nat} {fields : List SrcExpr}
    {body : SrcStmt}
    (ok : (SrcStmt.letView id length fields pointer body).lower (sp.sigsAt bud) sp.decls ret scope next = some stmt)
    (corr : Corr sx places scope frame st env) (fr : Layout scope frame base next) (fresh : st.Fresh)
    (le : base ≤ st.nextCell) (hc : HeapCorr st.heap st.world hp) (fc : LentHomes sx bud places st hp)
    (under : ∀ x ∈ places, x.cell < base)
    (run : execStmt (fuel + 1) sp.toCore st (SrcStmt.letView id length fields pointer body).toCore = .done c st')
    (bound : st'.heap.nextAddress ≤ hp.limit) :
    Simulates sx bud places mp hp ret scope frame base st env stmt c st' := by
  obtain ⟨xs, bstmt, nz, -, literalOk, bodyOk, rfl⟩ := letView_lower_inv ok
  have pos : 0 < length := Nat.pos_of_ne_zero nz
  simp only [lowerLiteral, lowerStructFields] at literalOk
  split at literalOk
  · simp at literalOk
  rw [repeatType_eq] at literalOk
  simp only [SrcStmt.toCore, execStmt] at run
  split at run
  · rename_i v st1 valueRun
    cases fuel with
    | zero => simp [evalExpr] at valueRun
    | succ k =>
      simp only [SrcType.literal, evalExpr] at valueRun
      split at valueRun
      · rename_i vs st2 fieldsRun
        simp only [Semantics.Outcome.done.injEq] at valueRun
        obtain ⟨hv, hst1⟩ := valueRun
        subst hv
        subst st1
        refine Simulates.checked (lowerArgs_guard corr (SrcProgram.target_toCore sp) literalOk fieldsRun) ?_
        obtain ⟨hst, fieldsHold, len, shapes⟩ :=
          lowerArgs_sound corr (SrcProgram.target_toCore sp) literalOk fieldsRun
        subst st2
        rw [sizes_replicate] at len
        have flat : FlatValue sx places (.array .i32 length) (.array vs) env xs :=
          ⟨by simp only [SrcType.size, len], .array fieldsHold⟩
        have insens : Insens xs next := Insens.below fun x mem => by
          obtain ⟨ys, shape, inYs⟩ := shapes x mem
          exact shape.below fr.slots x inYs
        have fh : FieldsHold sx places (List.replicate length .i32) vs (env.setFrom next xs) next := by
          have stored := flat.store insens
          cases stored; assumption
        simp only [execStmt] at run
        cases ptrRun : evalExpr k sp.toCore (st.bindLocal id (.array vs)) (.i32ArrayDataPtr (.local id)) with
        | done w st3 =>
          simp only [ptrRun] at run
          cases bodyRun : execStmt k sp.toCore (st3.bindLocal pointer w) body.toCore with
          | done c' s4 =>
            simp only [bodyRun, Semantics.restoreOutcomeLocals, Semantics.Outcome.done.injEq] at run
            obtain ⟨rfl, rfl⟩ := run
            have bound4 : s4.heap.nextAddress ≤ hp.limit := bound
            have room : st3.heap.nextAddress ≤ hp.limit := stmt_bound bodyRun bound4
            obtain ⟨p, frame', envB, hp3, rfl, corrB, frB, freshB, leB, hcB, fcB, limit3, keeps3, pop, exec', -⟩ :=
              view_entered (mp := mp) (ret := ret) (pointer := pointer) corr fr fresh le hc fc under pos fh ptrRun room
            obtain ⟨fresh4, keeps4, d, out, exec, matched⟩ :=
              ih k (Nat.le_succ k) (hp := hp3) bodyOk corrB frB freshB leB hcB fcB under bodyRun
                (by rw [limit3]; exact bound4)
            exact ⟨restore_fresh (restore_fresh fresh4),
              keeps3.trans (keeps4.trans ((restore_keeps base st3 s4).trans (restore_keeps base st _))), d, out,
              exec' exec, pop matched⟩
          | trapped => simp [bodyRun, Semantics.restoreOutcomeLocals] at run
          | exited => simp [bodyRun, Semantics.restoreOutcomeLocals] at run
          | outOfFuel => simp [bodyRun, Semantics.restoreOutcomeLocals] at run
        | trapped => simp [ptrRun, Semantics.restoreOutcomeLocals] at run
        | exited => simp [ptrRun, Semantics.restoreOutcomeLocals] at run
        | outOfFuel => simp [ptrRun, Semantics.restoreOutcomeLocals] at run
      all_goals simp at valueRun
  all_goals simp at run

end Statements

end Lanius.Mini
