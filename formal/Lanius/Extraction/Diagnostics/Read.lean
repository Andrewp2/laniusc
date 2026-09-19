import Lanius.Extraction.Diagnostics.Natural

namespace Lanius.Extraction.Diagnostics.Read
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.CompactOutput

def statement (writer : FunctionId) (argument count : VarId) : Stmt :=
  .sequence (.expression (.call writer [read argument]))
    (.sequence (.ifThenElse (binary .lessEqual (read count) negativeOne)
      (.sequence (.expression (.call writer [binary .subtract (number 0) (read count)])) .skip)
      (.sequence (.expression (.call writer [number 0])) .skip)) (returned (number 6)))

structure Checked (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (argument count : VarId) (source : Stmt) where
  writer : Natural.Checked program
  exactSource : source = statement writer.source.source.function.id argument count

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (argument count : VarId) (source : Stmt) : Option (Checked program argument count source) := do
  let writer ← Natural.check? program
  let same ← Equality.statement? source (statement writer.source.source.function.id argument count)
  pure ⟨writer, same.equal⟩

/-- Execute both real diagnostic calls on the reader's oversized-input
result. Their existing formatter proof preserves all non-stderr state. -/
theorem Checked.oversized (checked : Checked program argument count source)
    (initial : Allocation.Registry before) (representable : Host.RepresentableViews before)
    (argumentRead : before.local? argument = some (.signed .i32 index)) (bounded : index ≤ 2147483647)
    (countRead : before.local? count = some (.signed .i32 (-2))) :
    ∃ after, Executes program.core before source (.returned (some (.signed .i32 6))) after ∧
      Allocation.Registry after ∧ Host.RepresentableViews after ∧ Host.Effect CellSet.empty before after ∧
      Host.StderrOnly before.world after.world := by
  obtain ⟨_, middle, first, registered, values, effect, firstWorld⟩ := checked.writer.write index bounded initial representable
    (.cons (local_evaluates program.core argumentRead) (.nil _ _))
  have countAt := effect.preservesLocal initial.wellFormed countRead (by simp [CellSet.empty])
  have guard : Evaluates program.core middle (binary .lessEqual (read count) negativeOne) (.boolean true) middle := by
    apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program.core countAt)
      (negativeOne_evaluates program.core middle)
    simp [evalBinaryValue, evalSignedBinary]
  have detail : Evaluates program.core middle (binary .subtract (number 0) (read count)) (.signed .i32 2) middle := by
    apply evaluatesEagerBinary (by decide) (by decide) evaluatesValue (local_evaluates program.core countAt)
    rfl
  obtain ⟨_, after, second, finalRegistry, finalValues, finalEffect, secondWorld⟩ := checked.writer.write 2 (by decide)
    registered values (.cons detail (.nil _ _))
  have run : Executes program.core before (statement checked.writer.source.source.function.id argument count)
      (.returned (some (.signed .i32 6))) after :=
    executesSequence (executesExpression first)
      (executesSequence (executesIfTrue guard (executesSequence (executesExpression second) (executesSkip _ _)))
        (executesSequenceReturned (executesReturnValue evaluatesValue)))
  exact ⟨after, checked.exactSource.symm ▸ run, finalRegistry, finalValues, effect.trans finalEffect, firstWorld.trans secondWorld⟩

end Lanius.Extraction.Diagnostics.Read
