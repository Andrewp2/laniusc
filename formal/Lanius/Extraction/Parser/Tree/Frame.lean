import Lanius.Extraction.Parser.Tree.Loop
import Lanius.Extraction.Parser.Derivation.Scopes

namespace Lanius.Extraction.ParserTreeSource

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser Lanius.Extraction.ParserRecognize

/-- Immutable inputs needed to invoke the reader and recursive materializer.
    This is the ambient frame of the sibling loop, not another interpretation
    of the tree or a presumed successful component execution. -/
structure TreeRuntime.Frame (runtime : TreeRuntime) (layout : WorkspaceLayout)
    (workspace : LogicalWorkspace) (workspaceValues : List Int) (workspaceCell : CellId)
    (depth : Nat) (state : State) : Prop where
  wellFormed : StateWellFormed state
  artifact : RecognizerWorkspaceArtifact layout workspace workspaceValues workspaceCell state
  recordsSeparate : workspaceCell ≠ runtime.recordsCell
  offsetsSeparate : workspaceCell ≠ runtime.offsetsCell
  workspaceLocal : state.local? 0 = some (.slice (.scalar (.signed .i32)) workspaceCell [] 0 workspaceValues.length)
  workspaceLengthLocal : state.local? 1 = some (.signed .i32 (Int.ofNat workspaceValues.length))
  tokensLocal : state.local? 2 = some (.signed .i32 (Int.ofNat layout.tokenCount))
  statesLocal : state.local? 3 = some (.signed .i32 (Int.ofNat workspace.states.length))
  capacityLocal : state.local? 6 = some (.signed .i32 (Int.ofNat runtime.records.length))
  depthLocal : state.local? 11 = some (.signed .i32 (Int.ofNat depth))
  depthBound : depth ≤ 2147483647

theorem TreeRuntime.Frame.bind {runtime : TreeRuntime}
    (framed : runtime.Frame layout workspace workspaceValues workspaceCell depth before)
    (localId : Lanius.VarId) (fresh : 12 ≤ localId) (value : Value) :
    runtime.Frame layout workspace workspaceValues workspaceCell depth (before.bindLocal localId value) := by
  have preserve {id : Lanius.VarId} {v : Value} (small : id < 12) (found : before.local? id = some v) :
      (before.bindLocal localId value).local? id = some v :=
    (bindLocal_preserves_other_local framed.wellFormed (Ne.symm (Nat.ne_of_lt (Nat.lt_of_lt_of_le small fresh)))).trans found
  exact ⟨bindLocal_preserves_well_formed _ _ _ framed.wellFormed,
    framed.artifact.bind_local framed.wellFormed localId value, framed.recordsSeparate, framed.offsetsSeparate,
    preserve (by decide) framed.workspaceLocal, preserve (by decide) framed.workspaceLengthLocal,
    preserve (by decide) framed.tokensLocal, preserve (by decide) framed.statesLocal,
    preserve (by decide) framed.capacityLocal, preserve (by decide) framed.depthLocal, framed.depthBound⟩

/-- Cursor setup establishes the loop's ambient frame from the pre-loop
    caller frame. There is no assumed frame in an unrelated runtime state. -/
theorem TreeRuntime.Frame.initialize {runtime : TreeRuntime}
    (framed : runtime.Frame layout workspace workspaceValues workspaceCell depth before) :
    (runtime.freshCursors before).Frame layout workspace workspaceValues workspaceCell depth
      (runtime.initialState before) := by
  have initialized := ((framed.bind 13 (by decide)
    (.signed .i32 (Int.ofNat (runtime.wordBase + 4 + runtime.parent.dot * 3)))).bind 14 (by decide)
      (.signed .i32 (Int.ofNat runtime.nodeBase))).bind 15 (by decide) (.signed .i32 0)
  exact ⟨initialized.wellFormed, initialized.artifact, initialized.recordsSeparate, initialized.offsetsSeparate,
    initialized.workspaceLocal, initialized.workspaceLengthLocal, initialized.tokensLocal, initialized.statesLocal,
    initialized.capacityLocal, initialized.depthLocal, initialized.depthBound⟩

/-- The reader or a child call may modify only output arrays. All copied
    parameters and the logical/physical workspace connection survive. -/
theorem TreeRuntime.Frame.after_outputs {runtime : TreeRuntime}
    {recordsContents offsetsContents : List Value}
    (framed : runtime.Frame layout workspace workspaceValues workspaceCell depth before)
    (records : before.cellEntry? runtime.recordsCell = some {
      id := runtime.recordsCell, value := some (.array recordsContents) })
    (offsets : before.cellEntry? runtime.offsetsCell = some {
      id := runtime.offsetsCell, value := some (.array offsetsContents) })
    (effect : CellEffect runtime.outputs before after) :
    runtime.Frame layout workspace workspaceValues workspaceCell depth after := by
  have preserve {id : Lanius.VarId} {value : Value} (found : before.local? id = some value)
      (plain : ∀ values, value ≠ .array values) : after.local? id = some value := by
    apply effect.preserves_local framed.wellFormed found
    intro cell binding written
    exact written.elim (local_cell_ne_of_distinct_value found records (plain _) binding)
      (local_cell_ne_of_distinct_value found offsets (plain _) binding)
  refine ⟨effect.wellFormed, ?_, framed.recordsSeparate, framed.offsetsSeparate,
    preserve framed.workspaceLocal (by intro values impossible; cases impossible),
    preserve framed.workspaceLengthLocal (by intro values impossible; cases impossible),
    preserve framed.tokensLocal (by intro values impossible; cases impossible),
    preserve framed.statesLocal (by intro values impossible; cases impossible),
    preserve framed.capacityLocal (by intro values impossible; cases impossible),
    preserve framed.depthLocal (by intro values impossible; cases impossible), framed.depthBound⟩
  exact ⟨framed.artifact.workspaceLength, framed.artifact.workspaceEncoded,
    effect.preserves_entry framed.wellFormed framed.artifact.workspaceBacking
      (fun written => written.elim framed.recordsSeparate framed.offsetsSeparate)⟩

/-- Discharge the sibling loop's ambient-frame preservation obligation,
    including its private cursor writes and arbitrary recursive output writes. -/
theorem TreeRuntime.Frame.preserved {runtime : TreeRuntime}
    (framed : runtime.Frame layout workspace workspaceValues workspaceCell depth before)
    (held : runtime.At trees pending before) (effect : CellEffect runtime.writes before after) :
    runtime.Frame layout workspace workspaceValues workspaceCell depth after := by
  have wordsSeparate : workspaceCell ≠ runtime.wordsCell := Ne.symm
    (local_cell_ne_of_distinct_value (Assertion.localPointsTo_local _ _ _ _ held.wordsOwned)
      framed.artifact.workspaceBacking (by intro impossible; cases impossible) held.wordsOwned.1)
  have nodesSeparate : workspaceCell ≠ runtime.nodesCell := Ne.symm
    (local_cell_ne_of_distinct_value (Assertion.localPointsTo_local _ _ _ _ held.nodesOwned)
      framed.artifact.workspaceBacking (by intro impossible; cases impossible) held.nodesOwned.1)
  have cursorSeparate : workspaceCell ≠ runtime.cursorCell := Ne.symm
    (local_cell_ne_of_distinct_value (Assertion.localPointsTo_local _ _ _ _ held.cursorOwned)
      framed.artifact.workspaceBacking (by intro impossible; cases impossible) held.cursorOwned.1)
  refine ⟨effect.wellFormed, ?_, framed.recordsSeparate, framed.offsetsSeparate,
    held.preserves_fixed effect (by decide) framed.workspaceLocal (by intro values impossible; cases impossible),
    held.preserves_fixed effect (by decide) framed.workspaceLengthLocal (by intro values impossible; cases impossible),
    held.preserves_fixed effect (by decide) framed.tokensLocal (by intro values impossible; cases impossible),
    held.preserves_fixed effect (by decide) framed.statesLocal (by intro values impossible; cases impossible),
    held.preserves_fixed effect (by decide) framed.capacityLocal (by intro values impossible; cases impossible),
    held.preserves_fixed effect (by decide) framed.depthLocal (by intro values impossible; cases impossible), framed.depthBound⟩
  exact ⟨framed.artifact.workspaceLength, framed.artifact.workspaceEncoded,
    effect.preserves_entry framed.wellFormed framed.artifact.workspaceBacking (fun written =>
      written.elim framed.recordsSeparate (fun h => h.elim framed.offsetsSeparate
        (fun h => h.elim wordsSeparate (fun h => h.elim nodesSeparate cursorSeparate))))⟩

end Lanius.Extraction.ParserTreeSource
