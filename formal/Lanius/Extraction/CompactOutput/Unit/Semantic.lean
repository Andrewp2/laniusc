import Lanius.Extraction.CompactOutput.Unit.State
import Lanius.Extraction.CompactOutput.Assignments.Call

namespace Lanius.Extraction.CompactOutput.Unit

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.SemanticTokens

theorem Owned.semantic (owned : Owned memory position contents before)
    (checked : Assignments.Checked program byte digit word)
    (assignments : List Assignment) (inputLength capacity : Nat)
    (input : I32Prefix memory.base inputCell physicalCapacity (assignments.flatMap Assignment.words))
    (inputRead : memory.base.local? 10 = some (.slice i32 inputCell [] 0 physicalCapacity))
    (lengthRead : memory.base.local? 11 = some (.signed .i32 inputLength))
    (countRead : memory.base.local? 9 = some (.signed .i32 assignments.length))
    (distinct : memory.outputCell ≠ inputCell)
    (inputRoom : 2 * assignments.length ≤ inputLength) (lengthFit : inputLength ≤ 2147483647)
    (fields : ∀ assignment ∈ assignments, assignment.first ≤ 2147483647 ∧
      -1 ≤ Assignments.secondWord assignment ∧ Assignments.secondWord assignment < 2147483647)
    (outputRead : memory.base.local? 16 = some (.slice i32 memory.outputCell [] 0 memory.initialContents.length))
    (capacityRead : memory.base.local? 17 = some (.signed .i32 capacity))
    (room : capacity ≤ memory.initialContents.length) (capacityFit : capacity ≤ 2147483647) :
    ∃ after, Evaluates program.core before
        (.assign .set (.local 19) (.call checked.source.function.id [read 10, read 11, read 9, read 16, read 17, read 19])) .unit after ∧
      Owned memory (appendAll capacity (Assignments.encodeAll assignments) position contents).position
        (appendAll capacity (Assignments.encodeAll assignments) position contents).contents after ∧
      CellEffect memory.writes before after := by
  have output : before.local? 16 = some (.slice i32 memory.outputCell [] 0 contents.length) := by
    simpa only [owned.length] using owned.local (by decide) outputRead (by intro same; cases same)
  obtain ⟨written, run, backing, effect⟩ := checked.write assignments inputLength capacity position owned.frame.wellFormed
    (owned.input input distinct) distinct inputRoom lengthFit fields
    (by simpa only [owned.length] using room) capacityFit owned.backing
    (.cons (local_evaluates program.core (owned.local (by decide) inputRead (by intro same; cases same)))
      (.cons (local_evaluates program.core (owned.local (by decide) lengthRead (by intro same; cases same)))
        (.cons (local_evaluates program.core (owned.local (by decide) countRead (by intro same; cases same)))
          (.cons (local_evaluates program.core output) (.cons
            (local_evaluates program.core (owned.local (by decide) capacityRead (by intro same; cases same)))
            (.cons (local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ owned.cursor)) (.nil _ _)))))))
  exact owned.assign run effect backing (appendAll_length _ _ _ _)

end Lanius.Extraction.CompactOutput.Unit
