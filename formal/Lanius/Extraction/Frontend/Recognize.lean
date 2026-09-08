import Lanius.Extraction.Frontend.Guards
import Lanius.Extraction.BufferCopy.Kinds
import Lanius.Extraction.Parser.Recognize.Linked

namespace Lanius.Extraction.Frontend

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Lexer Lanius.Compiler.Parser
open Lanius.Extraction.CanonicalTokens CanonicalizeModel Compaction
open Lanius.Extraction.ParserRecognize Lanius.Extraction.ParserAccessors Lanius.Extraction.ParserFind

/-- Execute the real kind-capacity guard, copy, and recognizer call from the
canonicalizer's buffer. The loop invariant, callee resources, and semantic
outcome are derived here. Only the later parse/tree continuation is a premise. -/
theorem canonical_to_recognize
    (link : Semantics.Relocation.Link allowed symbols verifiedParserCore program)
    (injective : Function.Injective symbols.typeId)
    (inverseType : TypeId → TypeId) (inverse : Function.RightInverse inverseType symbols.typeId)
    (retained : allowed extractedParserRecognizeFunction.id = true)
    (source : List Byte) (raw : List RawToken) (unused kinds workspaceValues : List Int)
    (before : State) (wellFormed : StateWellFormed before)
    (canonicalCell kindsCell grammarCell workspaceCell : CellId)
    (canonicalKinds : canonicalCell ≠ kindsCell) (canonicalWorkspace : canonicalCell ≠ workspaceCell)
    (grammarKinds : grammarCell ≠ kindsCell) (grammarWorkspace : grammarCell ≠ workspaceCell)
    (kindsWorkspace : kindsCell ≠ workspaceCell)
    (canonicalFit : 3 * raw.length + unused.length ≤ 2147483647)
    (kindsFit : kinds.length ≤ 2147483647)
    (capacity : (canonicalizeTokens source raw).length ≤ kinds.length)
    (grammarEncoded : EncodesGrammar grammarLayout grammar words)
    (grammarWellFormed : grammar.WellFormed) (wordsFit : words.length ≤ 2147483647)
    (workspaceLength : workspaceValues.length = workspaceLayout.workspaceLength)
    (workspaceTokenCount : workspaceLayout.tokenCount = (canonicalizeTokens source raw).length)
    (canonicalLocal : before.local? 6 = some
      (.slice (.scalar (.signed .i32)) canonicalCell [] 0 (3 * raw.length + unused.length)))
    (kindsLocal : before.local? 8 = some (.slice (.scalar (.signed .i32)) kindsCell [] 0 kinds.length))
    (kindsLength : before.local? 9 = some (.signed .i32 kinds.length))
    (countLocal : before.local? 20 = some (.signed .i32 (canonicalizeTokens source raw).length))
    (grammarLocal : before.local? 2 = some (parserGrammarValue words grammarCell))
    (grammarLengthLocal : before.local? 3 = some (.signed .i32 (Int.ofNat words.length)))
    (workspaceLocal : before.local? 10 = some (workspaceValue workspaceValues workspaceCell))
    (workspaceLengthLocal : before.local? 11 = some (.signed .i32 (Int.ofNat workspaceValues.length)))
    (canonicalContents : before.cellEntry? canonicalCell = some {
      id := canonicalCell, value := some (.array (signedI32Values
        (compactedBuffer raw unused (canonicalizeTokens source raw)))) })
    (kindsContents : before.cellEntry? kindsCell = some {
      id := kindsCell, value := some (.array (signedI32Values kinds)) })
    (grammarContents : before.cellEntry? grammarCell = some {
      id := grammarCell, value := some (.array (signedI32Values words)) })
    (workspaceContents : before.cellEntry? workspaceCell = some {
      id := workspaceCell, value := some (.array (signedI32Values workspaceValues)) }) :
    let tokens := canonicalizeTokens source raw
    let codes := tokens.map (fun token => token.kind.gpuCode)
    ∃ completion, ∃ (outcome : RecognizerInitialContinuationOutcome grammarLayout grammar words codes workspaceLayout completion),
      ∃ finalWorkspace finalValues ready,
      (∀ storageFailure rest completion final, Executes program ready rest completion final →
        Executes program before (recognitionBody (symbols.functionId extractedParserRecognizeFunction.id)
          (symbols.typeId 0) storageFailure rest) completion (restoreLocals before final)) ∧
      StateWellFormed ready ∧
      ready.local? 22 = some (Core.Relocation.value symbols outcome.resultValue) ∧
      outcome.workspaceAgrees finalWorkspace ∧
      WorkspaceAppendClosure workspaceLayout.capacity emptyWorkspace finalWorkspace ∧
      RecognizerWorkspaceArtifact workspaceLayout finalWorkspace finalValues workspaceCell ready ∧
      ready.cellEntry? canonicalCell = some {
        id := canonicalCell,
        value := some (.array (signedI32Values (compactedBuffer raw unused tokens))) } ∧
      ready.cellEntry? kindsCell = some {
        id := kindsCell,
        value := some (.array (signedI32Values (BufferCopy.tokenKinds tokens ++ kinds.drop tokens.length))) } ∧
      (∀ id value, id < 21 → before.local? id = some value →
        value ≠ .array (signedI32Values kinds) → value ≠ .array (signedI32Values workspaceValues) →
        ready.local? id = some value) ∧
      CellEffect (CellSet.union (CellSet.singleton kindsCell) (CellSet.singleton workspaceCell))
        before (restoreLocals before ready) := by
  dsimp only
  let tokens := canonicalizeTokens source raw
  let codes := tokens.map (fun token => token.kind.gpuCode)
  have guardRun := kinds_capacity_evaluates program before tokens.length kinds.length countLocal kindsLength
  simp only [tokens, capacity, decide_true, Bool.not_true] at guardRun
  obtain ⟨copied, copyRun, canonicalCopied, kindsCopied, kindsLocalCopied, countCopied, copiedWF, copyEffect⟩ :=
    BufferCopy.copy_kinds program before source raw unused kinds 6 8 21 20 canonicalCell kindsCell
      wellFormed canonicalKinds (by simp) canonicalFit kindsFit capacity canonicalLocal kindsLocal countLocal
      canonicalContents kindsContents
  have copiedEntry {cell : CellId} {value : Option Value}
      (found : before.cellEntry? cell = some { id := cell, value := value }) (different : cell ≠ kindsCell) :
      copied.cellEntry? cell = some { id := cell, value := value } := by
    have old := StateWellFormed.cell_lt_next_of_entry wellFormed found
    exact copyEffect.preserves_entry (bindLocal_preserves_well_formed _ _ _ wellFormed)
      (((bindLocal_effect before 21 (.signed .i32 0)).oldCells cell old (by simp [CellSet.empty])).trans found)
      (by simp only [CellSet.union, CellSet.singleton, not_or]; exact ⟨different, Nat.ne_of_lt old⟩)
  have copiedLocal {id : VarId} {value : Value} (found : before.local? id = some value)
      (early : id < 21) (notArray : value ≠ .array (signedI32Values kinds)) :
      copied.local? id = some value := by
    have different := Ne.symm (Nat.ne_of_lt early)
    have bound := (bindLocal_preserves_other_local wellFormed different (value := Value.signed .i32 0)).trans found
    apply copyEffect.preserves_local (bindLocal_preserves_well_formed _ _ _ wellFormed) bound
    intro cell binding written
    have oldBinding : before.cellId? id = some cell := by
      simpa only [bindLocal_preserves_other_cellId before 21 id (.signed .i32 0) different] using binding
    rcases written with destination | cursor
    · exact local_cell_ne_of_distinct_value found kindsContents notArray oldBinding destination
    · exact Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_local_binding id cell wellFormed oldBinding) cursor
  have prefixStorage : I32Prefix copied kindsCell kinds.length (codes.map Int.ofNat) := by
    simpa only [codes, List.map_map, Function.comp_def, BufferCopy.tokenKinds] using
      BufferCopy.kind_prefix tokens kinds capacity kindsCopied
  let region := recognitionRegion (symbols.functionId extractedParserRecognizeFunction.id) (symbols.typeId 0) .skip
  obtain ⟨completion, outcome, finalWorkspace, finalValues, parsed, callRun, agreement, growth, artifact, parseEffect⟩ :=
    recognize_region_at region link injective inverseType inverse retained rfl
      (copiedLocal grammarLocal (by change 2 < 21; decide) (by intro same; cases same))
      (copiedLocal grammarLengthLocal (by change 3 < 21; decide) (by intro same; cases same)) kindsLocalCopied
      (show copied.local? region.locals.count = some (.signed .i32 (Int.ofNat codes.length)) from by
        simpa only [region, recognitionRegion, codes, tokens, List.length_map, Int.ofNat_eq_natCast] using countCopied)
      (copiedLocal workspaceLocal (by change 10 < 21; decide) (by intro same; cases same))
      (copiedLocal workspaceLengthLocal (by change 11 < 21; decide) (by intro same; cases same)) copiedWF
      grammarEncoded grammarWellFormed wordsFit
      (by simpa only [codes, List.length_map] using Nat.le_trans capacity kindsFit)
      workspaceLength (by simpa only [codes, List.length_map] using workspaceTokenCount)
      (copiedEntry grammarContents grammarKinds) prefixStorage
      (copiedEntry workspaceContents (Ne.symm kindsWorkspace)) grammarWorkspace kindsWorkspace
  let ready := parsed.bindLocal 22 (Core.Relocation.value symbols outcome.resultValue)
  have readyWF : StateWellFormed ready := bindLocal_preserves_well_formed _ _ _ parseEffect.wellFormed
  have readyEntry {cell : CellId} {value : Option Value}
      (found : parsed.cellEntry? cell = some { id := cell, value := value }) :
      ready.cellEntry? cell = some { id := cell, value := value } :=
    ((bindLocal_effect parsed 22 _).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry parseEffect.wellFormed found) (by simp [CellSet.empty])).trans found
  refine ⟨completion, outcome, finalWorkspace, finalValues, ready, ?_, readyWF,
    bindLocal_finds_local _ _ _ parseEffect.wellFormed, agreement, growth,
    ⟨artifact.workspaceLength, artifact.workspaceEncoded, readyEntry artifact.workspaceBacking⟩,
    readyEntry (parseEffect.preserves_entry copiedWF canonicalCopied canonicalWorkspace),
    readyEntry (parseEffect.preserves_entry copiedWF kindsCopied kindsWorkspace), ?_, ?_⟩
  · intro storageFailure rest completion final continuation
    have run := copyRun _ _ _ (executesLetLocal (type := .structure (symbols.typeId 0)) callRun continuation)
    exact executesSequence (executesIfFalse guardRun (executesSkip _ _)) run
  · intro id value early found notKinds notWorkspace
    have preserved := parseEffect.preserves_local_of_distinct_value copiedWF
      (copiedLocal found early notKinds) (copiedEntry workspaceContents (Ne.symm kindsWorkspace)) notWorkspace
    exact (bindLocal_preserves_other_local parseEffect.wellFormed
      (Ne.symm (Nat.ne_of_lt (Nat.lt_of_lt_of_le early (by decide : 21 ≤ 22))))).trans preserved
  · let writes := CellSet.union (CellSet.singleton kindsCell) (CellSet.singleton workspaceCell)
    have copyClosed : CellEffect (CellSet.singleton kindsCell) before (restoreLocals before copied) :=
      (CellEffect.closeLocal before 21 (.signed .i32 0) wellFormed copyEffect).narrow (by
        intro cell old written
        rcases written with destination | cursor
        · exact destination
        · exact (Nat.ne_of_lt old cursor).elim)
    have resultClosed := CellEffect.closeLocal parsed 22 (Core.Relocation.value symbols outcome.resultValue)
      parseEffect.wellFormed (CellEffect.refl (writes := CellSet.singleton workspaceCell) readyWF)
    have parseClosed := parseEffect.trans resultClosed
    have parseScoped : CellEffect (CellSet.singleton workspaceCell) copied (restoreLocals copied ready) := by
      simpa only [restoreLocals, parseEffect.locals] using parseClosed
    exact (copyClosed.weaken (larger := writes) CellSet.subset_union_left).transScoped
      (parseScoped.weaken CellSet.subset_union_right) wellFormed

end Lanius.Extraction.Frontend
