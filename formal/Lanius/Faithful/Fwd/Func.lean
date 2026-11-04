module

public import Lanius.Faithful.Fwd.Stmt
public import Lanius.Faithful.Fwd.Prim
public import Lanius.Faithful.Simulation

@[expose] public section

/-! # Forward: calls complete in Core

By induction on the cost semantics' fuel, Core completes the body of every
call the cost semantics gives a value (`func_live`): a pure function's body
by `stmt_live`, and `boxed` and `unbox` by `boxed_live` and `unbox_live`,
with `boxCost` the prim cost. So a call whose cost `h` fits below `2 ^ 64`,
on an unbounded allocator, completes in Core with its pure value
(`call_completes`), the heap grown by at most `h`. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State evalExpr evalExprs restoreLocals)

/-- Core evaluates literal arguments to themselves, from fuel 1 on. -/
theorem values_fwd {P : Core.Program} {st : State} :
    ∀ (vals : List Value), Ev (fun k => evalExprs k P st (vals.map .value)) vals st
  | [] => exprs_nil_fwd
  | x :: rest => exprs_cons_fwd (value_fwd x) (values_fwd rest)

section
variable {sp : SrcProgram} {prims : Prims} {outside : List Nat}

/-- The ending of a body the cost semantics gives a value to is a call's. -/
theorem callResult_of {ret : SrcType} {heap : Memory.Heap} {tenv : TEnv} {st : State}
    {c : Lanius.Semantics.Completion} {o : Out} {w : Value}
    (dr : OutRel sp.toCore (boxElem sp prims) heap ret tenv st c o) (hv : outValue ret o = some w) :
    ∃ v, CallResult ret c v := by
  cases c with
  | next =>
    cases o with
    | next e =>
      simp only [outValue] at hv
      split at hv
      · next isUnit => exact ⟨.unit, SrcType.toCore_eq_unit isUnit, rfl⟩
      · cases hv
    | brk _ => exact False.elim dr
    | cont _ => exact False.elim dr
    | ret _ => exact False.elim dr
  | returned r =>
    cases r with
    | none =>
      cases o with
      | ret dv =>
        cases dv with
        | none =>
          simp only [outValue] at hv
          split at hv
          · next isUnit => exact ⟨.unit, SrcType.toCore_eq_unit isUnit, rfl⟩
          · cases hv
        | some => exact dr.elim
      | next _ => exact False.elim dr
      | brk _ => exact False.elim dr
      | cont _ => exact False.elim dr
    | some x => exact ⟨x, rfl⟩
  | breakLoop =>
    cases o with
    | brk _ => simp [outValue] at hv
    | next _ => exact False.elim dr
    | cont _ => exact False.elim dr
    | ret _ => exact False.elim dr
  | continueLoop =>
    cases o with
    | cont _ => simp [outValue] at hv
    | next _ => exact False.elim dr
    | brk _ => exact False.elim dr
    | ret _ => exact False.elim dr

/-- Core completes, within the cost, every call the cost semantics gives a
value with any fuel. -/
theorem func_live (pure : PureProg sp prims outside) (primsOk : PrimsOk sp prims) :
    ∀ N, FuncLive sp prims outside (boxCost sp) N
  | 0 => by
    intro found notOut len inv args hq budget fr
    rename_i c f values ps st w h
    simp [qcall] at hq
  | N + 1 => by
    intro found notOut len inv args hq budget fr
    rename_i c f values ps st w h
    have ih : FuncLive sp prims outside (boxCost sp) N := func_live pure primsOk N
    cases hp : prims.isPrim c with
    | false =>
      have plen : ps.length = f.params.length := by simpa using args.length.2
      simp only [qcall, hp, Bool.false_eq_true, if_false, found, plen, if_true] at hq
      obtain ⟨d, h1, h2, hd, hv, rfl⟩ := qthen_some hq
      obtain ⟨hd', rfl⟩ := qfree_some hv
      have entryInv := Same.start inv (paramBindings f.params values)
      have heapE : (({ st with locals := [] } : State).bindLocals (paramBindings f.params values)).heap = st.heap :=
        (bindLocals_same _ _).1
      have rel := EnvRel.heap_eq heapE.symm (EnvRel.entry inv args)
      obtain ⟨compl, completed, ev, dr, -, grown, rem⟩ := stmt_live (func_sim pure primsOk) ih f.ret f.body
        (PureFunc.stmt (pure c f found hp notOut)) entryInv (Locs.entry inv _) rel hd (by rw [heapE]; simpa using budget)
        (by rw [heapE]; exact fr)
      rw [heapE] at grown
      obtain ⟨v, cr⟩ := callResult_of dr hd'
      exact ⟨compl, completed, v, ev, cr, by simpa using grown, rem⟩
    | true =>
      simp only [qcall, hp, if_true, Option.map_eq_some_iff, Prod.mk.injEq] at hq
      obtain ⟨x, -, rfl, rfl⟩ := hq
      cases hb : prims.boxed.contains c with
      | true =>
        obtain ⟨t, id, sizeOf, slice, panic, hf, hs, hl, -, el, -, some⟩ := primsOk.1 c (by simpa using hb)
        rw [hf, Option.some.injEq] at found
        subst found
        rw [← valueWords_toCore] at some
        obtain ⟨wd, hwd⟩ := Option.isSome_iff_exists.mp some
        simp only [hb, if_true, boxCost_boxed hf hwd] at budget ⊢
        exact boxed_live hs hl el hwd inv args budget fr
      | false =>
        have nb : c ∉ prims.boxed := by simpa using hb
        have mem : c ∈ prims.unbox := (show c ∈ prims.boxed ∨ c ∈ prims.unbox by simpa [Prims.isPrim] using hp).resolve_left nb
        obtain ⟨t, id, slice, hf, hl, el, box⟩ := primsOk.2 c mem
        rw [hf, Option.some.injEq] at found
        subst found
        obtain ⟨compl, completed, v, ev, cr, heap⟩ := unbox_live hl el box inv args
        refine ⟨compl, completed, v, ev, cr, ?_, ?_⟩
        · simp only [heap, Bool.false_eq_true, if_false, Nat.add_zero, Nat.le_refl]
        · rw [heap]
          exact fr

/-- A call of a pure function whose cost `h` with fuel `N` fits below
`2 ^ 64`, on an unbounded allocator, completes in Core with the pure value
`pcall` gives with fuel `N`, the heap grown by at most `h` and still
unbounded. -/
theorem call_completes (pure : PureProg sp prims outside) (primsOk : PrimsOk sp prims)
    {N c h : Nat} {f : SrcFunc} {args ps : List Value} {st : State}
    (found : sp.funcs[c]? = some f) (notOutside : outside.contains c = false) (inv : Inv st)
    (rel : VRels sp.toCore (boxElem sp prims) st.heap (f.params.map SrcParam.ty) args ps)
    (cost : ccall sp prims (boxCost sp) N c ps = some h)
    (budget : st.heap.nextAddress + h ≤ 2 ^ 64) (fr : st.heap.remaining = none) :
    ∃ w v st', pcall sp prims N c ps = some w ∧
      Ev (fun k => evalExpr k sp.toCore st (.call c (args.map .value))) v st' ∧
      VRel sp.toCore (boxElem sp prims) st'.heap f.ret v w ∧ Inv st' ∧ Step st st' ∧
      st'.heap.nextAddress ≤ st.heap.nextAddress + h ∧ st'.heap.remaining = none := by
  simp only [ccall, Option.map_eq_some_iff] at cost
  obtain ⟨⟨w, h'⟩, hq, rfl⟩ := cost
  have len : args.length = f.params.length := by simpa using rel.length.1
  obtain ⟨compl, completed, v, ev, cr, grown, rem⟩ :=
    func_live pure primsOk N found notOutside len inv rel hq budget fr
  have call := call_fwd (values_fwd args) found len ev cr
  obtain ⟨k, hk⟩ := call.at
  have bound : (restoreLocals st completed).heap.nextAddress ≤ 2 ^ 64 := Nat.le_trans grown budget
  obtain ⟨w', hw', r, inv', step⟩ := call_sim pure primsOk found notOutside inv bound rel hk
  have hw : pcall sp prims N c ps = some w := by rw [pcall_eq_qcall sp prims (boxCost sp), hq]; rfl
  have same := (pcall_mono sp prims N hw (Nat.le_max_left N k)).symm.trans
    (pcall_mono sp prims k hw' (Nat.le_max_right N k))
  simp only [Option.some.injEq] at same
  subst same
  exact ⟨w, v, _, hw, call, r, inv', step, grown, rem⟩

/-- A call of a pure function on arguments Core completes, whose cost `h`
fits below `2 ^ 64`, on an unbounded allocator: Core completes the call, with
`pcall`'s value, the locals of the state after the arguments, and the heap
grown by at most `h` and still unbounded. -/
theorem pure_call_fwd (pure : PureProg sp prims outside) (primsOk : PrimsOk sp prims)
    {N c h : Nat} {f : SrcFunc} {args : List Core.Expr} {values ps : List Value} {st s1 : State}
    (found : sp.funcs[c]? = some f) (notOutside : outside.contains c = false)
    (argsRun : Ev (fun k => evalExprs k sp.toCore st args) values s1) (inv : Inv s1)
    (rel : VRels sp.toCore (boxElem sp prims) s1.heap (f.params.map SrcParam.ty) values ps)
    (cost : ccall sp prims (boxCost sp) N c ps = some h)
    (budget : s1.heap.nextAddress + h ≤ 2 ^ 64) (fr : s1.heap.remaining = none) :
    ∃ w v st', pcall sp prims N c ps = some w ∧
      Ev (fun k => evalExpr k sp.toCore st (.call c args)) v st' ∧
      VRel sp.toCore (boxElem sp prims) st'.heap f.ret v w ∧ Inv st' ∧ Step s1 st' ∧
      st'.heap.nextAddress ≤ s1.heap.nextAddress + h ∧ st'.heap.remaining = none ∧ st'.locals = s1.locals := by
  simp only [ccall, Option.map_eq_some_iff] at cost
  obtain ⟨⟨w, h'⟩, hq, rfl⟩ := cost
  have len : values.length = f.params.length := by simpa using rel.length.1
  obtain ⟨compl, completed, v, ev, cr, grown, rem⟩ :=
    func_live pure primsOk N found notOutside len inv rel hq budget fr
  have call := call_fwd argsRun found len ev cr
  obtain ⟨k, hk⟩ := ev.at
  obtain ⟨w', hw', r, inv', step⟩ := func_sim pure primsOk k found notOutside len inv
    (Nat.le_trans grown budget) rel hk cr
  have hw : pcall sp prims N c ps = some w := by rw [pcall_eq_qcall sp prims (boxCost sp), hq]; rfl
  have same := (pcall_mono sp prims N hw (Nat.le_max_left N (k + 1))).symm.trans
    (pcall_mono sp prims (k + 1) hw' (Nat.le_max_right N (k + 1)))
  simp only [Option.some.injEq] at same
  subst same
  exact ⟨w, v, _, hw, call, r, inv'.restore _, step.restore _, grown, rem, rfl⟩

end

end Lanius.Faithful
