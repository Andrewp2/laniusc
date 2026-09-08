import Lanius.Extraction.Frontend.Failure
import Lanius.Extraction.Frontend.Canonicalize

namespace Lanius.Extraction.Frontend

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.FunctionalView.Core Lanius.Compiler.Lexer
open Lanius.Extraction.RawLexer.LexInto
open Lanius.Extraction.CanonicalTokens CanonicalizeModel Compaction

/-- Early extraction results distinguish a lexical error, raw-output exhaustion,
and canonical-output exhaustion. No resource error is reported as success, and
the impossible logical fuel-exhaustion case is not admitted. -/
def lexerEarlyPost (outcome : Model.Outcome) (capacity : Nat) (stage detail position : Int) : Prop :=
  match outcome with
  | .completed raw => capacity < 3 * raw.length ∧ stage = 3 ∧ detail = 0 ∧ position = 0
  | .lexicalFailure _ error => stage = 2 ∧ detail = 1 ∧ position = error
  | .outputFull _ offset => stage = 2 ∧ detail = 2 ∧ position = offset
  | .impossibleFuelExhaustion _ _ => False

theorem lexerEarlyPost.stage {stage : Int} (post : lexerEarlyPost outcome capacity stage detail position) :
    stage = 2 ∨ stage = 3 := by
  cases outcome <;> simp_all [lexerEarlyPost]

/-- Execute from the actual lexer invocation through either of the two first
failure returns. The only storage required is the lexer's source/raw pair; later
destinations are never inspected. The logical rejection condition excludes only
the successful-and-sufficient-capacity branch covered by lex_to_canonical. -/
theorem lex_to_early_failure
    (checked : CheckedEarly program symbols)
    (invariant : ∀ rename, Semantics.CellRenaming.Execution.ProgramInvariant rename verifiedFrontendCore)
    (link : Semantics.Relocation.Link allowed relocation verifiedFrontendCore program.core)
    (injective : Function.Injective relocation.typeId)
    (inverseType : Lanius.TypeId → Lanius.TypeId)
    (inverse : Function.RightInverse inverseType relocation.typeId)
    (retained : allowed Functions.lexIntoFunction.id = true)
    (countAccessor : Source.CheckedProjection program ["verified", "raw_lexer"] "lex_token_count"
      (relocation.typeId 4) 1)
    (lexerId : symbols.lexer = relocation.functionId Functions.lexIntoFunction.id)
    (countId : symbols.count = countAccessor.source.function.id)
    (resultType : symbols.resultType = relocation.typeId 4)
    (request : Model.Request) (records : List Int) (capacity : Nat)
    (wordCapacity : request.capacity = records.length / 3)
    (recordsFit : records.length ≤ 2147483647) (capacityFit : capacity ≤ 2147483647)
    (rejected : ∀ raw, request.outcome = .completed raw → capacity < 3 * raw.length)
    (sourceCell rawCell : CellId) (sourceRaw : sourceCell ≠ rawCell)
    (before : State) (wellFormed : StateWellFormed before)
    (sourceLocal : before.local? 0 = some (.slice Structure.i32Type sourceCell [] 0 request.source.length))
    (sourceLength : before.local? 1 = some (.signed .i32 request.source.length))
    (rawLocal : before.local? 4 = some (.slice Structure.i32Type rawCell [] 0 records.length))
    (rawLength : before.local? 5 = some (.signed .i32 records.length))
    (capacityLocal : before.local? 7 = some (.signed .i32 capacity))
    (owned : (ReadOnly.World.owns (ReadOnly.World.pair sourceCell (sourceIntegers request.source)
      rawCell records)).holds before) :
    ∃ stage detail position after,
      lexerEarlyPost request.outcome capacity stage detail position ∧
      (∀ rest, Executes program.core before
        (tokenizationBody symbols checked.lexicalBody checked.canonicalBody rest)
        (.returned (some (syntaxResult checked.constructor.typeId stage detail
          (Model.emittedTokens request.outcome).length 0 0 0 position))) after) ∧
      (ReadOnly.World.owns (ReadOnly.World.pair sourceCell (sourceIntegers request.source) rawCell
        (encodeTokens (Model.emittedTokens request.outcome) ++
          records.drop (3 * (Model.emittedTokens request.outcome).length)))).holds after ∧
      CellEffect (CellSet.singleton rawCell) before after := by
  have recordsCapacity : 3 * request.capacity ≤ records.length := by rw [wordCapacity]; omega
  have quotient := evaluatesNatI32Divide
    (show Evaluates program.core before (.local 5) (.signed .i32 records.length) before from
      ⟨1, evalLocal_of_local 0 _ _ _ _ rawLength⟩)
    (show Evaluates program.core before (.value (.signed .i32 3)) (.signed .i32 3) before from ⟨1, rfl⟩)
    (by decide) (Nat.le_trans (Nat.div_le_self _ _) recordsFit)
  have arguments : ArgumentsEvaluateTo program.core before
      [.local 0, .local 1, .local 4, .binary .divide (.local 5) (.value (.signed .i32 3))]
      [.slice Structure.i32Type sourceCell [] 0 request.source.length, .signed .i32 request.source.length,
        .slice Structure.i32Type rawCell [] 0 records.length, .signed .i32 request.capacity] before :=
    .cons ⟨1, evalLocal_of_local 0 _ _ _ _ sourceLocal⟩
      (.cons ⟨1, evalLocal_of_local 0 _ _ _ _ sourceLength⟩
        (.cons ⟨1, evalLocal_of_local 0 _ _ _ _ rawLocal⟩ (.singleton (wordCapacity ▸ quotient))))
  obtain ⟨lexed, prefixRun, lexedWF, countLocal, resultLocal, buffers, _, localsPreserved, prefixEffect⟩ :=
    lex_then_count invariant link injective inverseType inverse retained countAccessor request records recordsCapacity
      sourceCell rawCell sourceRaw 17 18 (by decide) wellFormed owned arguments
  suffices ∃ stage detail position after,
      lexerEarlyPost request.outcome capacity stage detail position ∧
      (∀ rest, Executes program.core lexed (tokenGuards symbols checked.lexicalBody checked.canonicalBody rest).body
        (.returned (some (syntaxResult checked.constructor.typeId stage detail
          (Model.emittedTokens request.outcome).length 0 0 0 position))) after) ∧
      CellEffect CellSet.empty lexed after by
    obtain ⟨stage, detail, position, after, post, tailRun, tailEffect⟩ := this
    have tailScoped : CellEffect CellSet.empty lexed (restoreLocals lexed after) := by
      simpa only [restoreLocals, ← tailEffect.locals] using tailEffect
    refine ⟨stage, detail, position, restoreLocals before after, post, ?_, ?_,
      prefixEffect.transScoped (tailScoped.weaken CellSet.empty_subset) wellFormed⟩
    · intro rest
      simpa only [tokenizationBody, LexerPrefix.body, LexerPrefix.arguments, lexerId, countId, resultType]
        using prefixRun _ _ _ (tailRun rest)
    · intro cell values found
      exact tailEffect.empty_preserves_entry lexedWF (buffers cell values found)
  cases outcomeEq : request.outcome with
  | completed raw =>
      have resultReady : lexed.local? 17 = some (.structure symbols.resultType
          [.signed .i32 0, .signed .i32 raw.length, .signed .i32 0]) := by
        simpa only [outcomeEq, Model.resultValue, Core.Relocation.value, Core.Relocation.values, resultType,
          Int.ofNat_eq_natCast] using resultLocal
      obtain ⟨after, run, effect⟩ := checked.canonical_full lexed lexedWF raw.length capacity resultReady
        (by simpa only [outcomeEq, Model.emittedTokens] using countLocal)
        (localsPreserved 7 _ capacityLocal (by decide) (by decide) (by intro same; cases same))
        capacityFit (rejected raw outcomeEq)
      refine ⟨3, 0, 0, after, ⟨rejected raw outcomeEq, rfl, rfl, rfl⟩, ?_, effect⟩
      simpa only [Model.emittedTokens] using run checked.lexicalBody
  | lexicalFailure accepted error =>
      have resultReady : lexed.local? 17 = some (.structure symbols.resultType
          [.signed .i32 1, .signed .i32 accepted.length, .signed .i32 error]) := by
        simpa only [outcomeEq, Model.resultValue, Core.Relocation.value, Core.Relocation.values, resultType,
          Int.ofNat_eq_natCast] using resultLocal
      obtain ⟨after, run, effect⟩ := checked.lexer_failure lexed lexedWF resultReady
        (by simpa only [outcomeEq, Model.emittedTokens] using countLocal) (by decide)
      exact ⟨2, 1, error, after, ⟨rfl, rfl, rfl⟩, run checked.canonicalBody, effect⟩
  | outputFull accepted offset =>
      have resultReady : lexed.local? 17 = some (.structure symbols.resultType
          [.signed .i32 2, .signed .i32 accepted.length, .signed .i32 offset]) := by
        simpa only [outcomeEq, Model.resultValue, Core.Relocation.value, Core.Relocation.values, resultType,
          Int.ofNat_eq_natCast] using resultLocal
      obtain ⟨after, run, effect⟩ := checked.lexer_failure lexed lexedWF resultReady
        (by simpa only [outcomeEq, Model.emittedTokens] using countLocal) (by decide)
      exact ⟨2, 2, offset, after, ⟨rfl, rfl, rfl⟩, run checked.canonicalBody, effect⟩
  | impossibleFuelExhaustion accepted offset =>
      exact (Model.lexInto_ne_impossibleFuelExhaustion request.source request.capacity accepted offset outcomeEq).elim

/-- Execute the lexer, successful guards, raw copy, and canonicalizer before
the kind-capacity failure. Only raw/canonical storage may change; kind, parser,
and tree destinations do not need to exist for this branch to return correctly. -/
theorem lex_to_kinds_failure
    (checked : CheckedEarly program symbols)
    (invariant : ∀ rename, Semantics.CellRenaming.Execution.ProgramInvariant rename verifiedFrontendCore)
    (link : Semantics.Relocation.Link allowed relocation verifiedFrontendCore program.core)
    (injective : Function.Injective relocation.typeId)
    (inverseType : Lanius.TypeId → Lanius.TypeId)
    (inverse : Function.RightInverse inverseType relocation.typeId)
    (retained : allowed Functions.lexIntoFunction.id = true)
    (countAccessor : Source.CheckedProjection program ["verified", "raw_lexer"] "lex_token_count"
      (relocation.typeId 4) 1)
    (lexerId : symbols.lexer = relocation.functionId Functions.lexIntoFunction.id)
    (countId : symbols.count = countAccessor.source.function.id)
    (resultType : symbols.resultType = relocation.typeId 4)
    (canonicalizer : CheckedSource program.core symbols.canonicalize triviaId kindId keywordId matcher)
    (request : Model.Request) (raw : List RawToken) (successful : request.outcome = .completed raw)
    (records canonical : List Int) (kindCapacity : Nat) (wordCapacity : request.capacity = records.length / 3)
    (recordsFit : records.length ≤ 2147483647) (canonicalFit : canonical.length ≤ 2147483647)
    (capacity : 3 * raw.length ≤ canonical.length)
    (kindsFull : kindCapacity < (canonicalizeTokens request.source raw).length)
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
    (kindLength : before.local? 9 = some (.signed .i32 kindCapacity))
    (owned : (ReadOnly.World.owns (ReadOnly.World.pair sourceCell (sourceIntegers request.source)
      rawCell records)).holds before)
    (canonicalContents : before.cellEntry? canonicalCell = some {
      id := canonicalCell, value := some (.array (signedI32Values canonical)) }) :
    let tokens := canonicalizeTokens request.source raw
    ∃ after,
      (∀ functionId resultType rest, Executes program.core before
        (tokenizationBody symbols checked.lexicalBody checked.canonicalBody
          (recognitionBody functionId resultType checked.kindsBody rest))
        (.returned (some (syntaxResult checked.constructor.typeId 3 1 raw.length tokens.length 0 0 0))) after) ∧
      (ReadOnly.World.owns (ReadOnly.World.pair sourceCell (sourceIntegers request.source) rawCell
        (encodeTokens raw ++ records.drop (3 * raw.length)))).holds after ∧
      after.cellEntry? canonicalCell = some { id := canonicalCell, value := some (.array (signedI32Values
        (compactedBuffer raw (canonical.drop (3 * raw.length)) tokens))) } ∧
      CellEffect (CellSet.union (CellSet.singleton rawCell) (CellSet.singleton canonicalCell)) before after := by
  dsimp only
  obtain ⟨ready, prefixRun, readyWF, rawCount, tokenCount, buffers, canonicalBuffer, localsPreserved, prefixEffect⟩ :=
    lex_to_canonical symbols invariant link injective inverseType inverse retained countAccessor checked.status
      lexerId countId checked.statusId resultType checked.lexerSuccess canonicalizer request raw successful
      records canonical wordCapacity recordsFit canonicalFit capacity sourceCell rawCell canonicalCell sourceRaw
      sourceCanonical rawCanonical before wellFormed sourceLocal sourceLength rawLocal rawLength
      canonicalLocal canonicalLength owned canonicalContents
  obtain ⟨after, tailRun, tailEffect⟩ := checked.kinds_full ready readyWF _ kindCapacity rawCount tokenCount
    (localsPreserved 9 _ (by decide) kindLength (by intro same; cases same) (by intro same; cases same)) kindsFull
  have tailScoped : CellEffect CellSet.empty ready (restoreLocals ready after) := by
    simpa only [restoreLocals, ← tailEffect.locals] using tailEffect
  refine ⟨restoreLocals before after, ?_, ?_,
    tailEffect.empty_preserves_entry readyWF canonicalBuffer,
    prefixEffect.transScoped (tailScoped.weaken CellSet.empty_subset) wellFormed⟩
  · intro functionId resultType rest
    exact prefixRun _ _ _ _ _ (tailRun functionId resultType rest)
  · intro cell values found
    exact tailEffect.empty_preserves_entry readyWF (buffers cell values found)

end Lanius.Extraction.Frontend
