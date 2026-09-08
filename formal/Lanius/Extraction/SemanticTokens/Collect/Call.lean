import Lanius.Extraction.SemanticTokens.Collect.Body
import Lanius.FunctionalViewCoreSimulation
import Lanius.CallContracts

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Compiler.Parser
open Lanius.FunctionalView.Core
open Lanius.CallContracts

/-- Concrete argument order of the public Lanius collector. Logical counts
are independent of the capacities contained in the slice values. -/
def argumentValues (grammar kinds records offsets output : Value)
    (grammarLength tokenCount wordCount nodeCount : Nat) (capacity : Int) : List Value :=
  [grammar, .signed .i32 grammarLength, kinds, .signed .i32 tokenCount,
    records, .signed .i32 wordCount, offsets, .signed .i32 nodeCount, output, .signed .i32 capacity]

def argumentBindings (grammar kinds records offsets output : Value)
    (grammarLength tokenCount wordCount nodeCount : Nat) (capacity : Int) : List (VarId × Value) :=
  parameterBindings (fun index : Fin 10 =>
    (argumentValues grammar kinds records offsets output grammarLength tokenCount wordCount nodeCount capacity).get index)

/-- Caller-owned arrays; no callee locals or successful execution is assumed.
Each input may have spare storage not included in its logical contents. -/
structure CallStorage (data : TraversalData) (state : State) where
  grammarCapacity : Nat
  kindsCapacity : Nat
  recordsCapacity : Nat
  offsetsCapacity : Nat
  grammar : I32Prefix state data.grammarCell grammarCapacity data.grammar.words
  kinds : I32Prefix state data.kindsCell kindsCapacity (data.tokens.map (Int.ofNat ∘ Token.kind))
  records : I32Prefix state data.recordsCell recordsCapacity (ParserTreeLayout.treeFrom 0 0 data.tree).words
  offsets : I32Prefix state data.offsetsCell offsetsCapacity ((ParserTreeLayout.treeFrom 0 0 data.tree).offsets.map Int.ofNat)
  output : state.cellEntry? data.outputCell = some {
    id := data.outputCell, value := some (.array (signedI32Values data.original)) }

def CallStorage.values {data : TraversalData} (storage : CallStorage data state) : List Value :=
  argumentValues (.slice i32 data.grammarCell [] 0 storage.grammarCapacity)
    (.slice i32 data.kindsCell [] 0 storage.kindsCapacity)
    (.slice i32 data.recordsCell [] 0 storage.recordsCapacity)
    (.slice i32 data.offsetsCell [] 0 storage.offsetsCapacity)
    (.slice i32 data.outputCell [] 0 data.original.length)
    data.grammar.words.length data.tokens.length (ParserTreeLayout.treeFrom 0 0 data.tree).words.length
    data.collection.records.length data.original.length

def CallStorage.bindings {data : TraversalData} (storage : CallStorage data state) : List (VarId × Value) :=
  parameterBindings (fun index : Fin 10 => storage.values.get index)

theorem CallStorage.entry {data : TraversalData} (storage : CallStorage data before)
    (wellFormed : StateWellFormed before)
    (nodesFit : data.collection.records.length ≤ 2147483647)
    (capacityFit : data.original.length ≤ 2147483647)
    (separate : ∀ cell ∈ [data.grammarCell, data.kindsCell, data.recordsCell, data.offsetsCell], cell ≠ data.outputCell) :
    Entry data (enterCall before storage.bindings) := by
  have locals (index : Fin 10) : (enterCall before storage.bindings).local? index.val = some (storage.values.get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have preserve {cell : CellId} {value : Option Value}
      (found : before.cellEntry? cell = some { id := cell, value := value }) :
      (enterCall before storage.bindings).cellEntry? cell = some { id := cell, value := value } :=
    ((enterCall_effect before storage.bindings).oldCells cell
      (StateWellFormed.cell_lt_next_of_entry wellFormed found) (by simp [CellSet.empty])).trans found
  have prefixPreserved {cell : CellId} {capacity : Nat} {words : List Int}
      (owned : I32Prefix before cell capacity words) : I32Prefix (enterCall before storage.bindings) cell capacity words := by
    obtain ⟨unused, length, contents⟩ := owned
    exact ⟨unused, length, preserve contents⟩
  exact ⟨enterCall_preserves_wellFormed wellFormed,
    ⟨storage.grammarCapacity, locals ⟨0, by decide⟩, prefixPreserved storage.grammar⟩,
    ⟨storage.kindsCapacity, locals ⟨2, by decide⟩, prefixPreserved storage.kinds⟩,
    ⟨storage.recordsCapacity, locals ⟨4, by decide⟩, prefixPreserved storage.records⟩,
    ⟨storage.offsetsCapacity, locals ⟨6, by decide⟩, prefixPreserved storage.offsets⟩,
    locals ⟨8, by decide⟩, preserve storage.output, locals ⟨1, by decide⟩, locals ⟨3, by decide⟩,
    locals ⟨5, by decide⟩, locals ⟨7, by decide⟩, locals ⟨9, by decide⟩,
    nodesFit, capacityFit, separate⟩

variable {checkedProgram : CoreSynthesis.Program.CheckedProgram artifacts}

/-- Execute the current public function from evaluated arguments and caller
storage. Callee bindings, body execution, and caller-scope restoration follow
from the checked source, rather than being independent premises. -/
theorem CheckedCollect.call_evaluates (checked : CheckedCollect checkedProgram)
    {data : TraversalData} (storage : CallStorage data before) (wellFormed : StateWellFormed before)
    (nodesFit : data.collection.records.length ≤ 2147483647)
    (capacityFit : data.original.length ≤ 2147483647)
    (separate : ∀ cell ∈ [data.grammarCell, data.kindsCell, data.recordsCell, data.offsetsCell], cell ≠ data.outputCell)
    (argumentsResult : ArgumentsEvaluateTo checkedProgram.core caller arguments storage.values before) :
    ∃ after, Evaluates checkedProgram.core caller (.call checked.source.function.id arguments) (.signed .i32 0) after ∧
      after.cellEntry? data.outputCell = some {
        id := data.outputCell, value := some (.array (signedI32Values
          (data.collection.assignments.flatMap Assignment.words ++ data.original.drop (data.tokens.length * 2)))) } ∧
      CellEffect (CellSet.singleton data.outputCell) before after := by
  obtain ⟨completed, run, contents, effect⟩ := checked.execute_body
    (storage.entry wellFormed nodesFit capacityFit separate) checked.bodyExact
  have identity : checked.source.function.id = checked.source.source.id := by
    simpa [Program.function?] using List.find?_some checked.source.found
  have found : checkedProgram.core.function? checked.source.function.id = some checked.source.function := by
    rw [identity]
    exact checked.source.found
  have bound : bindParameters checked.source.function.parameters storage.values = some storage.bindings := by
    rw [checked.signature.1]
    rfl
  exact ⟨restoreLocals before completed, evaluatesCallReturned argumentsResult found bound checked.bodyExact run,
    contents, CellEffect.closeCall before storage.bindings wellFormed effect⟩

/-- Insufficient capacity returns -2 before reading any buffer. The five
buffer values need not refer to allocated storage on this failure path. -/
theorem CheckedCollect.short_capacity_call (checked : CheckedCollect checkedProgram)
    (grammar kinds records offsets output : Value) (grammarLength tokenCount wordCount nodeCount capacity : Nat)
    (wellFormed : StateWellFormed before) (header : 16 < grammarLength)
    (tokensFit : tokenCount * 2 ≤ 2147483647) (capacityFit : capacity ≤ 2147483647)
    (short : capacity / 2 < tokenCount)
    (argumentsResult : ArgumentsEvaluateTo checkedProgram.core caller arguments
      (argumentValues grammar kinds records offsets output grammarLength tokenCount wordCount nodeCount capacity) before) :
    ∃ after, Evaluates checkedProgram.core caller (.call checked.source.function.id arguments) (.signed .i32 (-2)) after ∧
      CellEffect CellSet.empty before after := by
  let bindings := argumentBindings grammar kinds records offsets output grammarLength tokenCount wordCount nodeCount capacity
  let callee := enterCall before bindings
  have locals (index : Fin 10) : callee.local? index.val = some
      ((argumentValues grammar kinds records offsets output grammarLength tokenCount wordCount nodeCount capacity).get index) :=
    enterCall_parameterBindings_matches wellFormed index
  let input : InputScalars callee := ⟨grammarLength, tokenCount, nodeCount, wordCount,
    locals ⟨1, by decide⟩, locals ⟨3, by decide⟩, locals ⟨7, by decide⟩, locals ⟨5, by decide⟩⟩
  have firstPass : input.bad = false := by
    have headerPass : ¬ ((grammarLength : Int) ≤ 16) := by omega
    have tokenPass : ¬ ((1073741824 : Int) ≤ tokenCount) := by omega
    have nonnegative (n : Nat) : ¬ ((n : Int) ≤ -1) := by omega
    simp only [InputScalars.bad, input, headerPass, tokenPass, nonnegative, decide_false, Bool.false_or]
  have run := input.reject_short_capacity checkedProgram.core checked.symbols firstPass tokenCount capacity
    (locals ⟨3, by decide⟩) (locals ⟨9, by decide⟩) capacityFit short
  have identity : checked.source.function.id = checked.source.source.id := by
    simpa [Program.function?] using List.find?_some checked.source.found
  have found : checkedProgram.core.function? checked.source.function.id = some checked.source.function := by
    rw [identity]
    exact checked.source.found
  have bound : bindParameters checked.source.function.parameters
      (argumentValues grammar kinds records offsets output grammarLength tokenCount wordCount nodeCount capacity) = some bindings := by
    rw [checked.signature.1]
    rfl
  exact ⟨restoreLocals before callee, evaluatesCallReturned argumentsResult found bound checked.bodyExact run,
    CellEffect.closeCall before bindings wellFormed (CellEffect.refl (enterCall_preserves_wellFormed wellFormed))⟩

end Lanius.Extraction.SemanticTokens.Collect
