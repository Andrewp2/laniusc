module

public import Lanius.Faithful.Fwd.Expr

@[expose] public section

/-! # Forward: the Core steps effects and statements take

Each lemma runs one Core construct forward: its parts complete from some
fuel on, so it does, one fuel later. -/

namespace Lanius.Faithful

/-- `omega` on heap addresses: `Address` is `Nat`, which `omega` does not
see through. -/
macro "aomega" : tactic => `(tactic| ((try simp only [Lanius.Address] at *); omega))

open Lanius.Mini
open Lanius.Core (Value)
open Lanius.Semantics (State Completion Outcome evalExpr evalExprs evalMatchArms execStmt restoreLocals)

section
variable {P : Core.Program} {st : State}

theorem struct_fwd {id : Nat} {es : List Core.Expr} {vs : List Value} {s : State}
    (sub : Ev (fun k => evalExprs k P st es) vs s) :
    Ev (fun k => evalExpr k P st (.structValue id es)) (.structure id vs) s := by
  obtain ⟨K, hK⟩ := sub
  refine ⟨K + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [evalExpr, hK j (by omega)]

theorem enum_fwd {id variant : Nat} {es : List Core.Expr} {vs : List Value} {s : State}
    (sub : Ev (fun k => evalExprs k P st es) vs s) :
    Ev (fun k => evalExpr k P st (.enumValue id variant es)) (.enumeration id variant vs) s := by
  obtain ⟨K, hK⟩ := sub
  refine ⟨K + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [evalExpr, hK j (by omega)]

theorem match_fwd {e : Core.Expr} {arms : List (Core.Pattern × Core.Expr)} {sv v : Value} {s1 s2 : State}
    (scrutinee : Ev (fun k => evalExpr k P st e) sv s1) (rest : Ev (fun k => evalMatchArms k P s1 sv arms) v s2) :
    Ev (fun k => evalExpr k P st (.matchValue e arms)) v s2 := by
  obtain ⟨K1, h1⟩ := scrutinee
  obtain ⟨K2, h2⟩ := rest
  refine ⟨max K1 K2 + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [evalExpr, h1 j (by omega), h2 j (by omega)]

theorem arms_skip_fwd {sv v : Value} {pat : Core.Pattern} {body : Core.Expr} {arms : List (Core.Pattern × Core.Expr)}
    {s : State} (none : Semantics.matchPattern pat sv = none) (rest : Ev (fun k => evalMatchArms k P st sv arms) v s) :
    Ev (fun k => evalMatchArms k P st sv ((pat, body) :: arms)) v s := by
  obtain ⟨K, hK⟩ := rest
  refine ⟨K + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [evalMatchArms, none, hK j (by omega)]

theorem arms_hit_fwd {sv v : Value} {pat : Core.Pattern} {body : Core.Expr} {arms : List (Core.Pattern × Core.Expr)}
    {bs : List (Nat × Value)} {s : State} (found : Semantics.matchPattern pat sv = some bs)
    (run : Ev (fun k => evalExpr k P (st.bindLocals bs) body) v s) :
    Ev (fun k => evalMatchArms k P st sv ((pat, body) :: arms)) v (restoreLocals st s) := by
  obtain ⟨K, hK⟩ := run
  refine ⟨K + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [evalMatchArms, found, hK j (by omega), Semantics.restoreOutcomeLocals]

theorem assert_fwd {e : Core.Expr} {s : State} (sub : Ev (fun k => evalExpr k P st e) (.boolean true) s) :
    Ev (fun k => evalExpr k P st (.intrinsic .assert e)) .unit s := by
  obtain ⟨K, hK⟩ := sub
  refine ⟨K + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp [evalExpr, hK j (by omega)]

/-! ## Statements -/

theorem skip_fwd : Ev (fun k => execStmt k P st .skip) .next st :=
  ⟨1, fun k hk => by
    obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
    simp [execStmt]⟩

theorem expression_fwd {e : Core.Expr} {v : Value} {s : State} (sub : Ev (fun k => evalExpr k P st e) v s) :
    Ev (fun k => execStmt k P st (.expression e)) .next s := by
  obtain ⟨K, hK⟩ := sub
  refine ⟨K + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [execStmt, hK j (by omega)]

theorem letLocal_fwd {id : Nat} {ty : Core.Ty} {e : Core.Expr} {body : Core.Stmt} {v : Value} {c : Completion}
    {s1 s2 : State} (value : Ev (fun k => evalExpr k P st e) v s1)
    (rest : Ev (fun k => execStmt k P (s1.bindLocal id v) body) c s2) :
    Ev (fun k => execStmt k P st (.letLocal id ty e body)) c (restoreLocals s1 s2) := by
  obtain ⟨K1, h1⟩ := value
  obtain ⟨K2, h2⟩ := rest
  refine ⟨max K1 K2 + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [execStmt, h1 j (by omega), h2 j (by omega), Semantics.restoreOutcomeLocals]

theorem sequence_next_fwd {a b : Core.Stmt} {c : Completion} {s1 s2 : State}
    (first : Ev (fun k => execStmt k P st a) .next s1) (second : Ev (fun k => execStmt k P s1 b) c s2) :
    Ev (fun k => execStmt k P st (.sequence a b)) c s2 := by
  obtain ⟨K1, h1⟩ := first
  obtain ⟨K2, h2⟩ := second
  refine ⟨max K1 K2 + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [execStmt, h1 j (by omega), h2 j (by omega)]

theorem sequence_ret_fwd {a b : Core.Stmt} {r : Option Value} {s1 : State}
    (first : Ev (fun k => execStmt k P st a) (.returned r) s1) :
    Ev (fun k => execStmt k P st (.sequence a b)) (.returned r) s1 := by
  obtain ⟨K, hK⟩ := first
  refine ⟨K + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [execStmt, hK j (by omega)]

/-- A sequence whose first statement ends other than going on ends so. -/
theorem sequence_stop_fwd {a b : Core.Stmt} {c : Completion} {s1 : State} (stop : c ≠ .next)
    (first : Ev (fun k => execStmt k P st a) c s1) :
    Ev (fun k => execStmt k P st (.sequence a b)) c s1 := by
  obtain ⟨K, hK⟩ := first
  refine ⟨K + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  cases c with
  | next => exact absurd rfl stop
  | breakLoop => simp only [execStmt, hK j (by omega)]
  | continueLoop => simp only [execStmt, hK j (by omega)]
  | returned r => simp only [execStmt, hK j (by omega)]

theorem if_fwd {cond : Core.Expr} {a b : Core.Stmt} {x : Bool} {c : Completion} {s1 s2 : State}
    (test : Ev (fun k => evalExpr k P st cond) (.boolean x) s1)
    (branch : Ev (fun k => execStmt k P s1 (if x then a else b)) c s2) :
    Ev (fun k => execStmt k P st (.ifThenElse cond a b)) c s2 := by
  obtain ⟨K1, h1⟩ := test
  obtain ⟨K2, h2⟩ := branch
  refine ⟨max K1 K2 + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  have e2 := h2 j (by omega)
  cases x with
  | true => simp only [execStmt, h1 j (by omega)]; simpa using e2
  | false => simp only [execStmt, h1 j (by omega)]; simpa using e2

theorem while_false_fwd {cond : Core.Expr} {body : Core.Stmt} {s1 : State}
    (test : Ev (fun k => evalExpr k P st cond) (.boolean false) s1) :
    Ev (fun k => execStmt k P st (.whileLoop cond body)) .next s1 := by
  obtain ⟨K, hK⟩ := test
  refine ⟨K + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [execStmt, hK j (by omega)]

/-- A loop whose body ends `next` or `continue` goes on as the loop from where the body left. -/
theorem while_again_fwd {cond : Core.Expr} {body : Core.Stmt} {cb c : Completion} {s1 s2 s3 : State}
    (test : Ev (fun k => evalExpr k P st cond) (.boolean true) s1)
    (first : Ev (fun k => execStmt k P s1 body) cb s2) (again : cb = .next ∨ cb = .continueLoop)
    (rest : Ev (fun k => execStmt k P s2 (.whileLoop cond body)) c s3) :
    Ev (fun k => execStmt k P st (.whileLoop cond body)) c s3 := by
  obtain ⟨K1, h1⟩ := test
  obtain ⟨K2, h2⟩ := first
  obtain ⟨K3, h3⟩ := rest
  refine ⟨max K1 (max K2 K3) + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  rcases again with rfl | rfl
  · simp only [execStmt, h1 j (by omega), h2 j (by omega), h3 j (by omega)]
  · simp only [execStmt, h1 j (by omega), h2 j (by omega), h3 j (by omega)]

theorem while_break_fwd {cond : Core.Expr} {body : Core.Stmt} {s1 s2 : State}
    (test : Ev (fun k => evalExpr k P st cond) (.boolean true) s1)
    (first : Ev (fun k => execStmt k P s1 body) .breakLoop s2) :
    Ev (fun k => execStmt k P st (.whileLoop cond body)) .next s2 := by
  obtain ⟨K1, h1⟩ := test
  obtain ⟨K2, h2⟩ := first
  refine ⟨max K1 K2 + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [execStmt, h1 j (by omega), h2 j (by omega)]

theorem while_ret_fwd {cond : Core.Expr} {body : Core.Stmt} {r : Option Value} {s1 s2 : State}
    (test : Ev (fun k => evalExpr k P st cond) (.boolean true) s1)
    (first : Ev (fun k => execStmt k P s1 body) (.returned r) s2) :
    Ev (fun k => execStmt k P st (.whileLoop cond body)) (.returned r) s2 := by
  obtain ⟨K1, h1⟩ := test
  obtain ⟨K2, h2⟩ := first
  refine ⟨max K1 K2 + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [execStmt, h1 j (by omega), h2 j (by omega)]

theorem break_fwd : Ev (fun k => execStmt k P st .breakLoop) .breakLoop st :=
  ⟨1, fun k hk => by
    obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
    simp only [execStmt]⟩

theorem continue_fwd : Ev (fun k => execStmt k P st .continueLoop) .continueLoop st :=
  ⟨1, fun k hk => by
    obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
    simp only [execStmt]⟩

theorem return_fwd {e : Core.Expr} {v : Value} {s : State} (sub : Ev (fun k => evalExpr k P st e) v s) :
    Ev (fun k => execStmt k P st (.returnValue (some e))) (.returned (some v)) s := by
  obtain ⟨K, hK⟩ := sub
  refine ⟨K + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  simp only [execStmt, hK j (by omega)]

theorem returnUnit_fwd : Ev (fun k => execStmt k P st (.returnValue none)) (.returned none) st :=
  ⟨1, fun k hk => by
    obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
    simp [execStmt]⟩

end

/-- A call of one of `sp`'s functions: its arguments complete, then its body
on fresh locals does. -/
theorem call_fwd {sp : SrcProgram} {st afterArgs completed : State} {callee : Nat} {args : List Core.Expr}
    {f : SrcFunc} {values : List Value} {c : Completion} {v : Value}
    (argsRun : Ev (fun k => evalExprs k sp.toCore st args) values afterArgs)
    (found : sp.funcs[callee]? = some f) (len : values.length = f.params.length)
    (body : Ev (fun k => execStmt k sp.toCore (({ afterArgs with locals := [] } : State).bindLocals
      (paramBindings f.params values)) f.body.toCore) c completed)
    (result : CallResult f.ret c v) :
    Ev (fun k => evalExpr k sp.toCore st (.call callee args)) v (restoreLocals afterArgs completed) := by
  obtain ⟨K1, h1⟩ := argsRun
  obtain ⟨K2, h2⟩ := body
  refine ⟨max K1 K2 + 1, fun k hk => ?_⟩
  obtain ⟨j, rfl⟩ : ∃ j, k = j + 1 := ⟨k - 1, by omega⟩
  have e2 := h2 j (by omega)
  simp only [evalExpr, h1 j (by omega), SrcProgram.function?_toCore, found, SrcFunc.toCore,
    bindParameters_eq _ _ len, e2]
  cases c with
  | next =>
    obtain ⟨hr, rfl⟩ := result
    simp [hr, SrcType.toCore]
  | returned w =>
    cases w with
    | none =>
      obtain ⟨hr, rfl⟩ := result
      simp [hr, SrcType.toCore]
    | some w =>
      subst result
      rfl
  | breakLoop => exact result.elim
  | continueLoop => exact result.elim

end Lanius.Faithful
