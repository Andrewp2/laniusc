import Lean.Elab.Tactic.Omega
import Lanius.Compiler.Lexer.Composition
import Lanius.Semantics.Branch

namespace Lanius.Compiler.Lexer

open Lanius Lanius.Core Lanius.Semantics

/-! Proof family for read-only one-argument decision trees with Core constants. -/

inductive I32DecisionTree where
  | leaf (constant : ConstantId) (tag : Int)
  | branch (predicate : UnaryI32Predicate) (thenBranch elseBranch : I32DecisionTree)
deriving Repr

def I32DecisionTree.accepts : I32DecisionTree → Int → Int
  | .leaf _ tag, _ => tag
  | .branch p t e, input => if p.accepts input then t.accepts input else e.accepts input

def I32DecisionTree.compileStmt (parameter : VarId) : I32DecisionTree → Stmt
  | .leaf constant _ => .sequence (.returnValue (some (.constant constant))) .skip
  | .branch p t e => .sequence (.ifThenElse (p.compile parameter)
      (t.compileStmt parameter) (e.compileStmt parameter)) .skip

def i32DecisionTreeFunction
    (functionId parameter : FunctionId) (tree : I32DecisionTree) : Function :=
  { id := functionId
    parameters := [(parameter, .scalar (.signed .i32))]
    returnType := .scalar (.signed .i32)
    body := some (tree.compileStmt parameter) }

def I32DecisionTree.ConstantsResolved (program : Program) : I32DecisionTree → Prop
  | .leaf constant tag =>
      ∃ declaration, program.constant? constant = some declaration ∧
        declaration.value = .signed .i32 tag
  | .branch _ t e => t.ConstantsResolved program ∧ e.ConstantsResolved program

def I32DecisionTree.fuel : I32DecisionTree → Nat
  | .leaf _ _ => 3
  | .branch p t e => max p.exprFuel (max t.fuel e.fuel) + 2

private theorem StableStmt.weakenThreshold
    {oldFuel newFuel : Nat} {program : Program} {state : State} {statement : Stmt}
    {completion : Completion} {after : State}
    (run : StableStmt oldFuel program state statement completion after) (fuelOrder : oldFuel ≤ newFuel) :
    StableStmt newFuel program state statement completion after :=
  fun fuel enough => run fuel (Nat.le_trans fuelOrder enough)

private theorem maxBranchFuel_le (conditionFuel branchFuel otherFuel : Nat) :
    max conditionFuel branchFuel + 1 ≤ max conditionFuel (max branchFuel otherFuel) + 1 :=
  Nat.add_le_add_right (Nat.max_le.mpr ⟨Nat.le_max_left _ _, Nat.le_trans (Nat.le_max_left _ _) (Nat.le_max_right _ _)⟩) 1

private theorem evalExpr_constant_of_found (fuel : Nat) (program : Program) (state : State)
    (constant : ConstantId) (declaration : Constant)
    (found : program.constant? constant = some declaration) :
    evalExpr fuel.succ program state (.constant constant) =
      .done declaration.value state := by
  rw [evalExpr.eq_def]
  simp [found]

private theorem thresholdI32DecisionTreeStmt (tree : I32DecisionTree) (program : Program)
    (state : State) (parameter : VarId) (input : Int)
    (resolved : tree.ConstantsResolved program) (formed : state.CellsWellFormed)
    (localFound : state.local? parameter = some (.signed .i32 input)) :
    StableStmt tree.fuel program state (tree.compileStmt parameter)
      (.returned (some (.signed .i32 (tree.accepts input)))) state := by
  induction tree generalizing state input with
  | leaf constant tag =>
      rcases resolved with ⟨declaration, found, value⟩
      have constantRun : StableExpr 1 program state (.constant constant)
          (.signed .i32 tag) state := by
        intro fuel enough
        simpa [value, show fuel - 1 + 1 = fuel by omega] using
          (evalExpr_constant_of_found (fuel := fuel - 1) program state
            constant declaration found)
      simpa [I32DecisionTree.compileStmt, I32DecisionTree.accepts,
        I32DecisionTree.fuel] using
        (StableStmt.returnValueSequence program state (.constant constant)
          (.signed .i32 tag) constantRun)
  | branch predicate thenBranch elseBranch ihThen ihElse =>
      rcases resolved with ⟨resolvedThen, resolvedElse⟩
      have conditionRun : StableExpr predicate.exprFuel program state
          (predicate.compile parameter) (.boolean (predicate.accepts input)) state := by
        intro fuel enough
        exact evalExpr_unaryI32Predicate predicate fuel enough program state parameter input localFound
      cases accepted : predicate.accepts input with
      | true =>
          have branchRun := StableStmt.ifThenElse_true (elseBranch := elseBranch.compileStmt parameter)
            (by simpa [StableExpr, accepted] using conditionRun)
            (ihThen (state := state) (input := input) resolvedThen formed localFound)
          have branchRun' := StableStmt.weakenThreshold branchRun (maxBranchFuel_le predicate.exprFuel thenBranch.fuel elseBranch.fuel)
          have bodyRun := StableStmt.sequence_completed (second := .skip) branchRun' (by simp)
          simpa [I32DecisionTree.compileStmt, I32DecisionTree.accepts, I32DecisionTree.fuel, accepted] using bodyRun
      | false =>
          have branchRun := StableStmt.ifThenElse_false (thenBranch := thenBranch.compileStmt parameter)
            (by simpa [StableExpr, accepted] using conditionRun)
            (ihElse (state := state) (input := input) resolvedElse formed localFound)
          have branchRun' := StableStmt.weakenThreshold branchRun (maxBranchFuel_le predicate.exprFuel elseBranch.fuel thenBranch.fuel)
          have bodyRun := StableStmt.sequence_completed (second := .skip) branchRun' (by simp)
          simpa [I32DecisionTree.compileStmt, I32DecisionTree.accepts, I32DecisionTree.fuel, accepted, Nat.max_comm] using bodyRun

theorem thresholdI32DecisionTreeCall (tree : I32DecisionTree) (program : Program) (caller : State)
    (functionId parameter : FunctionId) (input : Int)
    (found : program.function? functionId =
      some (i32DecisionTreeFunction functionId parameter tree))
    (resolved : tree.ConstantsResolved program) (formed : caller.CellsWellFormed) :
    ThresholdPure (tree.fuel + 5) program caller
      (.call functionId [.value (.signed .i32 input)])
      (.signed .i32 (tree.accepts input))
      (restoreLocals caller
        (({ caller with locals := [] }).bindLocal parameter
          (.signed .i32 input))) := by
  let value : Value := .signed .i32 input
  let callee : State := ({ caller with locals := [] }).bindLocal parameter value
  have clearedFormed : ({ caller with locals := [] }).CellsWellFormed :=
    fun _ member => formed _ member
  have calleeFormed : callee.CellsWellFormed :=
    clearedFormed.bindLocal parameter value
  have localFound : callee.local? parameter = some value :=
    clearedFormed.bindLocal_local parameter value
  have body := thresholdI32DecisionTreeStmt tree program callee parameter input
    resolved calleeFormed localFound
  have calleeFrame : CallerFrame caller callee := by
    exact ⟨formed, by
      simp [callee, FreshCellFrame, State.bindLocal, State.bindCell], rfl, rfl, rfl⟩
  have contract := thresholdInternalCall program caller
    (i32DecisionTreeFunction functionId parameter tree) [.value value]
    (tree.compileStmt parameter) [value] [(parameter, value)] caller callee callee
    (.signed .i32 (tree.accepts input)) found rfl
    (by simpa using ThresholdPureList.singleton (ThresholdPure.value formed))
    (by simp [i32DecisionTreeFunction, bindParameters])
    (by simp [callee, State.bindLocals]) body calleeFrame (PureFrame.refl calleeFormed)
  exact contract.weaken (by omega)

theorem purelyEvaluates_i32DecisionTreeCall (tree : I32DecisionTree) (program : Program)
    (caller : State) (functionId parameter : FunctionId) (input : Int)
    (found : program.function? functionId =
      some (i32DecisionTreeFunction functionId parameter tree))
    (resolved : tree.ConstantsResolved program) (formed : caller.CellsWellFormed) :
    PurelyEvaluates program caller
      (.call functionId [.value (.signed .i32 input)])
      (.signed .i32 (tree.accepts input)) := by
  exact (thresholdI32DecisionTreeCall tree program caller functionId parameter input
    found resolved formed).erase

end Lanius.Compiler.Lexer
