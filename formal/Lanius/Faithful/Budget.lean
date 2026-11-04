module

public import Lanius.Faithful.SelfAgree
public import Lanius.Faithful.BudgetCore
import all Lanius.Faithful.Gen.SelfSrc1
import all Lanius.Faithful.Gen.SelfSrc4

@[expose] public section

/-! # Budget certificates: the self program's (F14)

`progW`'s functions, and the budget certificates of the prelude's `plus` and
`times` at the self program (the rewrites are in `BudgetCore.lean`). -/

namespace Lanius.Faithful.Budget

open Lanius.Mini
open Lanius.Faithful
open Lanius.Faithful.Termination
open Lanius.Core (Value)

open Lanius.Faithful.SelfPanics in
/-- `progW` has the self program's functions but `plus` and `times`. -/
theorem fnW_of {c : Nat} {f : SrcFunc} (h1 : SelfPure.ixPlus ≠ c) (h2 : SelfPure.ixTimes ≠ c)
    (fn : Self.prog.funcs[c]? = some f) : progW.funcs[c]? = some f := by
  rw [progW, wrapAt_ne h2, wrapAt_ne h1, fn]

open Lanius.Faithful.Self Lanius.Faithful.SelfRep Lanius.Faithful.SelfCert Lanius.Faithful.SelfPanics in
theorem bcert_plus {n : Nat} : BStmt_plus progW prog prims 75 n := by
  intro x0 x1 v0 v1 w k b h r0 r1 _ pre
  cases r0 with | mk l0 =>
  cases r1 with | mk l1 =>
  cases n with
  | zero => cases h
  | succ n =>
    have fnW : progW.funcs[75]? = some (wrapFunc .plus (src_plus 50)) := by
      rw [progW, wrapAt_ne (show SelfPure.ixTimes ≠ 75 by decide), wrapAt_get,
        if_pos (show SelfPure.ixPlus = 75 from rfl), fn_plus]
      rfl
    have lt : x0 + x1 < 2 ^ 64 := pre
    rw [qcall_succ np_plus fnW] at h
    rw [qcall_succ np_plus fn_plus]
    simp only [wrapFunc, src_plus, List.length_cons, List.length_nil, if_true] at h ⊢
    have hw := SelfAgree.qplus_wrapped (qcall progW prims uc n) n x0 x1
    have hp := SelfAgree.qplus_body (qcall prog prims uc n) n lt
    simp only [wrapFunc, src_plus] at hw hp
    rw [hw, Nat.mod_eq_of_lt lt] at h
    rw [hp]
    obtain ⟨rfl, rfl⟩ := Prod.mk.inj (Option.some.inj h)
    exact ⟨rfl, rfl, RepNat.mk lt⟩

open Lanius.Faithful.Self Lanius.Faithful.SelfRep Lanius.Faithful.SelfCert Lanius.Faithful.SelfPanics in
theorem bcert_times {n : Nat} : BStmt_times progW prog prims 105 n := by
  intro x0 x1 v0 v1 w k b h r0 r1 _ pre
  cases r0 with | mk l0 =>
  cases r1 with | mk l1 =>
  cases n with
  | zero => cases h
  | succ n =>
    have fnW : progW.funcs[105]? = some (wrapFunc .times (src_times 50)) := by
      rw [progW, wrapAt_get, if_pos (show SelfPure.ixTimes = 105 from rfl),
        wrapAt_ne (show SelfPure.ixPlus ≠ 105 by decide), fn_times]
      rfl
    have lt : x0 * x1 < 2 ^ 64 := pre
    rw [qcall_succ np_times fnW] at h
    rw [qcall_succ np_times fn_times]
    simp only [wrapFunc, src_times, List.length_cons, List.length_nil, if_true] at h ⊢
    have hw := SelfAgree.qtimes_wrapped (qcall progW prims uc n) n x0 x1
    have hp := SelfAgree.qtimes_body (qcall prog prims uc n) n lt
    simp only [wrapFunc, src_times] at hw hp
    rw [hw, Nat.mod_eq_of_lt lt] at h
    rw [hp]
    obtain ⟨rfl, rfl⟩ := Prod.mk.inj (Option.some.inj h)
    exact ⟨rfl, rfl, RepNat.mk lt⟩

end Lanius.Faithful.Budget
