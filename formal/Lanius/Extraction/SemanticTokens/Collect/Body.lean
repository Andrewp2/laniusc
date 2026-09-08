import Lanius.Extraction.SemanticTokens.Collect.Loops

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Compiler.Parser ParserTreeLayout

/-- The collector's ten arguments and their backing storage, before any
collector statement executes. No temporary-local or successful-run premise. -/
structure Entry (data : TraversalData) (before : State) : Prop where
  wellFormed : StateWellFormed before
  grammar : data.grammar.Owns data.grammarCell before
  kinds : I32PrefixLocal before 2 data.kindsCell (data.tokens.map (Int.ofNat ∘ Token.kind))
  records : I32PrefixLocal before 4 data.recordsCell (treeFrom 0 0 data.tree).words
  offsets : I32PrefixLocal before 6 data.offsetsCell ((treeFrom 0 0 data.tree).offsets.map Int.ofNat)
  output : before.local? 8 = some (.slice i32 data.outputCell [] 0 data.original.length)
  backing : before.cellEntry? data.outputCell = some {
    id := data.outputCell, value := some (.array (signedI32Values data.original)) }
  grammarLength : before.local? 1 = some (.signed .i32 data.grammar.words.length)
  count : before.local? 3 = some (.signed .i32 data.tokens.length)
  wordLength : before.local? 5 = some (.signed .i32 (treeFrom 0 0 data.tree).words.length)
  nodeCount : before.local? 7 = some (.signed .i32 data.collection.records.length)
  capacityRead : before.local? 9 = some (.signed .i32 data.original.length)
  nodesFit : data.collection.records.length ≤ 2147483647
  capacityFit : data.original.length ≤ 2147483647
  separate : ∀ cell ∈ [data.grammarCell, data.kindsCell, data.recordsCell, data.offsetsCell], cell ≠ data.outputCell

theorem Entry.input_pass {data : TraversalData} (entry : Entry data before) (program : Program) :
    Evaluates program before inputGuard (.boolean false) before := by
  let input : InputScalars before := ⟨data.grammar.words.length, data.tokens.length, data.collection.records.length,
    (treeFrom 0 0 data.tree).words.length, entry.grammarLength, entry.count, entry.nodeCount, entry.wordLength⟩
  have result := input.evaluates program
  have header := data.grammar.encoded.headerPresent
  have tokenBound := data.tokensFit
  have headerPass : ¬ ((data.grammar.words.length : Int) ≤ 16) := by
    simp only [grammarHeaderWords] at header
    omega
  have tokenPass : ¬ ((1073741824 : Int) ≤ data.tokens.length) := by omega
  have nonnegative (n : Nat) : ¬ ((n : Int) ≤ -1) := by omega
  simpa only [InputScalars.bad, input, headerPass, tokenPass, nonnegative,
    decide_false, Bool.false_or] using result

theorem Entry.capacity_pass {data : TraversalData} (entry : Entry data before) (program : Program) :
    Evaluates program before capacityGuard (.boolean false) before := by
  have result := capacityGuard_nonnegative program data.tokens.length data.original.length
    entry.count entry.capacityRead entry.capacityFit
  have enough : ¬ data.original.length / 2 < data.tokens.length := by have := data.capacity; omega
  simpa only [enough, decide_false] using result

theorem Entry.loops {data : TraversalData} (entry : Entry data before) :
    LoopEntry data (data.grammar.entered before) := by
  have firstWF := bindLocal_preserves_well_formed before 10 (.signed .i32 data.grammar.grammar.grammar.n_kinds) entry.wellFormed
  have fullWF := bindLocal_preserves_well_formed _ 11 (.signed .i32 data.grammar.layout.canonicalKindsOffset) firstWF
  have keep {id : VarId} {value : Value} (low : id < 10) (found : before.local? id = some value) :
      (data.grammar.entered before).local? id = some value := by
    have ne10 : (10 : VarId) ≠ id := by dsimp only [VarId] at low ⊢; omega
    have ne11 : (11 : VarId) ≠ id := by dsimp only [VarId] at low ⊢; omega
    exact (bindLocal_preserves_other_local firstWF ne11).trans
      ((bindLocal_preserves_other_local entry.wellFormed ne10).trans found)
  have preserved {id : VarId} {cell : CellId} {words : List Int} (low : id < 10)
      (owned : I32PrefixLocal before id cell words) : I32PrefixLocal (data.grammar.entered before) id cell words := by
    have ne10 : (10 : VarId) ≠ id := by dsimp only [VarId] at low ⊢; omega
    have ne11 : (11 : VarId) ≠ id := by dsimp only [VarId] at low ⊢; omega
    exact (owned.bindLocal entry.wellFormed 10 _ ne10).bindLocal firstWF 11 _ ne11
  have loaded := data.grammar.loaded entry.wellFormed entry.grammar entry.grammarLength
  have firstEffect := bindLocal_effect before 10 (.signed .i32 data.grammar.grammar.grammar.n_kinds)
  have secondEffect := bindLocal_effect
    (before.bindLocal 10 (.signed .i32 data.grammar.grammar.grammar.n_kinds)) 11
    (.signed .i32 data.grammar.layout.canonicalKindsOffset)
  have old := StateWellFormed.cell_lt_next_of_entry entry.wellFormed entry.backing
  have firstBacking := (firstEffect.oldCells data.outputCell old (by simp [CellSet.empty])).trans entry.backing
  have backing := (secondEffect.oldCells data.outputCell
    (StateWellFormed.cell_lt_next_of_entry firstWF firstBacking) (by simp [CellSet.empty])).trans firstBacking
  exact ⟨fullWF, preserved (by decide) entry.grammar, preserved (by decide) entry.kinds,
    preserved (by decide) entry.records, preserved (by decide) entry.offsets,
    keep (by decide) entry.output, backing,
    keep (by decide) entry.count, keep (by decide) entry.wordLength, keep (by decide) entry.nodeCount,
    loaded.kindRead, loaded.offsetRead, entry.nodesFit, entry.separate⟩

/-- The entire collector body returns success and exactly the selected tree's
accepted assignments. Initial guards, metadata reads, all loops, and lexical
scope restoration are included. -/
theorem Entry.execute {data : TraversalData} (entry : Entry data before)
    (program : Program) (symbols : Symbols)
    (tokenTag : ParserTreeSource.constantValue program symbols.childToken 1)
    (stateTag : ParserTreeSource.constantValue program symbols.childState 2) :
    ∃ after, Executes program before (body symbols) (.returned (some (.signed .i32 0))) after ∧
      after.cellEntry? data.outputCell = some {
        id := data.outputCell, value := some (.array (signedI32Values
          (data.collection.assignments.flatMap Assignment.words ++ data.original.drop (data.tokens.length * 2)))) } ∧
      CellEffect (CellSet.singleton data.outputCell) before after := by
  have first := data.grammar.header entry.grammar program 1 _ data.grammar.encoded.kindCount
  have firstWF := bindLocal_preserves_well_formed before 10 (.signed .i32 data.grammar.grammar.grammar.n_kinds) entry.wellFormed
  have firstOwned := entry.grammar.bindLocal entry.wellFormed 10 (.signed .i32 data.grammar.grammar.grammar.n_kinds) (by decide)
  have second := data.grammar.header firstOwned program 7 _ data.grammar.encoded.canonicalKindsOffset
  have loaded := data.grammar.loaded entry.wellFormed entry.grammar entry.grammarLength
  obtain ⟨completed, run, contents, effect⟩ := entry.loops.execute program symbols tokenTag stateTag
  have guarded := executesSequence (executesIfFalse (thenBranch := returned (negative 1)) (loaded.guard program) (executesSkip _ _)) run
  have inner := executesLetLocal (id := 11) (type := i32) second guarded
  have outer := executesLetLocal (id := 10) (type := i32) first inner
  have initial := executesSequence (executesIfFalse (thenBranch := returned (negative 1)) (entry.input_pass program) (executesSkip _ _))
    (executesSequence (executesIfFalse (thenBranch := returned (negative 2)) (entry.capacity_pass program) (executesSkip _ _)) outer)
  have innerEffect := CellEffect.closeLocal _ 11 (.signed .i32 data.grammar.layout.canonicalKindsOffset) firstWF effect
  have outerEffect := CellEffect.closeLocal before 10 (.signed .i32 data.grammar.grammar.grammar.n_kinds) entry.wellFormed innerEffect
  exact ⟨restoreLocals before completed, initial, contents, outerEffect⟩

/-- Transfer the execution contract to the complete source function selected
by the proof-producing collector checker, not a matching fragment. -/
theorem CheckedCollect.execute_body {artifacts : List Artifact}
    {checkedProgram : CoreSynthesis.Program.CheckedProgram artifacts}
    (checked : CheckedCollect checkedProgram) {data : TraversalData}
    (entry : Entry data before) (present : checked.source.function.body = some statement) :
    ∃ after, Executes checkedProgram.core before statement (.returned (some (.signed .i32 0))) after ∧
      after.cellEntry? data.outputCell = some {
        id := data.outputCell, value := some (.array (signedI32Values
          (data.collection.assignments.flatMap Assignment.words ++ data.original.drop (data.tokens.length * 2)))) } ∧
      CellEffect (CellSet.singleton data.outputCell) before after := by
  have same := Option.some.inj (present.symm.trans checked.bodyExact)
  subst statement
  exact entry.execute checkedProgram.core checked.symbols checked.tokenTag checked.stateTag

end Lanius.Extraction.SemanticTokens.Collect
