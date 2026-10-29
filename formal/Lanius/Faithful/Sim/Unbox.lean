import Lanius.Faithful.Sim.Slice

/-! # Core runs of `unbox<T>(box)`

`unbox` reads element 0 of the one-element view of the box's storage: the
value `boxed` wrote there, which means the box's pure value. -/

namespace Lanius.Faithful

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion evalExpr evalExprs execStmt restoreLocals readNativeValue)

/-- Element 0 of a view whose word 0 is the storage's last word. -/
theorem elementAddress_zero {P : Core.Program} {T : Core.Ty} {a w : Nat}
    (kind : (∃ id, T = .structure id) ∨ ∃ id, T = .enumeration id) (words : NativeLayout.valueWords? P T = some w)
    (pos : 0 < w) : Semantics.rawSliceElementAddress? P T (a + 8 * w - 8) 0 = .ok (a + 8 * w - 8) := by
  rcases kind with ⟨id, rfl⟩ | ⟨id, rfl⟩ <;>
  · simp only [Semantics.rawSliceElementAddress?, words, NativeLayout.elementBase?]
    rw [if_neg (by
      simp only [NativeLayout.wordBytes, Bool.or_eq_true, beq_iff_eq]
      rintro (bad | bad)
      · omega
      · exact absurd (of_decide_eq_true bad) (by omega))]
    simp only [Nat.zero_mul, Nat.sub_zero]
    rfl

theorem raw_read_zero {P : Core.Program} {s : State} {T : Core.Ty} {a w : Nat} {v : Value}
    (kind : (∃ id, T = .structure id) ∨ ∃ id, T = .enumeration id) (words : NativeLayout.valueWords? P T = some w)
    (pos : 0 < w) (h : Semantics.readRawSliceIndex P s T (a + 8 * w - 8) 1 0 = .ok v) :
    readNativeValue NativeLayout.maxDepth P s.heap T (a + 8 * w - 8) = .ok v := by
  simp only [Semantics.readRawSliceIndex, show ¬ (0 ≥ 1) by decide, if_false,
    elementAddress_zero kind words pos] at h
  exact h

section
variable {sp : SrcProgram} {prims : Prims} {m : Nat}

/-- A run of `unbox<t>` on a box: the pure value the box means, the heap as it was. -/
theorem unbox_sim {c : Nat} {t : SrcType} {id slice : Nat} {values ps : List Value} {st completed : State}
    {compl : Completion} {v : Value}
    (sliceFound : sp.funcs[slice]? = some (sliceFunc t)) (el : wordElement sp.decls t = true)
    (box : boxElem sp prims id = some t) (prim : prims.isPrim c = true) (inv : Inv st)
    (args : VRels sp.toCore (boxElem sp prims) st.heap ((unboxFunc t id slice).params.map SrcParam.ty) values ps)
    (run : execStmt m sp.toCore (({ st with locals := [] } : State).bindLocals
      (paramBindings (unboxFunc t id slice).params values)) (unboxFunc t id slice).body.toCore = .done compl completed)
    (result : CallResult (unboxFunc t id slice).ret compl v) :
    ∃ w, pcall sp prims (m + 1) c ps = some w ∧ VRel sp.toCore (boxElem sp prims) completed.heap t v w ∧
      Inv completed ∧ Step st completed := by
  obtain ⟨-, kind⟩ := sliceFrom_word el
  simp only [unboxFunc, List.map_cons, List.map_nil] at args
  cases args with
  | cons r rest =>
  cases rest with
  | nil =>
  rename_i x p
  cases r with
  | scalar s => exact s.elim
  | struct none _ => rw [box] at none; cases none
  | box found wv pos room ranged read rel =>
  rename_i t' a w y
  rw [box, Option.some.injEq] at found
  subst found
  have pc : pcall sp prims (m + 1) c [p] = some p := by simp only [pcall, prim, if_true, single]
  refine ⟨p, pc, ?_⟩
  have start : (({ st with locals := [] } : State).bindLocals (paramBindings (unboxFunc t id slice).params
      [.structure id [.pointer a]])) = ({ st with locals := [] } : State).bindLocal 9 (.structure id [.pointer a]) :=
    rfl
  rw [start] at run
  have inv0 := inv.clear.bindLocal 9 (.structure id [.pointer a])
  simp only [unboxFunc, SrcStmt.toCore, SrcEff.toCore, SrcExpr.toCore, SrcType.toCore,
    List.map_cons, List.map_nil, bv_zero, bv_one] at run
  obtain ⟨_, sv, s1, s2, -, call, body, rfl⟩ := letLocal_inv run
  have storage : ∀ {j u s}, evalExpr j sp.toCore (({ st with locals := [] } : State).bindLocal 9
      (.structure id [.pointer a])) (.field (.local 9) 0) = .done u s →
      u = .pointer a ∧ s = ({ st with locals := [] } : State).bindLocal 9 (.structure id [.pointer a]) := by
    intro j u s h
    obtain ⟨_, sid, fields, -, base, hf⟩ := field_inv h
    obtain ⟨hv, rfl⟩ := local_eval (local?_bindLocal_self inv.clear 9 _) base
    simp only [Value.structure.injEq] at hv
    obtain ⟨rfl, rfl⟩ := hv
    simp only [List.getElem?_cons_zero, Option.some.injEq] at hf
    exact ⟨hf.symm, rfl⟩
  obtain ⟨w', hw', -, rfl, same, -⟩ := slice_call sliceFound el inv0 storage call
  rw [wv, Option.some.injEq] at hw'
  subst hw'
  rw [show (a + (8 * w - 8)) % 2 ^ 64 = a + 8 * w - 8 by rw [Nat.mod_eq_of_lt (by omega)]; omega] at body
  obtain ⟨_, rv, -, idx, rfl⟩ := return_inv body
  obtain ⟨_, bv, s3, -, baseRun, rest⟩ := index_inv idx
  obtain ⟨rfl, rfl⟩ := local_eval (local?_bindLocal_self same.inv 39 _) baseRun
  obtain ⟨iv, posn, ir, hi, hr⟩ := rest _ _ _ rfl
  obtain ⟨rfl, rfl⟩ := value_inv ir
  simp only [Semantics.integerIndex, show ¬ ((0 : Int) < 0) by decide, if_false, Except.ok.injEq] at hi
  subst hi
  have hr' := raw_read_zero kind wv pos hr
  have heap : (s1.bindLocal 39 (.rawSlice t.toCore (a + 8 * w - 8) 1)).heap = st.heap := same.heap
  rw [heap, read, Except.ok.injEq] at hr'
  subst hr'
  simp only [CallResult] at result
  subst result
  have done := same.bind 39 (.rawSlice t.toCore (a + 8 * w - 8) 1) |>.restore s1
  refine ⟨?_, done.inv, ?_⟩
  · show VRel sp.toCore (boxElem sp prims) (restoreLocals s1 _).heap t _ p
    rw [done.heap]
    exact rel
  · exact (((Step.clear st).trans (Step.bindLocal _ 9 _)).trans done.step)

end

end Lanius.Faithful
