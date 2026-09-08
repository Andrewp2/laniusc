import Lanius.Extraction.RawLexer.LexInto.Caller
import Lanius.Semantics.Relocation.Link
import Lanius.Semantics.Relocation.Ownership
import Lanius.Separation.Relocation

namespace Lanius.Extraction.RawLexer.LexInto.Linked

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.CallContracts Lanius.FunctionalView.Core
open Lanius.FunctionalView.FreshSimulation
open Lanius.Extraction.RawLexer.LexInto.Functions

private theorem callee_relocated (symbols : Core.Relocation.Symbols) :
    Semantics.Relocation.state symbols
      (enterCall caller (parameterBindings (Caller.environment sourceCell recordsCell source records capacity))) =
    enterCall (Semantics.Relocation.state symbols caller)
      (parameterBindings (Caller.environment sourceCell recordsCell source records capacity)) := by
  simp only [enterCall, Semantics.Relocation.bindLocals]
  rfl

/-- Execute the linked lexer from ordinary caller arguments and owned buffers.
The inverse type map handles unrelated tagged caller values internally; no
callee representation, model-coordinate state, or argument relocation is
required. Only the raw-record cell can change among existing caller cells. -/
theorem call_evaluates_at
    (invariant : ∀ rename, Semantics.CellRenaming.Execution.ProgramInvariant rename verifiedFrontendCore)
    (link : Semantics.Relocation.Link allowed symbols verifiedFrontendCore linked)
    (injective : Function.Injective symbols.typeId)
    (inverseType : Lanius.TypeId → Lanius.TypeId)
    (inverse : Function.RightInverse inverseType symbols.typeId)
    (retained : allowed lexIntoFunction.id = true)
    (request : Model.Request) (records : List Int)
    (recordsCapacity : 3 * request.capacity ≤ records.length)
    (sourceCell recordsCell : CellId) (distinct : sourceCell ≠ recordsCell)
    {before afterArguments : State} {arguments : List Expr}
    (wellFormed : StateWellFormed afterArguments)
    (owned : (ReadOnly.World.owns (ReadOnly.World.pair sourceCell
      (ScanOne.Model.sourceIntegers request.source) recordsCell records)).holds afterArguments)
    (argumentsResult : ArgumentsEvaluateTo linked before arguments
      [.slice Structure.i32Type sourceCell [] 0 request.source.length, .signed .i32 request.source.length,
        .slice Structure.i32Type recordsCell [] 0 records.length, .signed .i32 request.capacity] afterArguments) :
    ∃ after,
      Evaluates linked before (.call (symbols.functionId lexIntoFunction.id) arguments)
        (Core.Relocation.value symbols (Model.resultValue request.outcome)) after ∧
      (ReadOnly.World.owns (ReadOnly.World.pair sourceCell
        (ScanOne.Model.sourceIntegers request.source) recordsCell
        (CanonicalTokens.CanonicalizeModel.encodeTokens (Model.emittedTokens request.outcome) ++
          records.drop (3 * (Model.emittedTokens request.outcome).length)))).holds after ∧
      CellEffect (CellSet.singleton recordsCell) afterArguments after := by
  let unrelocate : Core.Relocation.Symbols := ⟨inverseType, id, id⟩
  let bindings := parameterBindings
    (Caller.environment sourceCell recordsCell request.source records request.capacity)
  have restored : Semantics.Relocation.state symbols (Semantics.Relocation.state unrelocate afterArguments) =
      afterArguments := Semantics.Relocation.state_leftInverse symbols unrelocate inverse afterArguments
  obtain ⟨completed, execution, buffers, effect⟩ := Caller.callee_executes invariant request records
    recordsCapacity sourceCell recordsCell distinct
    (Semantics.Relocation.state_wellFormed unrelocate wellFormed)
    (Semantics.Relocation.world_owns unrelocate owned)
  have body := link.executes injective execution (link.agreement.body _ _ _ retained
    verifiedFrontendCore_finds_lexInto lexInto_has_body)
  rw [callee_relocated, restored] at body
  have linkedEffect := effect.relocate symbols
  rw [callee_relocated, restored] at linkedEffect
  have linkedBuffers := Semantics.Relocation.world_owns symbols buffers
  have found := link.matching.function (link.agreement.functionFound retained verifiedFrontendCore_finds_lexInto)
  have bound : bindParameters (Core.Relocation.function symbols lexIntoFunction).parameters
      [.slice Structure.i32Type sourceCell [] 0 request.source.length, .signed .i32 request.source.length,
        .slice Structure.i32Type recordsCell [] 0 records.length, .signed .i32 request.capacity] =
      some bindings := by rfl
  have bodyExact : (Core.Relocation.function symbols lexIntoFunction).body =
      some (Core.Relocation.statement symbols lexIntoBody) := by
    simp only [Core.Relocation.function, lexInto_has_body, Option.map_some]
  have closed := CellEffect.closeCall afterArguments bindings wellFormed linkedEffect
  refine ⟨restoreLocals afterArguments (Semantics.Relocation.state symbols completed),
    evaluatesCallReturned argumentsResult found bound bodyExact body, linkedBuffers, closed.narrow ?_⟩
  intro cell old written
  rcases written with output | fresh
  · exact output
  · exact (Nat.not_le_of_lt old fresh).elim

end Lanius.Extraction.RawLexer.LexInto.Linked
