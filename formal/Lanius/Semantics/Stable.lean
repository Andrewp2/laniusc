import Lean.Elab.Tactic.Omega
import Lanius.Semantics.Frame
import Lanius.Semantics.Loop
import Lanius.Semantics.Pure
import Lanius.Semantics.Rules

namespace Lanius.Semantics

open Lanius Lanius.Core

/-- A contract valid at every fuel value above an evaluator threshold. -/
def StableExpr (threshold : Nat) (program : Program) (state : State)
    (expression : Expr) (value : Value) (after : State) : Prop :=
  ∀ fuel, threshold ≤ fuel →
    evalExpr fuel program state expression = .done value after

/-- A statement analogue of `StableExpr`, for fixed completion and state. -/
def StableStmt (threshold : Nat) (program : Program) (state : State)
    (statement : Stmt) (completion : Completion) (after : State) : Prop :=
  ∀ fuel, threshold ≤ fuel →
    execStmt fuel program state statement = .done completion after

theorem StableStmt.skip (program : Program) (state : State) :
    StableStmt 1 program state .skip .next state := by
  intro fuel enough
  cases fuel <;> simp_all [execStmt.eq_def]

/-- A pure execution may append fresh cells while preserving the caller frame. -/
structure PureFrame (before after : State) : Prop where
  beforeFormed : before.CellsWellFormed
  cells : FreshCellFrame before after
  locals : after.locals = before.locals
  heap : after.heap = before.heap
  world : after.world = before.world
  views : after.i32ArrayViews = before.i32ArrayViews

theorem PureFrame.refl (formed : state.CellsWellFormed) : PureFrame state state :=
  ⟨formed, ⟨[], by simp, Nat.le_refl _, by simp⟩, rfl, rfl, rfl, rfl⟩

theorem PureFrame.afterFormed
    (frame : PureFrame before after) : after.CellsWellFormed :=
  FreshCellFrame.after_cellsWellFormed frame.beforeFormed frame.cells

theorem PureFrame.trans
    (left : PureFrame before middle)
    (right : PureFrame middle after) : PureFrame before after :=
  ⟨left.beforeFormed, left.cells.trans right.cells, right.locals.trans left.locals,
    right.heap.trans left.heap, right.world.trans left.world, right.views.trans left.views⟩

/-- A contract valid at every fuel value above its evaluator threshold. -/
structure ThresholdPure (fuelThreshold : Nat)
    (program : Program) (before : State) (expression : Expr)
    (value : Value) (after : State) : Prop where
  run : ∀ fuel, fuelThreshold ≤ fuel →
    evalExpr fuel program before expression = .done value after
  frame : PureFrame before after

theorem StableStmt.letLocal
    {initFuel bodyFuel : Nat} (program : Program) (state : State)
    (id : VarId) (type : Ty) (initializer : Expr) (body : Stmt)
    (value : Value) (afterInit afterBody : State) (completion : Completion)
    (initializerContract : StableExpr initFuel program state initializer value afterInit)
    (bodyContract : StableStmt bodyFuel program (afterInit.bindLocal id value)
      body completion afterBody) :
    StableStmt (max initFuel bodyFuel + 1) program state
      (.letLocal id type initializer body) completion
      (restoreLocals afterInit afterBody) := by
  intro fuel enough
  have initializerRun := initializerContract (fuel - 1) (by omega)
  have bodyRun := bodyContract (fuel - 1) (by omega)
  simpa [show fuel - 1 + 1 = fuel by omega] using
    (execStmt_letLocal (fuel := fuel - 1) program state id type initializer body
      value afterInit afterBody completion initializerRun bodyRun)

theorem ThresholdPure.erase
    {fuelThreshold : Nat} {program : Program} {before : State} {expression : Expr}
    {value : Value} {after : State}
    (contract : ThresholdPure fuelThreshold program before expression value after) :
    PurelyEvaluates program before expression value := by
  exact ⟨after, ⟨⟨fuelThreshold, contract.run _ (Nat.le_refl _)⟩,
    contract.frame.beforeFormed, contract.frame.afterFormed, contract.frame.locals,
    contract.frame.heap, contract.frame.world, contract.frame.views⟩⟩

theorem ThresholdPure.weaken
    {oldThreshold newThreshold : Nat} {program : Program} {before : State}
    {expression : Expr} {value : Value} {after : State}
    (contract : ThresholdPure oldThreshold program before expression value after)
    (threshold : oldThreshold ≤ newThreshold) :
    ThresholdPure newThreshold program before expression value after := by
  exact ⟨fun fuel enough => contract.run fuel (Nat.le_trans threshold enough), contract.frame⟩

theorem logicalOrTrue
    {leftFuel : Nat} {program : Program} {before after : State} {left right : Expr}
    (leftContract : ThresholdPure leftFuel program before left (.boolean true) after) :
    ThresholdPure (leftFuel + 1) program before (.binary .logicalOr left right)
      (.boolean true) after := by
  refine ⟨?_, leftContract.frame⟩
  intro fuel enough
  have leftEval := leftContract.run (fuel - 1) (by omega)
  simpa [show fuel - 1 + 1 = fuel by omega] using
    (evalExpr_logicalOr_true (fuel - 1) program before left right after leftEval)

theorem logicalOrFalse
    {leftFuel rightFuel : Nat} {program : Program} {before : State} {left right : Expr}
    {middle after : State} {rightValue : Bool}
    (leftContract : ThresholdPure leftFuel program before left (.boolean false) middle)
    (rightContract : ThresholdPure rightFuel program middle right (.boolean rightValue) after) :
    ThresholdPure (max leftFuel rightFuel + 1) program before (.binary .logicalOr left right)
      (.boolean rightValue) after := by
  refine ⟨?_, ?_⟩
  · intro fuel enough
    have leftEval := leftContract.run (fuel - 1) (by omega)
    have rightEval := rightContract.run (fuel - 1) (by omega)
    simpa [show fuel - 1 + 1 = fuel by omega] using
      (evalExpr_logicalOr_false (fuel - 1) program before left right
      (.boolean rightValue) middle after leftEval rightEval)
  · exact leftContract.frame.trans rightContract.frame

theorem logicalOr3
    {program : Program} {state : State} {first second third : Expr}
    {a b c : Bool}
    (firstRun : ThresholdPure 3 program state first (.boolean a) state)
    (secondRun : ThresholdPure 3 program state second (.boolean b) state)
    (thirdRun : ThresholdPure 3 program state third (.boolean c) state) :
    ∃ fuel, ThresholdPure fuel program state
      (.binary .logicalOr (.binary .logicalOr first second) third)
      (.boolean (a || b || c)) state := by
  cases a with
  | false =>
      cases b with
      | false =>
          cases c with
          | false => exact ⟨_, logicalOrFalse (logicalOrFalse firstRun secondRun) thirdRun⟩
          | true => exact ⟨_, logicalOrFalse (logicalOrFalse firstRun secondRun) thirdRun⟩
      | true =>
          cases c <;> exact ⟨_, logicalOrTrue (logicalOrFalse firstRun secondRun)⟩
  | true =>
      cases b <;> cases c <;>
        exact ⟨_, logicalOrTrue (logicalOrTrue firstRun)⟩

end Lanius.Semantics
