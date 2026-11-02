import Lanius.Faithful.GenB.SelfBudget
import Lanius.Faithful.SelfTotal
import Lanius.Faithful.BudgetMono

/-! # The compile's bounds from the roots' preconditions (F14)

`SelfTotal`'s open premise asks that a wrapped compile (`costW`) under a
threshold `T` gives the self program's compile a value and a cost. The
budget certificates (`GenB.SelfBudget`) give that for the three roots,
`grammar` (8), `front_end_words` (7) and `compile_words` (6), each under its
precondition `Pre_F` at a budget above the run's block count (`uc`). The
certificates count blocks, the heap counts bytes (`boxCost prog`, at least 8
a block), so a run's block count is at most its heap cost
(`BudgetMono.qcall_cle`).

- `selfCost_of_pre`: a wrapped compile that costs `k < T`, with
  `front_end_words`'s precondition at `T` less `grammar`'s blocks, and
  `compile_words`'s at `T` less both, gives the self program's compile a cost.

What is left of `CompileBounded T` is those two preconditions. -/

namespace Lanius.Faithful.SelfBounded

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Faithful
open Lanius.Faithful.Self
open Lanius.Faithful.SelfRep
open Lanius.Faithful.SelfLive
open Lanius.Faithful.SelfPanics
open Lanius.Faithful.SelfTotal
open Lanius.Faithful.Budget
open Lanius.Faithful.SelfBudget

/-- Every `boxed` prim of the self program has one parameter. -/
theorem boxed_params :
    prims.boxed.all (fun c => (prog.funcs[c]?.map fun f => f.params.length) == some 1) = true := by
  decide +kernel

/-- A block costs at least one byte. -/
theorem uc_le_boxCost (c : Nat) (bx : prims.boxed.contains c = true) : uc c ≤ boxCost prog c := by
  have h := List.all_eq_true.mp boxed_params c (List.elem_iff.mp bx)
  unfold boxCost uc
  cases hf : prog.funcs[c]? with
  | none => rw [hf] at h; cases h
  | some f =>
    rw [hf] at h
    simp only [Option.map_some, beq_iff_eq, Option.some.injEq] at h
    simp only
    match hp : f.params with
    | [] => rw [hp] at h; cases h
    | [_] => simp only; omega
    | _ :: _ :: _ => rw [hp] at h; simp at h

/-- A run with a heap cost has a block count at most it, with the same value. -/
theorem uc_of_box {sp : SrcProgram} {n c : Nat} {vs : List Value} {g : Value × Nat}
    (h : qcall sp prims (boxCost prog) n c vs = some g) :
    ∃ k, qcall sp prims uc n c vs = some (g.1, k) ∧ k ≤ g.2 := by
  obtain ⟨gv, gc⟩ := g
  have hp : pcall sp prims n c vs = some gv := by
    rw [pcall_eq_qcall sp prims (boxCost prog), h]; rfl
  obtain ⟨k, hk⟩ := qcall_of_pcall uc hp
  obtain ⟨k', h1, h2⟩ := qcall_cle (fun c bx => uc_le_boxCost c bx) n c vs _ hk
  rw [h] at h1
  simp only [Option.some.injEq, Prod.mk.injEq] at h1
  obtain ⟨-, rfl⟩ := h1
  exact ⟨k, hk, h2⟩

/-- A run with a block count has a heap cost, with the same value. -/
theorem box_of_uc {sp : SrcProgram} {n c : Nat} {vs : List Value} {w : Value} {k : Nat}
    (h : qcall sp prims uc n c vs = some (w, k)) :
    ∃ k', qcall sp prims (boxCost prog) n c vs = some (w, k') := by
  obtain ⟨k', h1, -⟩ := qcall_cle (fun c bx => uc_le_boxCost c bx) n c vs _ h
  exact ⟨k', h1⟩

/-- **A wrapped compile under `T` gives the self program's compile a cost**,
where `front_end_words`'s and `compile_words`'s preconditions hold at what is
left of `T`. -/
theorem selfCost_of_pre {T N k : Nat} {W : List (BitVec 32)} (h : costW N W = some k) (lt : k < T)
    (pre7 : Pre_front_end_words N grammar W (T - Cost_grammar N))
    (pre6 : Pre_compile_words N (frontEndWords grammar W) (T - Cost_grammar N - Cost_front_end_words N grammar W)) :
    ∃ c, selfCost N W = some c := by
  simp only [costW] at h
  cases h8 : qcall progW prims (boxCost prog) N 8 [] with
  | none => rw [h8] at h; cases h
  | some g =>
    rw [h8] at h
    simp only [Option.bind_some] at h
    cases h7 : qcall progW prims (boxCost prog) N 7 [g.1, listVal W] with
    | none => rw [h7] at h; cases h
    | some fe =>
      rw [h7] at h
      simp only [Option.bind_some] at h
      cases h6 : qcall progW prims (boxCost prog) N 6 [fe.1] with
      | none => rw [h6] at h; cases h
      | some cw =>
        rw [h6] at h
        simp only [Option.bind_some, Option.some.injEq] at h
        obtain ⟨k8, u8, l8⟩ := uc_of_box h8
        obtain ⟨k7, u7, l7⟩ := uc_of_box h7
        obtain ⟨k6, u6, l6⟩ := uc_of_box h6
        obtain ⟨p8, c8, r8⟩ := bcert_grammar u8
        obtain ⟨p7, c7, r7⟩ := bcert_front_end_words u7 r8 (listVal_rep W) (b := T - Cost_grammar N)
          (by omega) pre7
        obtain ⟨p6, c6, r6⟩ := bcert_compile_words u6 r7
          (b := T - Cost_grammar N - Cost_front_end_words N grammar W) (by omega) pre6
        obtain ⟨b8, q8⟩ := box_of_uc p8
        obtain ⟨b7, q7⟩ := box_of_uc p7
        obtain ⟨b6, q6⟩ := box_of_uc p6
        exact ⟨W.length * consCost + b8 + b7 + b6, by simp [selfCost, q8, q7, q6]⟩

#print axioms selfCost_of_pre

end Lanius.Faithful.SelfBounded
