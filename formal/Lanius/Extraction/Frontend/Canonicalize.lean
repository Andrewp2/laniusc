import Lanius.Extraction.Frontend.Lexer
import Lanius.Extraction.Frontend.Guards

namespace Lanius.Extraction.Frontend

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.Compiler.Lexer
open Lanius.Extraction.RawLexer.LexInto
open Lanius.Extraction.CanonicalTokens CanonicalizeModel Compaction

/-- The actual successful source prefix from lexer invocation to canonical
tokens. Every intermediate call and both guards are executed here. The only
continuation premise concerns the later parser stages, after token_count is
bound. Capacity and logical lexer success are explicit input-domain conditions. -/
theorem lex_to_canonical
    (symbols : TokenizationSymbols)
    (invariant : ∀ rename, Semantics.CellRenaming.Execution.ProgramInvariant rename verifiedFrontendCore)
    (link : Semantics.Relocation.Link allowed relocation verifiedFrontendCore program.core)
    (injective : Function.Injective relocation.typeId)
    (inverseType : Lanius.TypeId → Lanius.TypeId)
    (inverse : Function.RightInverse inverseType relocation.typeId)
    (retained : allowed Functions.lexIntoFunction.id = true)
    (countAccessor : Source.CheckedProjection program ["verified", "raw_lexer"] "lex_token_count"
      (relocation.typeId 4) 1)
    (statusAccessor : Source.CheckedProjection program ["verified", "raw_lexer"] "lex_status" symbols.resultType 0)
    (lexerId : symbols.lexer = relocation.functionId Functions.lexIntoFunction.id)
    (countId : symbols.count = countAccessor.source.function.id)
    (statusId : symbols.status = statusAccessor.source.function.id)
    (resultType : symbols.resultType = relocation.typeId 4)
    (successConstant : Trivia.ConstantAt program.core symbols.success 0)
    (canonicalizer : CheckedSource program.core symbols.canonicalize triviaId kindId keywordId matcher)
    (request : Model.Request) (raw : List RawToken) (successful : request.outcome = .completed raw)
    (records canonical : List Int) (wordCapacity : request.capacity = records.length / 3)
    (recordsFit : records.length ≤ 2147483647) (canonicalFit : canonical.length ≤ 2147483647)
    (capacity : 3 * raw.length ≤ canonical.length)
    (sourceCell rawCell canonicalCell : CellId)
    (sourceRaw : sourceCell ≠ rawCell) (sourceCanonical : sourceCell ≠ canonicalCell)
    (rawCanonical : rawCell ≠ canonicalCell)
    (before : State) (wellFormed : StateWellFormed before)
    (sourceLocal : before.local? 0 = some (.slice Structure.i32Type sourceCell [] 0 request.source.length))
    (sourceLength : before.local? 1 = some (.signed .i32 request.source.length))
    (rawLocal : before.local? 4 = some (.slice Structure.i32Type rawCell [] 0 records.length))
    (rawLength : before.local? 5 = some (.signed .i32 records.length))
    (canonicalLocal : before.local? 6 = some (.slice Structure.i32Type canonicalCell [] 0 canonical.length))
    (canonicalLength : before.local? 7 = some (.signed .i32 canonical.length))
    (owned : (ReadOnly.World.owns (ReadOnly.World.pair sourceCell (sourceIntegers request.source)
      rawCell records)).holds before)
    (canonicalContents : before.cellEntry? canonicalCell = some {
      id := canonicalCell, value := some (.array (signedI32Values canonical)) }) :
    let tokens := canonicalizeTokens request.source raw
    ∃ ready,
      (∀ lexicalFailure storageFailure rest completion final,
        Executes program.core ready rest completion final →
        Executes program.core before (tokenizationBody symbols lexicalFailure storageFailure rest)
          completion (restoreLocals before final)) ∧
      StateWellFormed ready ∧
      ready.local? 18 = some (.signed .i32 raw.length) ∧
      ready.local? 20 = some (.signed .i32 tokens.length) ∧
      (ReadOnly.World.owns (ReadOnly.World.pair sourceCell (sourceIntegers request.source) rawCell
        (encodeTokens raw ++ records.drop (3 * raw.length)))).holds ready ∧
      ready.cellEntry? canonicalCell = some { id := canonicalCell, value := some (.array (signedI32Values
        (compactedBuffer raw (canonical.drop (3 * raw.length)) tokens))) } ∧
      (∀ id value, id < 17 → before.local? id = some value →
        value ≠ .array (signedI32Values records) → value ≠ .array (signedI32Values canonical) →
        ready.local? id = some value) ∧
      CellEffect (CellSet.union (CellSet.singleton rawCell) (CellSet.singleton canonicalCell))
        before (restoreLocals before ready) := by
  dsimp only
  have recordsCapacity : 3 * request.capacity ≤ records.length := by rw [wordCapacity]; omega
  have emitted : Model.emittedTokens request.outcome = raw := by rw [successful]; rfl
  have quotient := evaluatesNatI32Divide
    (show Evaluates program.core before (.local 5) (.signed .i32 records.length) before from
      ⟨1, evalLocal_of_local 0 _ _ _ _ rawLength⟩)
    (show Evaluates program.core before (.value (.signed .i32 3)) (.signed .i32 3) before from ⟨1, rfl⟩)
    (by decide) (Nat.le_trans (Nat.div_le_self _ _) recordsFit)
  have argumentsResult : ArgumentsEvaluateTo program.core before
      [.local 0, .local 1, .local 4, .binary .divide (.local 5) (.value (.signed .i32 3))]
      [.slice Structure.i32Type sourceCell [] 0 request.source.length, .signed .i32 request.source.length,
        .slice Structure.i32Type rawCell [] 0 records.length, .signed .i32 request.capacity] before :=
    .cons ⟨1, evalLocal_of_local 0 _ _ _ _ sourceLocal⟩
      (.cons ⟨1, evalLocal_of_local 0 _ _ _ _ sourceLength⟩
        (.cons ⟨1, evalLocal_of_local 0 _ _ _ _ rawLocal⟩ (.singleton (wordCapacity ▸ quotient))))
  obtain ⟨lexed, prefixRun, lexedWF, countLocal, resultLocal, buffers, preserved, localsPreserved, prefixEffect⟩ :=
    lex_then_count invariant link injective inverseType inverse retained countAccessor request records recordsCapacity
      sourceCell rawCell sourceRaw 17 18 (by decide) wellFormed owned argumentsResult
  have countReady : lexed.local? 18 = some (.signed .i32 raw.length) := by simpa only [emitted] using countLocal
  have resultReady : lexed.local? 17 = some
      (.structure symbols.resultType [.signed .i32 0, .signed .i32 raw.length, .signed .i32 0]) := by
    simpa only [successful, Model.resultValue, Core.Relocation.value, Core.Relocation.values, resultType,
      Int.ofNat_eq_natCast] using resultLocal
  have capacityReady := localsPreserved 7 _ canonicalLength (by decide) (by decide) (by intro same; cases same)
  -- Passing the guards does not depend on the failure bodies or later code.
  let guards := tokenGuards symbols .skip .skip .skip
  obtain ⟨guarded, pass, guardEffect⟩ := guards.pass statusAccessor statusId successConstant lexed raw.length
    canonical.length lexedWF resultReady countReady capacityReady canonicalFit capacity
  have guardedBuffers : (ReadOnly.World.owns (ReadOnly.World.pair sourceCell (sourceIntegers request.source)
      rawCell (encodeTokens (Model.emittedTokens request.outcome) ++
        records.drop (3 * (Model.emittedTokens request.outcome).length)))).holds guarded := by
    intro cell values found
    exact guardEffect.empty_preserves_entry lexedWF (buffers cell values found)
  have canonicalGuarded := guardEffect.empty_preserves_entry lexedWF
    (preserved _ _ canonicalContents (Ne.symm rawCanonical))
  have guardedLocal {id : VarId} {value : Value} (found : before.local? id = some value)
      (early : id < 17) (notArray : value ≠ .array (signedI32Values records)) :
      guarded.local? id = some value := guardEffect.empty_preserves_local lexedWF
    (localsPreserved id value found (Ne.symm (Nat.ne_of_lt early))
      (Ne.symm (Nat.ne_of_lt (Nat.lt_of_lt_of_le early (by decide : 17 ≤ 18)))) notArray)
  obtain ⟨copied, copyRun, copiedBuffers, copiedCanonical, copyEffect⟩ :=
    BufferCopy.copy_emitted_then_canonicalize canonicalizer guarded request records canonical 0 4 6 19 18
      sourceCell rawCell canonicalCell guardEffect.wellFormed sourceRaw sourceCanonical rawCanonical
      (by simp) recordsCapacity recordsFit canonicalFit (by simpa only [emitted] using capacity)
      (guardedLocal sourceLocal (by decide) (by intro same; cases same))
      (guardedLocal rawLocal (by decide) (by intro same; cases same))
      (guardedLocal canonicalLocal (by decide) (by intro same; cases same))
      (guardEffect.empty_preserves_local lexedWF countLocal) guardedBuffers canonicalGuarded
  simp only [emitted] at copyRun copiedBuffers copiedCanonical copyEffect
  let ready := copied.bindLocal 20 (.signed .i32 (canonicalizeTokens request.source raw).length)
  have readyWF : StateWellFormed ready := bindLocal_preserves_well_formed _ _ _ copyEffect.wellFormed
  have readyEntry {cell : CellId} {value : Option Value}
      (found : copied.cellEntry? cell = some { id := cell, value := value }) :
      ready.cellEntry? cell = some { id := cell, value := value } :=
    ((bindLocal_effect copied 20 _).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry copyEffect.wellFormed found) (by simp [CellSet.empty])).trans found
  have copiedLocal {id : VarId} {value : Value} (found : guarded.local? id = some value)
      (notCursor : 19 ≠ id) (notCount : 20 ≠ id) (notArray : value ≠ .array (signedI32Values canonical)) :
      ready.local? id = some value := by
    have bound := (bindLocal_preserves_other_local guardEffect.wellFormed notCursor
      (value := Value.signed .i32 0)).trans found
    have afterCopy := copyEffect.preserves_local
      (bindLocal_preserves_well_formed _ _ _ guardEffect.wellFormed) bound (by
        intro cell binding written
        have oldBinding : guarded.cellId? id = some cell := by
          simpa only [bindLocal_preserves_other_cellId guarded 19 id (.signed .i32 0) notCursor] using binding
        rcases written with destination | cursor
        · exact local_cell_ne_of_distinct_value found canonicalGuarded notArray oldBinding destination
        · exact Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_local_binding id cell guardEffect.wellFormed oldBinding) cursor)
    exact (bindLocal_preserves_other_local copyEffect.wellFormed notCount).trans afterCopy
  refine ⟨ready, ?_, readyWF,
    copiedLocal (guardEffect.empty_preserves_local lexedWF countReady) (by decide) (by decide)
      (by intro same; cases same), bindLocal_finds_local _ _ _ copyEffect.wellFormed,
    (fun cell values found => readyEntry (copiedBuffers cell values found)), readyEntry copiedCanonical, ?_, ?_⟩
  · intro lexicalFailure storageFailure rest completion final tailRun
    have copyComplete := copyRun 20 rest completion final tailRun
    have guardedComplete := pass lexicalFailure storageFailure (tokenCopy symbols rest).body _ _ copyComplete
    have completed := prefixRun _ _ _ guardedComplete
    simpa only [tokenizationBody, LexerPrefix.body, LexerPrefix.arguments, guards, tokenGuards,
      tokenCopy, BufferCopy.Canonicalization.body,
      lexerId, countId, resultType, restoreLocals] using completed
  · intro id value early found notRaw notCanonical
    exact copiedLocal (guardedLocal found early notRaw)
      (Ne.symm (Nat.ne_of_lt (Nat.lt_of_lt_of_le early (by decide : 17 ≤ 19))))
      (Ne.symm (Nat.ne_of_lt (Nat.lt_of_lt_of_le early (by decide : 17 ≤ 20)))) notCanonical
  · have countClosed := CellEffect.closeLocal copied 20
      (.signed .i32 (canonicalizeTokens request.source raw).length) copyEffect.wellFormed
      (CellEffect.refl (writes := CellSet.union (CellSet.singleton canonicalCell) (CellSet.singleton guarded.nextCell)) readyWF)
    have copyClosed := CellEffect.closeLocal guarded 19 (.signed .i32 0) guardEffect.wellFormed
      (copyEffect.trans countClosed)
    have copyVisible : CellEffect (CellSet.singleton canonicalCell) guarded (restoreLocals guarded ready) :=
      copyClosed.narrow (by
        intro cell old written
        rcases written with destination | cursor
        · exact destination
        · exact (Nat.ne_of_lt old cursor).elim)
    have second := (guardEffect.weaken CellSet.empty_subset).trans copyVisible
    have secondScoped : CellEffect (CellSet.singleton canonicalCell) lexed (restoreLocals lexed ready) := by
      simpa only [restoreLocals, guardEffect.locals] using second
    exact (prefixEffect.weaken CellSet.subset_union_left).transScoped
      (secondScoped.weaken CellSet.subset_union_right) wellFormed

end Lanius.Extraction.Frontend
