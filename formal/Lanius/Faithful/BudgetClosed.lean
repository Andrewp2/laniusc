import Lanius.Faithful.Budget

/-! # Budget certificates of functions without arguments (F14)

A table builder such as `grammar_part_0` takes no arguments and makes
hundreds of calls in a line. `budget`'s step-by-step run of it costs a pass
over the whole body at every call. With no arguments its run is a closed
term, so the kernel evaluates it instead (`decide +kernel`):

- `qcallB`, a `qcall` that has no value where it would call a function
  `ok` rules out, and is computable, unlike `qcallG`, whose guard is a `Prop`.
  At `okW` (neither `plus` nor `times`), `qcallB progW`'s value is `qcall
  prog`'s (`qcall_of_okW`), because the two programs differ only there.
- `bclosed`: from the kernel's evaluation of `qcallB progW` at one fuel
  `D` (it has a value, its cost is `C D`, and `qcall progW` has none
  below `D`), every run of `progW` at any fuel is the self program's, at the
  cost `C n`. -/

namespace Lanius.Faithful.Budget

open Lanius.Mini
open Lanius.Faithful
open Lanius.Faithful.Termination
open Lanius.Core (Value)

/-- `qcall`, with no value at a call of a function `ok` rules out. -/
def qcallB (sp : SrcProgram) (prims : Prims) (cost : Nat → Nat) (ok : Nat → Bool) : Nat → QCalls
  | 0, _, _ => none
  | fuel + 1, callee, values =>
    if ok callee then
      if prims.isPrim callee then
        (single values).map (·, if prims.boxed.contains callee then cost callee else 0)
      else
        match sp.funcs[callee]? with
        | none => none
        | some f =>
          if values.length = f.params.length then
            qthen (qstmt (qcallB sp prims cost ok fuel) (paramEnv f.params values) f.body) fun d =>
              qfree (doneValue f.ret d)
          else none
    else none

/-- `qcallB` is `qcallG` at the guard `ok c = true`. -/
theorem qcallB_eq (sp : SrcProgram) (prims : Prims) (cost : Nat → Nat) (ok : Nat → Bool) :
    ∀ (n c : Nat) (vs : List Value),
      qcallG sp prims cost (fun c _ => ok c = true) n c vs = qcallB sp prims cost ok n c vs
  | 0, _, _ => rfl
  | n + 1, c, vs => by
    have ih : qcallG sp prims cost (fun c _ => ok c = true) n = qcallB sp prims cost ok n :=
      funext fun c => funext fun vs => qcallB_eq sp prims cost ok n c vs
    simp only [qcallG, qcallB, ih]
    by_cases hok : ok c = true
    · simp only [hok, ↓reduceIte]
      congr
    · simp only [hok, ↓reduceIte, Bool.false_eq_true]

/-- More fuel keeps every value of `qcallB`. -/
theorem qcallB_succ (sp : SrcProgram) (prims : Prims) (cost : Nat → Nat) (ok : Nat → Bool) :
    ∀ (n : Nat), QCallsLe (qcallB sp prims cost ok n) (qcallB sp prims cost ok (n + 1))
  | 0 => fun _ _ _ h => by simp [qcallB] at h
  | n + 1 => fun c vs w h => by
    simp only [qcallB] at h ⊢
    split at h
    · rename_i hok
      rw [if_pos hok]
      split at h
      · rename_i prim
        rw [if_pos prim]
        exact h
      · rename_i prim
        rw [if_neg prim]
        split at h
        · cases h
        · rename_i f hf
          try rw [hf]
          try simp only at h ⊢
          split at h
          · rename_i len
            rw [if_pos len]
            exact qthen_mono (fun _ hx => qstmt_mono (qcallB_succ sp prims cost ok n) _ hx)
              (fun _ _ hx => hx) h
          · cases h
    · cases h

theorem qcallB_add (sp : SrcProgram) (prims : Prims) (cost : Nat → Nat) (ok : Nat → Bool) (d : Nat) :
    ∀ (m : Nat), QCallsLe (qcallB sp prims cost ok d) (qcallB sp prims cost ok (m + d))
  | 0 => by rw [Nat.zero_add]; exact fun _ _ _ h => h
  | m + 1 => fun c vs w h => by
    rw [Nat.add_right_comm]
    exact qcallB_succ sp prims cost ok (m + d) c vs w (qcallB_add sp prims cost ok d m c vs w h)

/-- Neither `plus` nor `times`. -/
def okW (c : Nat) : Bool := !(c == SelfPure.ixPlus) && !(c == SelfPure.ixTimes)

theorem okW_ne {c : Nat} (h : okW c = true) : SelfPure.ixPlus ≠ c ∧ SelfPure.ixTimes ≠ c := by
  simp only [okW, Bool.and_eq_true, Bool.not_eq_true', beq_eq_false_iff_ne] at h
  exact ⟨Ne.symm h.1, Ne.symm h.2⟩

open Lanius.Faithful.SelfPanics in
/-- Away from `plus` and `times`, the programs have the same functions. -/
theorem qagrees_okW : QAgrees Self.prog progW (fun c _ => okW c = true) :=
  qagrees_trans (qagrees_wrapAt fun _ _ _ hs => absurd hs (by decide))
    (qagrees_wrapAt fun _ _ _ hs => absurd hs (by decide))

open Lanius.Faithful.SelfPanics in
/-- A run of `progW` that calls neither `plus` nor `times` is the self program's. -/
theorem qcall_of_okW {cost : Nat → Nat} {n c : Nat} {vs : List Value} {p : Value × Nat}
    (h : qcallB progW SelfPure.prims cost okW n c vs = some p) :
    qcall Self.prog SelfPure.prims cost n c vs = some p ∧ qcall progW SelfPure.prims cost n c vs = some p := by
  rw [← qcallB_eq] at h
  exact ⟨qcall_of_qcallG qagrees_okW n h, qcall_of_qcallG qagrees_refl n h⟩

open Lanius.Faithful.SelfPanics in
/-- **The budget certificate of a function without arguments**, from the
kernel's evaluation of its run at one fuel `D`. -/
theorem bclosed {ix D : Nat} {C : Nat → Nat}
    (run : (qcallB progW SelfPure.prims uc okW D ix []).isSome = true)
    (cost : (qcallB progW SelfPure.prims uc okW D ix []).map Prod.snd = some (C D))
    (stable : ∀ m, C (m + D) = C D)
    (small : ∀ m, m < D → qcall progW SelfPure.prims uc m ix [] = none)
    {n : Nat} {w : Value} {k : Nat} (h : qcall progW SelfPure.prims uc n ix [] = some (w, k)) :
    qcall Self.prog SelfPure.prims uc n ix [] = some (w, k) ∧ C n = k := by
  cases hd : qcallB progW SelfPure.prims uc okW D ix [] with
  | none => rw [hd] at run; cases run
  | some p =>
    rw [hd] at cost
    by_cases lt : n < D
    · rw [small n lt] at h
      cases h
    · obtain ⟨m, rfl⟩ : ∃ m, n = m + D := ⟨n - D, by omega⟩
      have hm := qcall_of_okW (qcallB_add progW SelfPure.prims uc okW D m ix [] p hd)
      rw [hm.2] at h
      cases h
      refine ⟨hm.1, ?_⟩
      rw [stable m]
      simp only [Option.map_some, Option.some.injEq] at cost
      exact cost.symm

end Lanius.Faithful.Budget
