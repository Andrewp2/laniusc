import Lanius.Extraction.Entry.Files.Request
import Lanius.Extraction.Entry.Files.Advance

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

def condition (argument count : VarId) : Expr :=
  .binary .notEqual (.local argument) (.local count)

theorem condition_evaluates (program : Program) (index limit : Nat)
    (indexRead : before.local? argument = some (.signed .i32 index))
    (countRead : before.local? count = some (.signed .i32 limit)) :
    Evaluates program before (condition argument count) (.boolean (decide (index ≠ limit))) before := by
  apply evaluatesEagerBinary (by decide) (by decide)
    (CompactOutput.local_evaluates program indexRead) (CompactOutput.local_evaluates program countRead)
  simp [evalBinaryValue, scalarEqual]
  apply Bool.eq_iff_iff.mpr
  simp
  omega

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {checked : File.Checked program} {before after : State}

/-- The immutable argc survives one file body. Its non-aliasing with the
argument cursor follows from their distinct current values; only separation
from the independently allocated output cursor remains an entry fact. -/
theorem count_after (resources : File.Resources checked.pipeline checked.syntaxStage checked.collectStage
      checked.emitStage checked.argument before)
    (frame : File.Handoff resources.input resources.data checked.syntaxStage checked.resultsStage
      checked.argument checked.emitStage.position after)
    (sameLocals : after.locals = before.locals)
    (carried : File.Carried checked.pipeline checked.syntaxStage checked.resultsStage countId)
    (countRead : before.local? countId = some (.signed .i32 limit))
    (remaining : (resources.input.index : Int) < limit)
    (apart : before.cellId? countId ≠ before.cellId? checked.emitStage.position) :
    after.local? countId = some (.signed .i32 limit) := by
  have restored : restoreLocals before after = after := by
    unfold restoreLocals
    rw [← sameLocals]
  rw [← restored]
  apply frame.locals countId _ carried countRead (by intro elements same; cases same) ?_ apart
  intro same
  have equal : before.local? countId = before.local? checked.argument := by simp only [State.local?, same]
  have indexRead := checked.advanceRelation.selected.symm ▸ resources.input.indexRead
  have numbers := countRead.symm.trans (equal.trans indexRead)
  simp only [Option.some.injEq, Value.signed.injEq, true_and] at numbers
  omega

/-- Final ordered evidence in the physical output buffer. It remains useful
after the last file without inventing a nonexistent next loading invocation. -/
def Finished (count : Nat) (sources : List SourceFile) (outputRoot : CellId)
    (positionId : VarId) (after : State) : Prop :=
  ∃ units : List CompactDecode.UnitData, ∃ position : Int, ∃ contents : List Int,
    History count units sources position contents ∧ units.length = count ∧ contents.length = 16777216 ∧
    after.cellEntry? outputRoot = some { id := outputRoot, value := some (.array (signedI32Values contents)) } ∧
    after.local? positionId = some (.signed .i32 position)

end Lanius.Extraction.Entry.Files
