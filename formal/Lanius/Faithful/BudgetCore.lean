import Lanius.Faithful.Cost
import Lanius.Faithful.Rep
import Lanius.Faithful.Sim.Term
import Lanius.Faithful.BudgetAttr

/-! # Budget certificates: the rewrites (F14)

A budget certificate of a function says that a run of `progW` (`plus` and
`times` wrapping) that costs `k` heap blocks, `k` below a budget `b`, is a run
of the self program with the same value and cost, when the function's Lean
precondition `Pre` holds at `b`: every `plus` or `times` its Nat evaluation
reaches with less than `b` allocated before it stays below `2 ^ 64`. The
cost is counted in blocks (`uc`, one per `boxed` call); `Cost` is its Lean
model.

This file has the rewrites the certificates run the cost semantics with, for
any program; `Budget.lean` adds the self program's (`progW`, `plus`, `times`).
The generated certificates import only this one, not the self program, so
that a change to one function rebuilds only the certificates that reach it.
They keep `qthen` folded, so that taking a call off a run (`qthen_peel`)
says how its cost adds up: `k = c + k'`, `c` the call's and `k'` the rest's.
That is what bounds the budget each callee gets. -/

namespace Lanius.Faithful.Budget

open Lanius.Mini
open Lanius.Faithful
open Lanius.Faithful.Termination
open Lanius.Core (Value)

/-- One block per `boxed` call. -/
def uc : Nat → Nat := fun _ => 1

section
variable {α β γ : Type}

@[budget_rule] theorem qthen_some (x : α) (c : Nat) (k : α → Option (β × Nat)) :
    qthen (some (x, c)) k = addC c (k x) := rfl

@[budget_rule] theorem qthen_none (k : α → Option (β × Nat)) : qthen (none : Option (α × Nat)) k = none := rfl

@[budget_rule] theorem addC_some (c : Nat) (x : α) (d : Nat) : addC c (some (x, d)) = some (x, c + d) := rfl

@[budget_rule] theorem addC_none (c : Nat) : addC c (none : Option (α × Nat)) = none := rfl

@[budget_rule] theorem addC_zero (o : Option (α × Nat)) : addC 0 o = o := by
  cases o <;> simp [addC]

@[budget_rule] theorem addC_addC (a b : Nat) (o : Option (α × Nat)) : addC a (addC b o) = addC (a + b) o := by
  cases o <;> simp [addC, Nat.add_assoc]

@[budget_rule] theorem qthen_addC (c : Nat) (o : Option (α × Nat)) (k : α → Option (β × Nat)) :
    qthen (addC c o) k = addC c (qthen o k) := by
  cases o with
  | none => rfl
  | some p =>
    simp only [addC, qthen, Option.map_some, Option.bind_some, Option.map_map]
    congr 1
    funext q
    simp [Nat.add_assoc]

@[budget_rule] theorem qthen_assoc (o : Option (α × Nat)) (g : α → Option (β × Nat)) (k : β → Option (γ × Nat)) :
    qthen (qthen o g) k = qthen o fun x => qthen (g x) k := by
  cases o with
  | none => rfl
  | some p =>
    simp only [qthen, Option.bind_some]
    exact qthen_addC p.2 (g p.1) k

@[budget_rule] theorem qfree_some (x : α) : qfree (some x) = some (x, 0) := rfl

@[budget_rule] theorem qfree_none : qfree (none : Option α) = none := rfl

/-- A run that starts with `o`: `o`'s result and cost, and the rest's. -/
theorem qthen_peel {o : Option (α × Nat)} {k : α → Option (β × Nat)} {w : β} {c : Nat}
    (h : qthen o k = some (w, c)) : ∃ x c₁ c₂, o = some (x, c₁) ∧ k x = some (w, c₂) ∧ c = c₁ + c₂ := by
  cases o with
  | none => cases h
  | some p =>
    obtain ⟨x, c₁⟩ := p
    simp only [qthen_some, addC] at h
    cases hk : k x with
    | none => rw [hk] at h; cases h
    | some q =>
      rw [hk] at h
      simp only [Option.map_some, Option.some.injEq, Prod.mk.injEq] at h
      obtain ⟨rfl, rfl⟩ := h
      exact ⟨x, c₁, q.2, rfl, by rw [hk], rfl⟩

theorem addC_peel {c : Nat} {o : Option (α × Nat)} {w : α} {k : Nat} (h : addC c o = some (w, k)) :
    ∃ k', o = some (w, k') ∧ k = c + k' := by
  cases o with
  | none => cases h
  | some p =>
    simp only [addC, Option.map_some, Option.some.injEq, Prod.mk.injEq] at h
    obtain ⟨rfl, rfl⟩ := h
    exact ⟨p.2, rfl, rfl⟩

end

@[budget_rule] theorem Out.qthen_next (rest : Lanius.Faithful.Env → Option (Out × Nat)) (env : Lanius.Faithful.Env) :
    Out.qthen rest (.next env) = rest env := rfl

@[budget_rule] theorem Out.qthen_brk (rest : Lanius.Faithful.Env → Option (Out × Nat)) (env : Lanius.Faithful.Env) :
    Out.qthen rest (.brk env) = some (.brk env, 0) := rfl

@[budget_rule] theorem Out.qthen_cont (rest : Lanius.Faithful.Env → Option (Out × Nat)) (env : Lanius.Faithful.Env) :
    Out.qthen rest (.cont env) = some (.cont env, 0) := rfl

@[budget_rule] theorem Out.qthen_ret (rest : Lanius.Faithful.Env → Option (Out × Nat)) (v : Option Value) :
    Out.qthen rest (.ret v) = some (.ret v, 0) := rfl

@[budget_rule] theorem qpop_some (o : Out) (c : Nat) : qpop (some (o, c)) = some (o.pop, c) := rfl

@[budget_rule] theorem qpop_none : qpop none = none := rfl

@[budget_rule] theorem Out.pop_next (env : Lanius.Faithful.Env) : Out.pop (.next env) = .next env.tail := rfl

@[budget_rule] theorem Out.pop_brk (env : Lanius.Faithful.Env) : Out.pop (.brk env) = .brk env.tail := rfl

@[budget_rule] theorem Out.pop_cont (env : Lanius.Faithful.Env) : Out.pop (.cont env) = .cont env.tail := rfl

@[budget_rule] theorem Out.pop_ret (v : Option Value) : Out.pop (.ret v) = .ret v := rfl

@[budget_rule] theorem qarms_nil (call : QCalls) (env : Lanius.Faithful.Env) (v : Value) (id k : Nat)
    (values : List SrcEff) : qarms call env v id k [] values = none := by
  cases values <;> rfl

@[budget_rule] theorem qarms_none (call : QCalls) (env : Lanius.Faithful.Env) (v : Value) (id k : Nat) (bs : List Nat)
    (rest : List (List Nat)) : qarms call env v id k (bs :: rest) [] = none := rfl

/-- The arm of the scrutinee's variant runs with its payload bound. -/
@[budget_rule] theorem qarms_hit (call : QCalls) (env : Lanius.Faithful.Env) (id k : Nat) (vs : List Value)
    (bs : List Nat) (rest : List (List Nat)) (value : SrcEff) (values : List SrcEff) (len : bs.length = vs.length) :
    qarms call env (.enumeration id k vs) id k (bs :: rest) (value :: values) =
      qeff call (env.bindAll (bs.zip vs)) value := by
  simp [qarms, Lanius.Semantics.matchPattern, Lanius.Faithful.matchPatterns_binds, len]

/-- An arm of another variant is passed over. -/
@[budget_rule] theorem qarms_miss (call : QCalls) (env : Lanius.Faithful.Env) (id k k' : Nat) (vs : List Value)
    (bs : List Nat) (rest : List (List Nat)) (value : SrcEff) (values : List SrcEff) (ne : k ≠ k') :
    qarms call env (.enumeration id k' vs) id k (bs :: rest) (value :: values) =
      qarms call env (.enumeration id k' vs) id (k + 1) rest values := by
  have : (k == k') = false := by simpa using ne
  simp [qarms, Lanius.Semantics.matchPattern, this]

/-- How a certificate unfolds a call of a function that is not a prim. -/
theorem qcall_succ {sp : SrcProgram} {prims : Prims} {cost : Nat → Nat} {n c : Nat} {vs : List Value}
    {f : SrcFunc} (np : prims.isPrim c = false) (found : sp.funcs[c]? = some f) :
    qcall sp prims cost (n + 1) c vs =
      if vs.length = f.params.length then
        qthen (qstmt (qcall sp prims cost n) n (paramEnv f.params vs) f.body) fun o => qfree (outValue f.ret o)
      else none := by
  simp [qcall, np, found]

/-- A prim's call: its argument, at its cost. -/
theorem qcall_prim {sp : SrcProgram} {prims : Prims} {cost : Nat → Nat} {n c : Nat} {v : Value}
    (p : prims.isPrim c = true) :
    qcall sp prims cost (n + 1) c [v] = some (v, if prims.boxed.contains c then cost c else 0) := by
  simp [qcall, p, single]

@[budget_rule] theorem qcall_zero (sp : SrcProgram) (prims : Prims) (cost : Nat → Nat) (c : Nat) (vs : List Value) :
    qcall sp prims cost 0 c vs = none := rfl

/-- A prim's call does not look at the program. -/
theorem qcall_prim_eq {sp sp' : SrcProgram} {prims : Prims} {cost : Nat → Nat} {n c : Nat} {vs : List Value}
    (p : prims.isPrim c = true) : qcall sp prims cost n c vs = qcall sp' prims cost n c vs := by
  cases n with
  | zero => rfl
  | succ n => simp [qcall, p]

theorem pcall_of_q {sp : SrcProgram} {prims : Prims} {cost : Nat → Nat} {n c : Nat} {vs : List Value} {w : Value}
    {k : Nat} (h : qcall sp prims cost n c vs = some (w, k)) : pcall sp prims n c vs = some w := by
  rw [pcall_eq_qcall sp prims cost, h]
  rfl

/-- A certificate's step past a call: the call's result `r` at cost `c₁`, then
the rest of the body at cost `c₂`. The cost's equation stays as it is. -/
theorem run_step {β : Type} {o : Option (Value × Nat)} {K : Value → Option (β × Nat)} {r : Value} {c₁ c₂ : Nat}
    {w : β} {C : Prop} (ho : o = some (r, c₁)) (h : K r = some (w, c₂) ∧ C) : qthen o K = some (w, c₁ + c₂) ∧ C := by
  subst ho
  refine ⟨?_, h.2⟩
  rw [qthen_some, h.1, addC_some]

/-- A step past a cost (a `boxed` prim's). -/
theorem addC_step {β : Type} {o : Option (β × Nat)} {c c₂ : Nat} {w : β} {C : Prop} (h : o = some (w, c₂) ∧ C) :
    addC c o = some (w, c + c₂) ∧ C := by
  refine ⟨?_, h.2⟩
  rw [h.1, addC_some]

/-! ## `plus` and `times`

Their precondition is that they do not wrap; they cost nothing. -/

/-- `plus` does not wrap. -/
def Pre_plus (_n x y _b : Nat) : Prop := x + y < 2 ^ 64

/-- `times` does not wrap. -/
def Pre_times (_n x y _b : Nat) : Prop := x * y < 2 ^ 64

/-- A budget certificate's statement for `plus` (`op` is `+`) or `times`. -/
abbrev BStmt_plus (spW sp : SrcProgram) (prims : Prims) (ix n : Nat) : Prop :=
  ∀ {x0 x1 : Nat} {v0 v1 w : Value} {k b : Nat},
    qcall spW prims uc n ix [v0, v1] = some (w, k) → RepNat x0 v0 → RepNat x1 v1 → k < b → Pre_plus n x0 x1 b →
    qcall sp prims uc n ix [v0, v1] = some (w, k) ∧ 0 = k ∧ RepNat (x0 + x1) w

abbrev BStmt_times (spW sp : SrcProgram) (prims : Prims) (ix n : Nat) : Prop :=
  ∀ {x0 x1 : Nat} {v0 v1 w : Value} {k b : Nat},
    qcall spW prims uc n ix [v0, v1] = some (w, k) → RepNat x0 v0 → RepNat x1 v1 → k < b → Pre_times n x0 x1 b →
    qcall sp prims uc n ix [v0, v1] = some (w, k) ∧ 0 = k ∧ RepNat (x0 * x1) w

end Lanius.Faithful.Budget
