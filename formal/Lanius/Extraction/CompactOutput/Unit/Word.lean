import Lanius.Extraction.CompactOutput.Unit.State
import Lanius.Extraction.CompactOutput.Word.Call

namespace Lanius.Extraction.CompactOutput.Unit

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

theorem Owned.word (owned : Owned memory position contents before)
    (word : Word.Checked program byte digit) (valueId : VarId) (capacity value : Nat)
    (notCursor : valueId ≠ 19)
    (valueRead : memory.base.local? valueId = some (.signed .i32 value))
    (outputRead : memory.base.local? 16 = some (.slice i32 memory.outputCell [] 0 memory.initialContents.length))
    (capacityRead : memory.base.local? 17 = some (.signed .i32 capacity))
    (room : capacity ≤ memory.initialContents.length) (capacityFit : capacity ≤ 2147483647)
    (valueFit : value ≤ 2147483647) :
    ∃ after, Evaluates program.core before
        (.assign .set (.local 19) (.call word.source.function.id [read 16, read 17, read 19, read valueId])) .unit after ∧
      Owned memory (appendAll capacity (hexDigits value 8) position contents).position
        (appendAll capacity (hexDigits value 8) position contents).contents after ∧
      CellEffect memory.writes before after := by
  have output : before.local? 16 = some (.slice i32 memory.outputCell [] 0 contents.length) := by
    simpa only [owned.length] using owned.local (by decide) outputRead (by intro same; cases same)
  obtain ⟨written, run, backing, effect⟩ := word.write position capacity value owned.frame.wellFormed
    (by simpa only [owned.length] using room) capacityFit valueFit owned.backing
    (.cons (local_evaluates program.core output) (.cons
      (local_evaluates program.core (owned.local (by decide) capacityRead (by intro same; cases same)))
      (.cons (local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ owned.cursor)) (.cons
        (local_evaluates program.core (owned.local notCursor valueRead (by intro same; cases same))) (.nil _ _)))))
  exact owned.assign run effect backing (appendAll_length _ _ _ _)

end Lanius.Extraction.CompactOutput.Unit
