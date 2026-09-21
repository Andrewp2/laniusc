import Lanius.Semantics.Assignment
import Lanius.Semantics.Bindings
import Lanius.Semantics.Aggregate
import Lanius.Semantics.Branch
import Lanius.Semantics.Call

namespace Lanius.Extraction.CertificateEmitterCall

open Lanius Lanius.Core Lanius.Extraction Lanius.Semantics

/-! The call-frame facts shared by extracted emitters.  In particular, these
lemmas keep a mutable caller cell in the caller state while allowing argument
and callee frames to allocate fresh parameter cells. -/

theorem stableMutableInternalCall
    (program : Program) (caller : State) (function : Function)
    (arguments : List Expr) (body : Stmt) (values : List Value)
    (bindings : List (VarId × Value)) (afterArguments callee completed : State)
    (result : Value)
    (functionFound : program.function? function.id = some function)
    (bodyFound : function.body = some body)
    {argumentsFuel bodyFuel : Nat}
    (argumentsContract : ThresholdPureList argumentsFuel program caller
      arguments values afterArguments)
    (parametersBind : bindParameters function.parameters values = some bindings)
    (calleeShape : callee = ({ afterArguments with locals := [] }).bindLocals bindings)
    (bodyContract : StableStmt bodyFuel program callee body
      (.returned (some result)) completed) :
    StableExpr (max argumentsFuel bodyFuel + 1) program caller
      (.call function.id arguments) result (restoreLocals caller completed) := by
  intro fuel enough
  have argumentsEvaluate := argumentsContract.run (fuel - 1) (by omega)
  have bodyEvaluate := bodyContract (fuel - 1) (by omega)
  have call := evalExpr_call_internal (fuel := fuel - 1) program caller
    function.id arguments function body values bindings afterArguments completed
    result functionFound bodyFound argumentsEvaluate parametersBind
    (by simpa [calleeShape] using bodyEvaluate)
  simpa [show fuel - 1 + 1 = fuel by omega, restoreLocals,
    argumentsContract.frame.locals] using call

theorem stableCall_memory_effect
    {threshold : Nat} (program : Program) (caller : State)
    (expression : Expr) (result : Value) (after : State) (root : CellId)
    (entry : Cell) (contract : StableExpr threshold program caller
      expression result after)
    (afterRoot : after.cellEntry? root = some entry) :
    ∃ fuel, evalExpr fuel program caller expression = .done result after ∧
      after.cellEntry? root = some entry :=
  ⟨threshold, contract threshold (Nat.le_refl _), afterRoot⟩

theorem cellsWellFormed_replaceCell
    (state : State) (root : CellId) (value : Value)
    (formed : state.CellsWellFormed) :
    ({ state with cells := replaceCell state.cells root value }).CellsWellFormed := by
  have preserve : ∀ (cells : List Cell),
      (∀ item ∈ cells, item.id < state.nextCell) →
      ∀ item ∈ replaceCell cells root value, item.id < state.nextCell := by
    intro cells
    induction cells with
    | nil => simp [replaceCell]
    | cons head tail induction =>
        intro bounded item member
        by_cases same : head.id = root
        · simp [replaceCell, same] at member
          rcases member with headMember | tailMember
          · subst item
            simpa [same] using bounded head (by simp)
          · exact induction (fun next inside => bounded next (by simp [inside])) item tailMember
        · simp [replaceCell, same] at member
          rcases member with headMember | tailMember
          · exact bounded item (by simp [headMember])
          · exact induction (fun next inside => bounded next (by simp [inside])) item tailMember
  intro item member
  exact preserve state.cells (fun next inside => formed next inside) item member

theorem stableLetLocalReturnCall
    (program : Program) (state : State) (id : VarId) (type : Ty)
    (initializer bodyCall : Expr) (initializerValue result : Value)
    (afterInitializer afterCall : State)
    {initializerFuel callFuel : Nat}
    (initializerContract : StableExpr initializerFuel program state
      initializer initializerValue afterInitializer)
    (callContract : StableExpr callFuel program
      (afterInitializer.bindLocal id initializerValue)
      bodyCall result afterCall) :
    StableStmt (max initializerFuel (callFuel + 2) + 1) program state
      (.letLocal id type initializer
        (.sequence (.returnValue (some bodyCall)) .skip))
      (.returned (some result))
      (restoreLocals afterInitializer afterCall) := by
  exact StableStmt.letLocal program state id type initializer
    (.sequence (.returnValue (some bodyCall)) .skip) initializerValue
    afterInitializer afterCall (.returned (some result)) initializerContract
    (StableStmt.returnValueSequence program
      (afterInitializer.bindLocal id initializerValue) bodyCall result
      callContract)

end Lanius.Extraction.CertificateEmitterCall
