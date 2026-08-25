import Lanius.Dynamics
import Lanius.Properties

namespace Lanius.Soundness

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Typing
open Lanius.Dynamics
open Lanius.Properties

/-- The fuel-independent expression relation preserves the expression's type,
    runtime store, and borrowed-view invariants. -/
theorem ExprEvaluatesTo.preserves_type
    (programTyped : ProgramWellTyped program)
    (constantsClosed : ProgramConstantsClosed program)
    (opaqueWorldsTyped : ∀ world, OpaqueResponsesWellTyped program world)
    (stateTyped : RuntimeStateHasType program context state store)
    (expressionTyped : ExprHasType program context expression type)
    (evaluates : ExprEvaluatesTo program state expression result) :
    RuntimeValueOutcomeHasExtendedType program context state store result type := by
  rcases evaluates with ⟨_terminal, fuel, evaluated⟩
  have preserved := evalExpr_has_runtime_type programTyped constantsClosed
    opaqueWorldsTyped fuel stateTyped expressionTyped
  rwa [evaluated] at preserved

/-- The fuel-independent statement relation preserves the statement's return
    type, control-flow discipline, store, and borrowed-view invariants. -/
theorem StmtExecutesTo.preserves_type
    (programTyped : ProgramWellTyped program)
    (constantsClosed : ProgramConstantsClosed program)
    (opaqueWorldsTyped : ∀ world, OpaqueResponsesWellTyped program world)
    (statementTyped : StmtHasType program returnType context inLoop statement)
    (stateTyped : RuntimeStateHasType program context state store)
    (executes : StmtExecutesTo program state statement result) :
    RuntimeCompletionOutcomeHasType program returnType context inLoop
      state store result := by
  rcases executes with ⟨_terminal, fuel, executed⟩
  have preserved := execStmt_has_runtime_type programTyped constantsClosed
    opaqueWorldsTyped statementTyped fuel stateTyped
  rwa [executed] at preserved

/-- Language-level whole-program soundness. Any terminal observation of a
    well-formed executable retains the declared entrypoint type and all runtime
    state invariants. -/
theorem ExecutionTerminatesWith.preserves_type
    (programTyped : ProgramWellTyped executable.program)
    (constantsClosed : ProgramConstantsClosed executable.program)
    (opaqueWorldsTyped : ∀ world,
      OpaqueResponsesWellTyped executable.program world)
    (wellFormed : Execution.ExecutableWellFormed executable)
    (initialTyped : RuntimeStateHasType executable.program Context.empty
      initial initialStore)
    (terminates : ExecutionTerminatesWith executable initial result) :
    ∃ returnType,
      Execution.EntrypointReturnType returnType ∧
        ExecutionResultHasType executable.program returnType initial initialStore
          result := by
  rcases terminates with ⟨_terminal, fuel, executed⟩
  obtain ⟨returnType, allowed, preserved⟩ :=
    executable_run_has_runtime_type programTyped constantsClosed
      opaqueWorldsTyped wellFormed fuel initial initialStore initialTyped
  exact ⟨returnType, allowed, by simpa [executed] using preserved⟩

end Lanius.Soundness
