import Lanius.Semantics
import Std.Tactic

namespace Lanius

open Lanius.Core
open Lanius.Semantics

/-! # Runtime program agreement

Structural Core execution observes a `Program` through only its target,
constant lookup, and function lookup.  This relation captures exactly that
runtime surface.  It permits a function proved in one checked compilation
unit to execute in a checked merged program without requiring the two program
records—or unrelated declarations—to be identical.
-/

structure Core.Program.RuntimeAgrees (first second : Program) : Prop where
  target : first.target = second.target
  constant : ∀ id, first.constant? id = second.constant? id
  function : ∀ id, first.function? id = second.function? id

namespace Core.Program.RuntimeAgrees

theorem refl (program : Program) : program.RuntimeAgrees program :=
  ⟨rfl, fun _ => rfl, fun _ => rfl⟩

theorem symm {first second : Program}
    (agreement : RuntimeAgrees first second) :
    second.RuntimeAgrees first :=
  ⟨agreement.target.symm, fun id => (agreement.constant id).symm,
    fun id => (agreement.function id).symm⟩

theorem trans {first second third : Program}
    (firstSecond : RuntimeAgrees first second)
    (secondThird : second.RuntimeAgrees third) : first.RuntimeAgrees third :=
  ⟨firstSecond.target.trans secondThird.target,
    fun id => (firstSecond.constant id).trans (secondThird.constant id),
    fun id => (firstSecond.function id).trans (secondThird.function id)⟩

private structure AtFuel (fuel : Nat) (first second : Program) : Prop where
  evalExpr : ∀ state expression,
    evalExpr fuel first state expression = evalExpr fuel second state expression
  evalExprs : ∀ state expressions,
    evalExprs fuel first state expressions =
      evalExprs fuel second state expressions
  evalMatchArms : ∀ state value arms,
    evalMatchArms fuel first state value arms =
      evalMatchArms fuel second state value arms
  evalPlace : ∀ state place,
    evalPlace fuel first state place = evalPlace fuel second state place
  execForValues : ∀ state id values body,
    execForValues fuel first state id values body =
      execForValues fuel second state id values body
  execForRange : ∀ state id current stop inclusive body,
    execForRange fuel first state id current stop inclusive body =
      execForRange fuel second state id current stop inclusive body
  execStmt : ∀ state statement,
    execStmt fuel first state statement = execStmt fuel second state statement

private theorem atFuel (agreement : first.RuntimeAgrees second) :
    ∀ fuel, AtFuel fuel first second := by
  intro fuel
  induction fuel with
  | zero =>
      constructor <;> intros <;>
        simp [evalExpr, evalExprs, evalMatchArms, evalPlace, execForValues,
          execForRange, execStmt]
  | succ fuel induction =>
      constructor
      · intro state expression
        cases expression <;>
          simp only [evalExpr] <;>
          simp only [induction.evalExpr, induction.evalExprs,
            induction.evalMatchArms, induction.evalPlace, induction.execStmt,
            agreement.target, agreement.constant, agreement.function]
      · intro state expressions
        cases expressions <;>
          simp only [evalExprs] <;>
          simp only [induction.evalExpr, induction.evalExprs]
      · intro state value arms
        cases arms <;>
          simp only [evalMatchArms] <;>
          simp only [induction.evalExpr, induction.evalMatchArms]
      · intro state place
        cases place <;>
          simp only [evalPlace] <;>
          simp only [induction.evalPlace, induction.evalExpr]
      · intro state id values body
        cases values <;>
          simp only [execForValues] <;>
          simp only [induction.execStmt, induction.execForValues]
      · intro state id current stop inclusive body
        simp only [execForRange]
        simp only [induction.execStmt, induction.execForRange, agreement.target]
      · intro state statement
        cases statement <;>
          simp only [execStmt] <;>
          simp only [induction.evalExpr, induction.execStmt,
            induction.execForValues, induction.execForRange]

theorem evalExpr_eq (agreement : first.RuntimeAgrees second)
    (fuel : Nat) (state : State) (expression : Expr) :
    evalExpr fuel first state expression =
      evalExpr fuel second state expression :=
  (atFuel agreement fuel).evalExpr state expression

theorem evalExprs_eq (agreement : first.RuntimeAgrees second)
    (fuel : Nat) (state : State) (expressions : List Expr) :
    evalExprs fuel first state expressions =
      evalExprs fuel second state expressions :=
  (atFuel agreement fuel).evalExprs state expressions

theorem evalMatchArms_eq (agreement : first.RuntimeAgrees second)
    (fuel : Nat) (state : State) (value : Value)
    (arms : List (Pattern × Expr)) :
    evalMatchArms fuel first state value arms =
      evalMatchArms fuel second state value arms :=
  (atFuel agreement fuel).evalMatchArms state value arms

theorem evalPlace_eq (agreement : first.RuntimeAgrees second)
    (fuel : Nat) (state : State) (place : Place) :
    evalPlace fuel first state place = evalPlace fuel second state place :=
  (atFuel agreement fuel).evalPlace state place

theorem execForValues_eq (agreement : first.RuntimeAgrees second)
    (fuel : Nat) (state : State) (id : VarId) (values : List Value)
    (body : Stmt) :
    execForValues fuel first state id values body =
      execForValues fuel second state id values body :=
  (atFuel agreement fuel).execForValues state id values body

theorem execForRange_eq (agreement : first.RuntimeAgrees second)
    (fuel : Nat) (state : State) (id : VarId) (current : Int)
    (stop : Option Int) (inclusive : Bool) (body : Stmt) :
    execForRange fuel first state id current stop inclusive body =
      execForRange fuel second state id current stop inclusive body :=
  (atFuel agreement fuel).execForRange state id current stop inclusive body

theorem execStmt_eq (agreement : first.RuntimeAgrees second)
    (fuel : Nat) (state : State) (statement : Stmt) :
    execStmt fuel first state statement =
      execStmt fuel second state statement :=
  (atFuel agreement fuel).execStmt state statement

theorem evaluates_iff (agreement : first.RuntimeAgrees second) :
    Evaluates first state expression value after ↔
      Evaluates second state expression value after := by
  constructor <;> rintro ⟨fuel, evaluated⟩ <;> refine ⟨fuel, ?_⟩
  · simpa [agreement.evalExpr_eq fuel state expression] using evaluated
  · simpa [(agreement.evalExpr_eq fuel state expression).symm] using evaluated

theorem executes_iff (agreement : first.RuntimeAgrees second) :
    Executes first state statement completion after ↔
      Executes second state statement completion after := by
  constructor <;> rintro ⟨fuel, executed⟩ <;> refine ⟨fuel, ?_⟩
  · simpa [agreement.execStmt_eq fuel state statement] using executed
  · simpa [(agreement.execStmt_eq fuel state statement).symm] using executed

end Core.Program.RuntimeAgrees

/-! ## One-way program extension

`RuntimeAgrees` is useful for exact replacement, but a merged source pack has
additional declarations.  `RuntimeExtends` is the corresponding one-way
relation: every declaration that the smaller program can resolve is preserved
verbatim by the larger program.  Successful executions therefore transport
forward even though failed lookups in the smaller program may become valid in
the larger one. -/

structure Core.Program.RuntimeExtends (smaller larger : Program) : Prop where
  target : smaller.target = larger.target
  constant : ∀ {id declaration},
    smaller.constant? id = some declaration →
      larger.constant? id = some declaration
  function : ∀ {id declaration},
    smaller.function? id = some declaration →
      larger.function? id = some declaration

namespace Core.Program.RuntimeExtends

theorem refl (program : Program) : program.RuntimeExtends program :=
  ⟨rfl, fun found => found, fun found => found⟩

theorem trans {first second third : Program}
    (firstSecond : first.RuntimeExtends second)
    (secondThird : second.RuntimeExtends third) :
    first.RuntimeExtends third :=
  ⟨firstSecond.target.trans secondThird.target,
    fun found => secondThird.constant (firstSecond.constant found),
    fun found => secondThird.function (firstSecond.function found)⟩

private structure AtFuel (fuel : Nat) (smaller larger : Program) : Prop where
  evalExpr : ∀ {state expression value after},
    evalExpr fuel smaller state expression = .done value after →
      evalExpr fuel larger state expression = .done value after
  evalExprs : ∀ {state expressions values after},
    evalExprs fuel smaller state expressions = .done values after →
      evalExprs fuel larger state expressions = .done values after
  evalMatchArms : ∀ {state value arms result after},
    evalMatchArms fuel smaller state value arms = .done result after →
      evalMatchArms fuel larger state value arms = .done result after
  evalPlace : ∀ {state place result after},
    evalPlace fuel smaller state place = .done result after →
      evalPlace fuel larger state place = .done result after
  execForValues : ∀ {state id values body completion after},
    execForValues fuel smaller state id values body = .done completion after →
      execForValues fuel larger state id values body = .done completion after
  execForRange : ∀ {state id current stop inclusive body completion after},
    execForRange fuel smaller state id current stop inclusive body =
        .done completion after →
      execForRange fuel larger state id current stop inclusive body =
        .done completion after
  execStmt : ∀ {state statement completion after},
    execStmt fuel smaller state statement = .done completion after →
      execStmt fuel larger state statement = .done completion after

private theorem restoreOutcomeLocals_done_mono
    {first second : Outcome α}
    (preserved : ∀ {value after}, first = .done value after →
      second = .done value after)
    (restored : restoreOutcomeLocals caller first = .done value after) :
    restoreOutcomeLocals caller second = .done value after := by
  cases first <;> simp only [restoreOutcomeLocals] at restored
  case done result completed =>
    have moved := preserved rfl
    rw [moved]
    exact restored
  all_goals contradiction

private theorem atFuel (extension : smaller.RuntimeExtends larger) :
    ∀ fuel, AtFuel fuel smaller larger := by
  intro fuel
  induction fuel with
  | zero =>
      constructor <;> intros <;>
        simp [evalExpr, evalExprs, evalMatchArms, evalPlace, execForValues,
          execForRange, execStmt] at *
  | succ fuel induction =>
      constructor
      · intro state expression value after evaluated
        cases expression <;> simp only [evalExpr] at evaluated ⊢
        all_goals
          repeat' first
            | rw [induction.evalExpr (by assumption)]
            | rw [induction.evalExprs (by assumption)]
            | rw [induction.evalMatchArms (by assumption)]
            | rw [induction.evalPlace (by assumption)]
            | rw [induction.execStmt (by assumption)]
            | split at evaluated
          all_goals grind only [induction.evalExpr, induction.evalExprs,
            induction.evalMatchArms, induction.evalPlace, induction.execStmt,
            extension.target, extension.constant, extension.function]
      · intro state expressions values after evaluated
        cases expressions <;> simp only [evalExprs] at evaluated ⊢
        all_goals
          repeat' first
            | rw [induction.evalExpr (by assumption)]
            | rw [induction.evalExprs (by assumption)]
            | split at evaluated
          all_goals grind only [induction.evalExpr, induction.evalExprs]
      · intro state value arms result after evaluated
        cases arms <;> simp only [evalMatchArms] at evaluated ⊢
        all_goals
          repeat' first
            | rw [induction.evalExpr (by assumption)]
            | rw [induction.evalMatchArms (by assumption)]
            | split at evaluated
          all_goals grind only [induction.evalExpr, induction.evalMatchArms,
            restoreOutcomeLocals_done_mono]
      · intro state place result after evaluated
        cases place <;> simp only [evalPlace] at evaluated ⊢
        all_goals
          repeat' first
            | rw [induction.evalPlace (by assumption)]
            | rw [induction.evalExpr (by assumption)]
            | split at evaluated
          all_goals grind only [induction.evalPlace, induction.evalExpr]
      · intro state id values body completion after executed
        cases values <;> simp only [execForValues] at executed ⊢
        all_goals
          repeat' first
            | rw [induction.execStmt (by assumption)]
            | rw [induction.execForValues (by assumption)]
            | split at executed
          all_goals grind only [induction.execStmt, induction.execForValues]
      · intro state id current stop inclusive body completion after executed
        simp only [execForRange] at executed ⊢
        repeat' first
          | rw [induction.execStmt (by assumption)]
          | rw [induction.execForRange (by assumption)]
          | split at executed
        all_goals grind only [induction.execStmt, induction.execForRange,
          extension.target]
      · intro state statement completion after executed
        cases statement <;> simp only [execStmt] at executed ⊢
        all_goals
          repeat' first
            | rw [induction.evalExpr (by assumption)]
            | rw [induction.execStmt (by assumption)]
            | rw [induction.execForValues (by assumption)]
            | rw [induction.execForRange (by assumption)]
            | split at executed
          all_goals grind only [induction.evalExpr, induction.execStmt,
            induction.execForValues, induction.execForRange,
            restoreOutcomeLocals_done_mono]

theorem evalExpr_done (extension : smaller.RuntimeExtends larger)
    (evaluated : evalExpr fuel smaller state expression = .done value after) :
    evalExpr fuel larger state expression = .done value after :=
  (atFuel extension fuel).evalExpr evaluated

theorem evalExprs_done (extension : smaller.RuntimeExtends larger)
    (evaluated : evalExprs fuel smaller state expressions = .done values after) :
    evalExprs fuel larger state expressions = .done values after :=
  (atFuel extension fuel).evalExprs evaluated

theorem evalPlace_done (extension : smaller.RuntimeExtends larger)
    (evaluated : evalPlace fuel smaller state place = .done value after) :
    evalPlace fuel larger state place = .done value after :=
  (atFuel extension fuel).evalPlace evaluated

theorem execStmt_done (extension : smaller.RuntimeExtends larger)
    (executed : execStmt fuel smaller state statement =
      .done completion after) :
    execStmt fuel larger state statement = .done completion after :=
  (atFuel extension fuel).execStmt executed

theorem evaluates (extension : smaller.RuntimeExtends larger)
    (evaluated : Evaluates smaller state expression value after) :
    Evaluates larger state expression value after := by
  obtain ⟨fuel, evaluated⟩ := evaluated
  exact ⟨fuel, extension.evalExpr_done evaluated⟩

theorem executes (extension : smaller.RuntimeExtends larger)
    (executed : Executes smaller state statement completion after) :
    Executes larger state statement completion after := by
  obtain ⟨fuel, executed⟩ := executed
  exact ⟨fuel, extension.execStmt_done executed⟩

end Core.Program.RuntimeExtends

end Lanius
