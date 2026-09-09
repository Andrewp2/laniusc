import Lanius.Extraction.CompactOutput.Word.Call
import Lanius.Extraction.CompactOutput.Word.Chunks

namespace Lanius.Extraction.CompactOutput.PackHeader

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.Source Lanius.FunctionalView.Core

def parameters : List (VarId × Ty) := [(0, i32), (1, .slice i32), (2, i32), (3, i32)]
def body (wordId : FunctionId) : Stmt :=
  .letLocal 4 i32 (.call wordId [read 1, read 2, read 3, number 1])
    (returned (.call wordId [read 1, read 2, read 4, read 0]))
abbrev Checked (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (byte : CheckedByte program) (digit : CheckedDigit program) (word : Word.Checked program byte digit) :=
  CheckedInternal program ["verified", "compact_artifact_output"] "emit_header" parameters i32 (body word.source.function.id)
def check? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (byte : CheckedByte program) (digit : CheckedDigit program) (word : Word.Checked program byte digit) :
    Option (Checked program byte digit word) :=
  checkInternal? program ["verified", "compact_artifact_output"] "emit_header" parameters i32 (body word.source.function.id)

def encoding (count : Nat) : List Nat := hexDigits 1 8 ++ hexDigits count 8

theorem execute (word : Word.Checked program byte digit) (count capacity : Nat) (position : Int)
    (wellFormed : StateWellFormed before) (countFit : count ≤ 2147483647)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (countRead : before.local? 0 = some (.signed .i32 count))
    (outputRead : before.local? 1 = some (.slice i32 outputCell [] 0 original.length))
    (capacityRead : before.local? 2 = some (.signed .i32 capacity))
    (positionRead : before.local? 3 = some (.signed .i32 position))
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) }) :
    ∃ after, Executes program.core before (body word.source.function.id)
        (.returned (some (.signed .i32 (appendAll capacity (encoding count) position original).position))) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (appendAll capacity (encoding count) position original).contents)) } ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  obtain ⟨first, firstRun, firstBacking, firstEffect⟩ := word.write position capacity 1 wellFormed
    capacityBound capacityFit (by decide) backing
    (.cons (local_evaluates program.core outputRead) (.cons (local_evaluates program.core capacityRead)
      (.cons (local_evaluates program.core positionRead) (.cons
        (show Evaluates program.core before (number 1) (.signed .i32 1) before from ⟨1, rfl⟩) (.nil _ _)))))
  let next := (appendAll capacity (hexDigits 1 8) position original).position
  let entered := first.bindLocal 4 (.signed .i32 next)
  have enteredWF : StateWellFormed entered := bindLocal_preserves_well_formed _ _ _ firstEffect.wellFormed
  have keep {id : VarId} {value : Value} (differentId : (4 : VarId) ≠ id)
      (found : before.local? id = some value) (differentValue : value ≠ .array (signedI32Values original)) :
      entered.local? id = some value := by
    apply (bindLocal_preserves_other_local firstEffect.wellFormed differentId).trans
    apply firstEffect.preserves_local wellFormed found
    intro cell binding changed
    exact local_cell_ne_of_distinct_value found backing differentValue binding changed
  have enteredBacking := ((bindLocal_effect first 4 (.signed .i32 next)).oldCells outputCell
    (StateWellFormed.cell_lt_next_of_entry firstEffect.wellFormed firstBacking) (by simp [CellSet.empty])).trans firstBacking
  have nextRead : entered.local? 4 = some (.signed .i32 next) := bindLocal_finds_local first _ _ firstEffect.wellFormed
  have output : entered.local? 1 = some (.slice i32 outputCell [] 0
      (appendAll capacity (hexDigits 1 8) position original).contents.length) := by
    simpa only [appendAll_length] using keep (by decide) outputRead (by intro same; cases same)
  obtain ⟨written, secondRun, secondBacking, secondEffect⟩ := word.write next capacity count enteredWF
    (by simpa only [appendAll_length] using capacityBound) capacityFit countFit enteredBacking
    (.cons (local_evaluates program.core output) (.cons
      (local_evaluates program.core (keep (by decide) capacityRead (by intro same; cases same)))
      (.cons (local_evaluates program.core nextRead) (.cons
        (local_evaluates program.core (keep (by decide) countRead (by intro same; cases same))) (.nil _ _)))))
  have run := executesLetLocal (id := 4) (type := i32) firstRun
    (executesSequenceReturned (second := .skip) (executesReturnValue secondRun))
  have closed := CellEffect.closeLocal first 4 (.signed .i32 next) firstEffect.wellFormed secondEffect
  have combined := Word.appendAll_following_word capacity count (hexDigits 1 8) position original
  refine ⟨restoreLocals first written, ?_, ?_, firstEffect.trans closed⟩
  · simpa only [body, returned, encoding, combined, next] using run
  · rw [encoding, combined]
    exact secondBacking

theorem Checked.write (checked : Checked program byte digit word) (count capacity : Nat) (position : Int)
    (wellFormed : StateWellFormed before) (countFit : count ≤ 2147483647)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) })
    (argumentsResult : ArgumentsEvaluateTo program.core caller arguments
      [.signed .i32 count, .slice i32 outputCell [] 0 original.length, .signed .i32 capacity, .signed .i32 position] before) :
    ∃ after, Evaluates program.core caller (.call checked.source.function.id arguments)
        (.signed .i32 (appendAll capacity (encoding count) position original).position) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (appendAll capacity (encoding count) position original).contents)) } ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  let values : List Value := [.signed .i32 count, .slice i32 outputCell [] 0 original.length,
    .signed .i32 capacity, .signed .i32 position]
  let params := parameterBindings (fun index : Fin 4 => values.get index)
  have locals (index : Fin 4) : (enterCall before params).local? index.val = some (values.get index) :=
    enterCall_parameterBindings_matches wellFormed index
  have calleeBacking := ((enterCall_effect before params).oldCells outputCell
    (StateWellFormed.cell_lt_next_of_entry wellFormed backing) (by simp [CellSet.empty])).trans backing
  obtain ⟨completed, run, contents, effect⟩ := execute word count capacity position
    (enterCall_preserves_wellFormed wellFormed) countFit capacityBound capacityFit
    (locals ⟨0, by decide⟩) (locals ⟨1, by decide⟩) (locals ⟨2, by decide⟩) (locals ⟨3, by decide⟩) calleeBacking
  have called := checked.call wellFormed argumentsResult (bindings := params) rfl run effect
  exact ⟨restoreLocals before completed, called.1, contents, called.2⟩

end Lanius.Extraction.CompactOutput.PackHeader
