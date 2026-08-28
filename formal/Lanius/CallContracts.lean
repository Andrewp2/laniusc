import Lanius.Dynamics
import Lanius.Separation

namespace Lanius.CallContracts

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Fuel
open Lanius.Properties
open Lanius.Separation

/-- Fuel-independent evaluation of an argument list. -/
def ArgumentsEvaluateTo
    (program : Program) (state : State) (arguments : List Expr)
    (values : List Value) (finalState : State) : Prop :=
  ∃ fuel, evalExprs fuel program state arguments = .done values finalState

theorem ArgumentsEvaluateTo.nil (program : Program) (state : State) :
    ArgumentsEvaluateTo program state [] [] state := by
  exact ⟨1, rfl⟩

/-- Compose one argument evaluation with the remaining argument list. This
    preserves the language's left-to-right state threading. -/
theorem ArgumentsEvaluateTo.cons
    (head : Evaluates program state expression value afterHead)
    (tail : ArgumentsEvaluateTo program afterHead expressions values finalState) :
    ArgumentsEvaluateTo program state (expression :: expressions)
      (value :: values) finalState := by
  obtain ⟨headFuel, headResult⟩ := head
  obtain ⟨tailFuel, tailResult⟩ := tail
  let fuel := max headFuel tailFuel
  have headAtFuel := evalExpr_done_at_larger_fuel
    (Nat.le_max_left headFuel tailFuel) headResult
  have tailAtFuel := evalExprs_done_at_larger_fuel
    (Nat.le_max_right headFuel tailFuel) tailResult
  refine ⟨fuel + 1, ?_⟩
  rw [Lanius.Semantics.evalExprs.eq_def]
  dsimp [fuel]
  rw [headAtFuel]
  simp only
  rw [tailAtFuel]

theorem ArgumentsEvaluateTo.singleton
    (argument : Evaluates program state expression value finalState) :
    ArgumentsEvaluateTo program state [expression] [value] finalState := by
  exact ArgumentsEvaluateTo.cons argument
    (ArgumentsEvaluateTo.nil program finalState)

/-- Separation-logic contract for left-to-right argument evaluation. It is the
    list analogue of `EvalTriple`; the final assertion and write footprint are
    available to the callee contract. -/
def ArgumentsTriple
    (program : Program) (pre : Assertion) (arguments : List Expr)
    (values : List Value) (post : Assertion) (writes : CellSet) : Prop :=
  ∀ before, StateWellFormed before → pre.holds before →
    ∃ after,
      ArgumentsEvaluateTo program before arguments values after ∧
      StateWellFormed after ∧ post.holds after ∧
      ModifiesOnly writes before after

theorem ArgumentsTriple.nil (pre : Assertion) :
    ArgumentsTriple program pre [] [] pre CellSet.empty := by
  intro before beforeWellFormed held
  exact ⟨before, ArgumentsEvaluateTo.nil program before,
    beforeWellFormed, held, ModifiesOnly.refl before⟩

theorem ArgumentsTriple.cons
    (head : EvalTriple program pre expression value middle headWrites)
    (tail : ArgumentsTriple program middle expressions values post tailWrites) :
    ArgumentsTriple program pre (expression :: expressions)
      (value :: values) post (CellSet.union headWrites tailWrites) := by
  intro before beforeWellFormed held
  obtain ⟨afterHead, headExecution, afterHeadWellFormed, middleHeld,
      headEffect⟩ := head before beforeWellFormed held
  obtain ⟨after, tailExecution, afterWellFormed, postHeld, tailEffect⟩ :=
    tail afterHead afterHeadWellFormed middleHeld
  exact ⟨after, ArgumentsEvaluateTo.cons headExecution tailExecution,
    afterWellFormed, postHeld, headEffect.trans tailEffect⟩

theorem ArgumentsTriple.frame
    (triple : ArgumentsTriple program pre arguments values post writes)
    (frame : Assertion)
    (postDisjoint : CellSet.Disjoint post.footprint frame.footprint)
    (writeDisjoint : CellSet.Disjoint frame.footprint writes) :
    ArgumentsTriple program (Assertion.sep pre frame) arguments values
      (Assertion.sep post frame) writes := by
  intro before beforeWellFormed held
  obtain ⟨after, execution, afterWellFormed, postHeld, effect⟩ :=
    triple before beforeWellFormed held.2.1
  have frameHeld := effect.preserve beforeWellFormed frame held.2.2
    writeDisjoint
  exact ⟨after, execution, afterWellFormed,
    ⟨postDisjoint, postHeld, frameHeld⟩, effect⟩

/-- Contract for an open function body. The precondition is observed after
    argument evaluation but before entering the callee. The postcondition is
    observed after the caller's local environment is restored. -/
def ReturnedCallBodyTriple
    (program : Program) (pre : Assertion) (bindings : List (VarId × Value))
    (body : Stmt) (result : Value) (post : Assertion) (writes : CellSet) : Prop :=
  ∀ caller, StateWellFormed caller → pre.holds caller →
    ∃ completed,
      Executes program (enterCall caller bindings) body
        (.returned (some result)) completed ∧
      StateWellFormed completed ∧
      post.holds (restoreLocals caller completed) ∧
      StoreEffect writes (enterCall caller bindings) completed

def UnitCallBodyTriple
    (program : Program) (pre : Assertion) (bindings : List (VarId × Value))
    (body : Stmt) (post : Assertion) (writes : CellSet) : Prop :=
  ∀ caller, StateWellFormed caller → pre.holds caller →
    ∃ completion completed,
      Executes program (enterCall caller bindings) body completion completed ∧
      (completion = .next ∨ completion = .returned none) ∧
      StateWellFormed completed ∧
      post.holds (restoreLocals caller completed) ∧
      StoreEffect writes (enterCall caller bindings) completed

/-- Generic source-function call composition. This is the semantic boundary
    implementation proofs need: evaluate arguments, bind the checked ABI,
    execute the selected body in a fresh local frame, and restore the caller's
    locals. No particular compiler program or function arity is baked in. -/
theorem evaluatesCallReturned
    (argumentsResult :
      ArgumentsEvaluateTo program state arguments values afterArguments)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters values = some bindings)
    (functionBody : function.body = some body)
    (bodyResult : Executes program (enterCall afterArguments bindings) body
      (.returned (some result)) completed) :
    Evaluates program state (.call function.id arguments) result
      (restoreLocals afterArguments completed) := by
  obtain ⟨argumentsFuel, argumentsResult⟩ := argumentsResult
  obtain ⟨bodyFuel, bodyResult⟩ := bodyResult
  let fuel := max argumentsFuel bodyFuel
  have argumentsAtFuel := evalExprs_done_at_larger_fuel
    (Nat.le_max_left argumentsFuel bodyFuel) argumentsResult
  have bodyAtFuel := execStmt_done_at_larger_fuel
    (Nat.le_max_right argumentsFuel bodyFuel) bodyResult
  refine ⟨fuel + 1, ?_⟩
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [argumentsAtFuel]
  simp only
  rw [functionFound]
  simp only
  rw [parametersBound, functionBody]
  simp only
  have bodyAtCallState :
      execStmt fuel program
          (({ afterArguments with locals := [] }).bindLocals bindings) body =
        .done (.returned (some result)) completed := by
    simpa [enterCall] using bodyAtFuel
  rw [bodyAtCallState]

/-- Effect-aware call rule. Argument effects and callee-body effects compose;
    parameter cells remain fresh implementation detail, and restoring locals
    closes the call into an `EvalTriple` suitable for the frame rule. -/
theorem ArgumentsTriple.callReturned
    (argumentsTriple :
      ArgumentsTriple program pre arguments values argumentsPost
        argumentWrites)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters values = some bindings)
    (functionBody : function.body = some body)
    (bodyTriple : ReturnedCallBodyTriple program argumentsPost bindings body
      result post bodyWrites) :
    EvalTriple program pre (.call function.id arguments) result post
      (CellSet.union argumentWrites bodyWrites) := by
  intro before beforeWellFormed held
  obtain ⟨afterArguments, argumentsExecution, argumentsWellFormed,
      argumentsPostHeld, argumentsEffect⟩ :=
    argumentsTriple before beforeWellFormed held
  obtain ⟨completed, bodyExecution, completedWellFormed, postHeld,
      bodyEffect⟩ :=
    bodyTriple afterArguments argumentsWellFormed argumentsPostHeld
  let after := restoreLocals afterArguments completed
  have entered : StoreEffect bodyWrites afterArguments
      (enterCall afterArguments bindings) :=
    (enterCall_effect afterArguments bindings).weaken CellSet.empty_subset
  have callStoreEffect : StoreEffect bodyWrites afterArguments completed :=
    entered.trans_same bodyEffect
  have afterWellFormed : StateWellFormed after :=
    callStoreEffect.restoreLocals_wellFormed argumentsWellFormed
      completedWellFormed
  have callEffect : ModifiesOnly bodyWrites afterArguments after :=
    callStoreEffect.restoreLocals
  have execution := evaluatesCallReturned argumentsExecution functionFound
    parametersBound functionBody bodyExecution
  exact ⟨after, by simpa [after] using execution, afterWellFormed,
    by simpa [after] using postHeld,
    argumentsEffect.trans callEffect⟩

/-- Unit-returning source calls accept either an explicit `return;` or normal
    fallthrough, exactly as the dynamic semantics does. -/
theorem evaluatesCallUnit
    (argumentsResult :
      ArgumentsEvaluateTo program state arguments values afterArguments)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters values = some bindings)
    (functionBody : function.body = some body)
    (unitReturn : function.returnType = .unit)
    (bodyResult : Executes program (enterCall afterArguments bindings) body
      completion completed)
    (returnsUnit : completion = .next ∨ completion = .returned none) :
    Evaluates program state (.call function.id arguments) .unit
      (restoreLocals afterArguments completed) := by
  obtain ⟨argumentsFuel, argumentsResult⟩ := argumentsResult
  obtain ⟨bodyFuel, bodyResult⟩ := bodyResult
  let fuel := max argumentsFuel bodyFuel
  have argumentsAtFuel := evalExprs_done_at_larger_fuel
    (Nat.le_max_left argumentsFuel bodyFuel) argumentsResult
  have bodyAtFuel := execStmt_done_at_larger_fuel
    (Nat.le_max_right argumentsFuel bodyFuel) bodyResult
  refine ⟨fuel + 1, ?_⟩
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [argumentsAtFuel]
  simp only
  rw [functionFound]
  simp only
  rw [parametersBound, functionBody]
  simp only
  have bodyAtCallState :
      execStmt fuel program
          (({ afterArguments with locals := [] }).bindLocals bindings) body =
        .done completion completed := by
    simpa [enterCall] using bodyAtFuel
  rw [bodyAtCallState]
  rcases returnsUnit with rfl | rfl <;> simp [unitReturn]

theorem ArgumentsTriple.callUnit
    (argumentsTriple :
      ArgumentsTriple program pre arguments values argumentsPost
        argumentWrites)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters values = some bindings)
    (functionBody : function.body = some body)
    (unitReturn : function.returnType = .unit)
    (bodyTriple : UnitCallBodyTriple program argumentsPost bindings body post
      bodyWrites) :
    EvalTriple program pre (.call function.id arguments) .unit post
      (CellSet.union argumentWrites bodyWrites) := by
  intro before beforeWellFormed held
  obtain ⟨afterArguments, argumentsExecution, argumentsWellFormed,
      argumentsPostHeld, argumentsEffect⟩ :=
    argumentsTriple before beforeWellFormed held
  obtain ⟨completion, completed, bodyExecution, returnsUnit,
      completedWellFormed, postHeld, bodyEffect⟩ :=
    bodyTriple afterArguments argumentsWellFormed argumentsPostHeld
  let after := restoreLocals afterArguments completed
  have entered : StoreEffect bodyWrites afterArguments
      (enterCall afterArguments bindings) :=
    (enterCall_effect afterArguments bindings).weaken CellSet.empty_subset
  have callStoreEffect : StoreEffect bodyWrites afterArguments completed :=
    entered.trans_same bodyEffect
  have execution := evaluatesCallUnit argumentsExecution functionFound
    parametersBound functionBody unitReturn bodyExecution returnsUnit
  exact ⟨after, by simpa [after] using execution,
    callStoreEffect.restoreLocals_wellFormed argumentsWellFormed
      completedWellFormed,
    by simpa [after] using postHeld,
    argumentsEffect.trans callStoreEffect.restoreLocals⟩

end Lanius.CallContracts
