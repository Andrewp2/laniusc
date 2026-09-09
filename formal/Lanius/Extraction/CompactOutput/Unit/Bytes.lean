import Lanius.Extraction.CompactOutput.Unit.State
import Lanius.Extraction.CompactOutput.Bytes.Call

namespace Lanius.Extraction.CompactOutput.Unit

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

theorem Owned.bytes (owned : Owned memory position contents before)
    (bytes : Bytes.Checked program byte digit hex) (inputId lengthId : VarId)
    (values : List Nat) (capacity : Nat)
    (inputNotCursor : inputId ≠ 19) (lengthNotCursor : lengthId ≠ 19)
    (input : I32Prefix memory.base inputCell physicalCapacity (values.map Int.ofNat))
    (inputRead : memory.base.local? inputId = some (.slice i32 inputCell [] 0 physicalCapacity))
    (lengthRead : memory.base.local? lengthId = some (.signed .i32 values.length))
    (distinct : memory.outputCell ≠ inputCell) (lengthFit : values.length ≤ 2147483647)
    (byteBound : ∀ value ∈ values, value < 256)
    (outputRead : memory.base.local? 16 = some (.slice i32 memory.outputCell [] 0 memory.initialContents.length))
    (capacityRead : memory.base.local? 17 = some (.signed .i32 capacity))
    (room : capacity ≤ memory.initialContents.length) (capacityFit : capacity ≤ 2147483647) :
    ∃ after, Evaluates program.core before
        (.assign .set (.local 19) (.call bytes.source.function.id [read inputId, read lengthId, read 16, read 17, read 19])) .unit after ∧
      Owned memory (appendAll capacity (Bytes.encoding values) position contents).position
        (appendAll capacity (Bytes.encoding values) position contents).contents after ∧
      CellEffect memory.writes before after := by
  have output : before.local? 16 = some (.slice i32 memory.outputCell [] 0 contents.length) := by
    simpa only [owned.length] using owned.local (by decide) outputRead (by intro same; cases same)
  obtain ⟨written, run, backing, effect⟩ := bytes.write values capacity position owned.frame.wellFormed
    (owned.input input distinct) distinct lengthFit byteBound
    (by simpa only [owned.length] using room) capacityFit owned.backing
    (.cons (local_evaluates program.core (owned.local inputNotCursor inputRead (by intro same; cases same)))
      (.cons (local_evaluates program.core (owned.local lengthNotCursor lengthRead (by intro same; cases same)))
        (.cons (local_evaluates program.core output) (.cons
          (local_evaluates program.core (owned.local (by decide) capacityRead (by intro same; cases same)))
          (.cons (local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ owned.cursor)) (.nil _ _))))))
  exact owned.assign run effect backing (appendAll_length _ _ _ _)

end Lanius.Extraction.CompactOutput.Unit
