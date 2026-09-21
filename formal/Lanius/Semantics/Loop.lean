import Lanius.Semantics.Rules

namespace Lanius.Semantics

open Lanius
open Lanius.Core

/-! Exact one-step rules for the evaluator's loop and local-binding forms.
    These expose the recursive fuel split without committing to a program. -/

theorem execStmt_expression
    (fuel : Nat) (program : Program) (state : State)
    (expression : Expr) (value : Value) (after : State)
    (evaluates : evalExpr fuel program state expression = .done value after) :
    execStmt fuel.succ program state (.expression expression) =
      .done .next after := by
  simp only [execStmt.eq_def, evaluates]

theorem execStmt_sequence_next
    (fuel : Nat) (program : Program) (state : State)
    (first second : Stmt) (completion : Completion)
    (afterFirst afterSecond : State)
    (firstEvaluates : execStmt fuel program state first =
      .done .next afterFirst)
    (secondEvaluates : execStmt fuel program afterFirst second =
      .done completion afterSecond) :
    execStmt fuel.succ program state (.sequence first second) =
      .done completion afterSecond := by
  rw [execStmt.eq_def]
  simp only [firstEvaluates, secondEvaluates]

theorem execStmt_letLocal
    (fuel : Nat) (program : Program) (state : State)
    (id : VarId) (type : Ty) (initializer : Expr) (body : Stmt)
    (value : Value) (afterInit afterBody : State) (completion : Completion)
    (initializerEvaluates :
      evalExpr fuel program state initializer = .done value afterInit)
    (bodyEvaluates :
      execStmt fuel program (afterInit.bindLocal id value) body =
        .done completion afterBody) :
    execStmt fuel.succ program state (.letLocal id type initializer body) =
      .done completion (restoreLocals afterInit afterBody) := by
  rw [execStmt.eq_def]
  simp only [initializerEvaluates, bodyEvaluates, restoreOutcomeLocals]

theorem execStmt_while_false
    (fuel : Nat) (program : Program) (state : State)
    (condition : Expr) (body : Stmt) (after : State)
    (conditionEvaluates :
      evalExpr fuel program state condition = .done (.boolean false) after) :
    execStmt fuel.succ program state (.whileLoop condition body) =
      .done .next after := by
  simp only [execStmt.eq_def, conditionEvaluates]

theorem execStmt_while_true_step
    (fuel : Nat) (program : Program) (state : State)
    (condition : Expr) (body : Stmt) (afterCondition afterBody final : State)
    (completion result : Completion)
    (conditionEvaluates :
      evalExpr fuel program state condition =
        .done (.boolean true) afterCondition)
    (bodyEvaluates :
      execStmt fuel program afterCondition body =
        .done completion afterBody)
    (continues : completion = .next ∨ completion = .continueLoop)
    (recursive :
      execStmt fuel program afterBody (.whileLoop condition body) =
        .done result final) :
    execStmt fuel.succ program state (.whileLoop condition body) =
      .done result final := by
  rcases continues with rfl | rfl
  · rw [execStmt.eq_def]
    simp only [conditionEvaluates, bodyEvaluates, recursive]
  · rw [execStmt.eq_def]
    simp only [conditionEvaluates, bodyEvaluates, recursive]

theorem evalExpr_logicalAnd_false
    (fuel : Nat) (program : Program) (state : State)
    (left right : Expr) (afterLeft : State)
    (leftEvaluates : evalExpr fuel program state left =
      .done (.boolean false) afterLeft) :
    evalExpr fuel.succ program state (.binary .logicalAnd left right) =
      .done (.boolean false) afterLeft := by
  rw [evalExpr.eq_def]
  simp only [leftEvaluates]

theorem evalExpr_logicalAnd_true
    (fuel : Nat) (program : Program) (state : State)
    (left right : Expr) (rightValue : Value) (afterLeft afterRight : State)
    (leftEvaluates : evalExpr fuel program state left =
      .done (.boolean true) afterLeft)
    (rightEvaluates : evalExpr fuel program afterLeft right =
      .done rightValue afterRight) :
    evalExpr fuel.succ program state (.binary .logicalAnd left right) =
      .done rightValue afterRight := by
  rw [evalExpr.eq_def]
  simp only [leftEvaluates, rightEvaluates]

theorem evalExpr_i32_locals_less
    (fuel : Nat) (program : Program) (state : State)
    (leftId rightId : VarId) (left right : Int)
    (leftFound : state.local? leftId = some (.signed .i32 left))
    (rightFound : state.local? rightId = some (.signed .i32 right)) :
    evalExpr fuel.succ.succ program state
      (.binary .less (.local leftId) (.local rightId)) =
      .done (.boolean (decide (left < right))) state := by
  have leftEvaluates := evalExpr_local_of_local? fuel program state leftId
    (.signed .i32 left) leftFound
  have rightEvaluates := evalExpr_local_of_local? fuel program state rightId
    (.signed .i32 right) rightFound
  apply evalExpr_binary_done (fuel := fuel.succ) program state .less
    (.local leftId) (.local rightId) (.signed .i32 left)
    (.signed .i32 right) (.boolean (decide (left < right))) state state
    leftEvaluates rightEvaluates (by simp)
  simp [evalBinaryValue, evalSignedBinary]

theorem wrapSigned_i32_nat_lt
    (target : Target) (n : Nat) (bound : n < 2 ^ 31) :
    wrapSigned target .i32 (n : Int) = (n : Int) := by
  have boundInt : (n : Int) < (2 : Int)^31 := by
    calc
      (n : Int) < ((2 ^ 31 : Nat) : Int) := Int.ofNat_lt.mpr bound
      _ = (2 : Int)^31 := by
        rw [Int.natCast_pow]
        rfl
  have modulo : (n : Int) % signedModulus target .i32 = (n : Int) :=
    Int.emod_eq_of_lt (Int.natCast_nonneg _) (by
      change (n : Int) < (2 : Int)^32
      omega)
  have signNot : ¬ (signedSignBit target .i32 ≤ (n : Int)) := by
    change ¬ ((2 : Int)^31 ≤ (n : Int))
    omega
  simp only [wrapSigned, modulo, if_neg signNot]

theorem evalPlace_local_of_local?
    (fuel : Nat) (program : Program) (state : State)
    (id : VarId) (cell : CellId) (value : Value)
    (cellFound : state.cellId? id = some cell)
    (localFound : state.local? id = some value) :
    evalPlace fuel.succ program state (.local id) =
      .done { root := cell, projections := [], value := some value } state := by
  simp only [evalPlace.eq_def, cellFound]
  unfold State.local? at localFound
  rw [cellFound] at localFound
  cases valueFound : state.cellEntry? cell with
  | none => simp [State.cell?, valueFound] at localFound
  | some entry =>
    cases entry with
    | mk entryId entryValue =>
      cases entryValue with
      | none => simp [State.cell?, valueFound] at localFound
      | some entryValue =>
        simp_all [State.cell?]

theorem evalExpr_assign_add_i32_local
    (fuel : Nat) (program : Program) (state : State)
    (id : VarId) (cell : CellId) (current increment : Int) (after : State)
    (cellFound : state.cellId? id = some cell)
    (localFound : state.local? id = some (.signed .i32 current))
    (assigned : state.assignLocal id
      (.signed .i32 (wrapSigned program.target .i32 (current + increment))) =
      some after) :
    evalExpr fuel.succ.succ program state
      (.assign .add (.local id) (.value (.signed .i32 increment))) =
      .done .unit after := by
  have place := evalPlace_local_of_local? fuel program state id cell
    (.signed .i32 current) cellFound localFound
  have right := evalExpr_value fuel program state
    (.signed .i32 increment)
  let nextValue : Value :=
    .signed .i32 (wrapSigned program.target .i32 (current + increment))
  have operation :
      evalAssignValue program.target .add
          (some (.signed .i32 current)) (.signed .i32 increment) =
        .ok nextValue := by
    simp [nextValue, evalAssignValue, assignOpBinary?, evalSignedBinary,
      evalBinaryValue]
  have assignedCell : state.assignCell cell nextValue = some after := by
    simpa [State.assignLocal, cellFound, nextValue] using assigned
  have write :
      writeResolvedPlace state
          { root := cell, projections := [], value := some (.signed .i32 current) }
          nextValue = .ok after := by
    unfold writeResolvedPlace
    rw [assignedCell]
  rw [evalExpr.eq_def]
  simp only [place, right]
  rw [operation]
  simp only [write]

end Lanius.Semantics
