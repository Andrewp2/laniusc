import Lanius.Extraction.RawLexer.LexInto.Linked
import Lanius.Extraction.Source.Projection
import Lanius.Extraction.BufferCopy.Canonicalize

namespace Lanius.Extraction.Frontend

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core
open Lanius.Extraction.RawLexer.LexInto

/-- Execute the actual lexer/result-count prefix. The continuation starts in
the source's two nested local scopes, with the emitted buffer and count already
derived. Unrelated storage and slice/scalar locals remain available for copying,
canonicalization, recognition, and materialization. -/
theorem lex_then_count
    (invariant : ∀ rename, Semantics.CellRenaming.Execution.ProgramInvariant rename verifiedFrontendCore)
    (link : Semantics.Relocation.Link allowed symbols verifiedFrontendCore program.core)
    (injective : Function.Injective symbols.typeId)
    (inverseType : Lanius.TypeId → Lanius.TypeId)
    (inverse : Function.RightInverse inverseType symbols.typeId)
    (retained : allowed Functions.lexIntoFunction.id = true)
    (accessor : Source.CheckedProjection program ["verified", "raw_lexer"] "lex_token_count"
      (symbols.typeId 4) 1)
    (request : Model.Request) (records : List Int)
    (recordsCapacity : 3 * request.capacity ≤ records.length)
    (sourceCell rawCell : CellId) (distinct : sourceCell ≠ rawCell)
    (lexedId countId : VarId) {before : State} {arguments : List Expr}
    (distinctNames : countId ≠ lexedId)
    (wellFormed : StateWellFormed before)
    (owned : (ReadOnly.World.owns (ReadOnly.World.pair sourceCell
      (RawLexer.ScanOne.Model.sourceIntegers request.source) rawCell records)).holds before)
    (argumentsResult : ArgumentsEvaluateTo program.core before arguments
      [.slice Structure.i32Type sourceCell [] 0 request.source.length, .signed .i32 request.source.length,
        .slice Structure.i32Type rawCell [] 0 records.length, .signed .i32 request.capacity] before) :
    ∃ ready,
      (∀ rest completion final, Executes program.core ready rest completion final →
        Executes program.core before
          (.letLocal lexedId (.structure (symbols.typeId 4))
            (.call (symbols.functionId Functions.lexIntoFunction.id) arguments)
            (.letLocal countId (.scalar (.signed .i32))
              (.call accessor.source.function.id [.local lexedId]) rest)) completion
          (restoreLocals before final)) ∧
      StateWellFormed ready ∧
      ready.local? countId = some (.signed .i32 (Model.emittedTokens request.outcome).length) ∧
      ready.local? lexedId = some (Core.Relocation.value symbols (Model.resultValue request.outcome)) ∧
      (ReadOnly.World.owns (ReadOnly.World.pair sourceCell
        (RawLexer.ScanOne.Model.sourceIntegers request.source) rawCell
        (CanonicalTokens.CanonicalizeModel.encodeTokens (Model.emittedTokens request.outcome) ++
          records.drop (3 * (Model.emittedTokens request.outcome).length)))).holds ready ∧
      (∀ cell value, before.cellEntry? cell = some { id := cell, value := value } → cell ≠ rawCell →
        ready.cellEntry? cell = some { id := cell, value := value }) ∧
      (∀ id value, before.local? id = some value → lexedId ≠ id → countId ≠ id →
        value ≠ .array (signedI32Values records) → ready.local? id = some value) ∧
      CellEffect (CellSet.singleton rawCell) before (restoreLocals before ready) := by
  obtain ⟨lexed, lexerCall, buffers, lexerEffect⟩ := Linked.call_evaluates_at invariant link injective
    inverseType inverse retained request records recordsCapacity sourceCell rawCell distinct
      wellFormed owned argumentsResult
  let result := Core.Relocation.value symbols (Model.resultValue request.outcome)
  let withResult := lexed.bindLocal lexedId result
  have resultWF : StateWellFormed withResult := bindLocal_preserves_well_formed _ _ _ lexerEffect.wellFormed
  have resultLocal : withResult.local? lexedId = some result := bindLocal_finds_local _ _ _ lexerEffect.wellFormed
  have projected : ∃ fields, result = .structure (symbols.typeId 4) fields ∧
      fields[1]? = some (.signed .i32 (Model.emittedTokens request.outcome).length) := by
    dsimp only [result]
    cases request.outcome <;> exact ⟨_, rfl, rfl⟩
  obtain ⟨fields, resultShape, countField⟩ := projected
  obtain ⟨counted, countCall, countEffect⟩ := accessor.call resultWF
    (.singleton (show Evaluates program.core withResult (.local lexedId)
      (.structure (symbols.typeId 4) fields) withResult from
      ⟨1, evalLocal_of_local 0 _ _ _ _ (resultShape ▸ resultLocal)⟩)) countField
  let ready := counted.bindLocal countId (.signed .i32 (Model.emittedTokens request.outcome).length)
  have readyWF : StateWellFormed ready := bindLocal_preserves_well_formed _ _ _ countEffect.wellFormed
  have preserveResult {cell : CellId} {value : Option Value}
      (found : lexed.cellEntry? cell = some { id := cell, value := value }) :
      withResult.cellEntry? cell = some { id := cell, value := value } :=
    ((bindLocal_effect lexed lexedId result).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry lexerEffect.wellFormed found) (by simp [CellSet.empty])).trans found
  have preserveCount {cell : CellId} {value : Option Value}
      (found : counted.cellEntry? cell = some { id := cell, value := value }) :
      ready.cellEntry? cell = some { id := cell, value := value } :=
    ((bindLocal_effect counted countId _).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry countEffect.wellFormed found) (by simp [CellSet.empty])).trans found
  refine ⟨ready, ?_, readyWF, bindLocal_finds_local _ _ _ countEffect.wellFormed, ?_, ?_, ?_, ?_, ?_⟩
  · intro rest completion final tailRun
    simpa only [restoreLocals, lexerEffect.locals] using
      executesLetLocal (type := .structure (symbols.typeId 4)) lexerCall
        (executesLetLocal (type := .scalar (.signed .i32)) countCall tailRun)
  · exact (bindLocal_preserves_other_local countEffect.wellFormed distinctNames).trans
      (countEffect.empty_preserves_local resultWF resultLocal)
  · intro cell values found
    exact preserveCount (countEffect.empty_preserves_entry resultWF (preserveResult (buffers cell values found)))
  · intro cell value found untouched
    exact preserveCount (countEffect.empty_preserves_entry resultWF
      (preserveResult (lexerEffect.preserves_entry wellFormed found untouched)))
  · intro id value found notResult notCount notArray
    have rawContents := owned _ _ (ReadOnly.World.pair_finds_second (Ne.symm distinct))
    have afterLexer := lexerEffect.preserves_local wellFormed found
      (fun _ binding => local_cell_ne_of_distinct_value found rawContents notArray binding)
    have afterResult := (bindLocal_preserves_other_local lexerEffect.wellFormed notResult
      (value := result)).trans afterLexer
    have afterCount := countEffect.empty_preserves_local resultWF afterResult
    exact (bindLocal_preserves_other_local countEffect.wellFormed notCount).trans afterCount
  · have countClosed := CellEffect.closeLocal counted countId
      (.signed .i32 (Model.emittedTokens request.outcome).length) countEffect.wellFormed
      (CellEffect.refl (writes := CellSet.empty) readyWF)
    have prefixClosed := CellEffect.closeLocal lexed lexedId result lexerEffect.wellFormed
      (countEffect.trans countClosed)
    have total := lexerEffect.trans (prefixClosed.weaken CellSet.empty_subset)
    simpa only [restoreLocals, lexerEffect.locals] using total

end Lanius.Extraction.Frontend
