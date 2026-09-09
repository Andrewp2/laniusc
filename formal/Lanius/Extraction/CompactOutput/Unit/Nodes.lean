import Lanius.Extraction.CompactOutput.Unit.State
import Lanius.Extraction.CompactOutput.Nodes.Call

namespace Lanius.Extraction.CompactOutput.Unit

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.SemanticTokens

theorem Owned.nodes (owned : Owned memory position contents before)
    (checked : Nodes.Checked program byte digit word tokenTag stateTag)
    (tokenConstant : ParserTreeSource.constantValue program.core tokenTag 1)
    (stateConstant : ParserTreeSource.constantValue program.core stateTag 2)
    (records : List RecordVisit) (words : List Int) (inputLength count capacity : Nat)
    (input : I32Prefix memory.base inputCell inputCapacity words)
    (offsets : I32Prefix memory.base offsetCell offsetCapacity (records.map (fun record => (record.offset : Int))))
    (inputRead : memory.base.local? 12 = some (.slice i32 inputCell [] 0 inputCapacity))
    (lengthRead : memory.base.local? 13 = some (.signed .i32 inputLength))
    (offsetRead : memory.base.local? 14 = some (.slice i32 offsetCell [] 0 offsetCapacity))
    (nodesRead : memory.base.local? 15 = some (.signed .i32 records.length))
    (countRead : memory.base.local? 9 = some (.signed .i32 count))
    (distinctInput : memory.outputCell ≠ inputCell) (distinctOffsets : memory.outputCell ≠ offsetCell)
    (inputRoom : words.length ≤ inputLength) (inputFit : inputLength ≤ 2147483647)
    (countFit : count ≤ 2147483647) (nodesFit : records.length ≤ 2147483647)
    (stored : ∀ record ∈ records, record.Stored 0 words)
    (fields : ∀ record ∈ records, record.production ≤ 2147483647 ∧ record.start ≤ 2147483647 ∧ record.finish ≤ 2147483647)
    (linked : ∀ (index : Nat) (record : RecordVisit), records[index]? = some record → ∀ child ∈ record.children, child.Linked 0 records index)
    (tokenBound : ∀ record ∈ records, ∀ child ∈ record.children, ∀ use, child = .token use → use.token < count)
    (outputRead : memory.base.local? 16 = some (.slice i32 memory.outputCell [] 0 memory.initialContents.length))
    (capacityRead : memory.base.local? 17 = some (.signed .i32 capacity))
    (room : capacity ≤ memory.initialContents.length) (capacityFit : capacity ≤ 2147483647) :
    ∃ after, Evaluates program.core before
        (.call checked.source.function.id [read 12, read 13, read 14, read 15, read 9, read 16, read 17, read 19])
        (.signed .i32 (appendAll capacity (Nodes.encodeAll records) position contents).position) after ∧
      after.cellEntry? memory.outputCell = some {
        id := memory.outputCell, value := some (.array (signedI32Values
          (appendAll capacity (Nodes.encodeAll records) position contents).contents)) } ∧
      CellEffect (CellSet.singleton memory.outputCell) before after := by
  have output : before.local? 16 = some (.slice i32 memory.outputCell [] 0 contents.length) := by
    simpa only [owned.length] using owned.local (by decide) outputRead (by intro same; cases same)
  exact checked.write tokenConstant stateConstant records words inputLength count capacity position owned.frame.wellFormed
    (owned.input input distinctInput) (owned.input offsets distinctOffsets) distinctInput distinctOffsets
    inputRoom inputFit countFit nodesFit stored fields linked tokenBound
    (by simpa only [owned.length] using room) capacityFit owned.backing
    (.cons (local_evaluates program.core (owned.local (by decide) inputRead (by intro same; cases same)))
      (.cons (local_evaluates program.core (owned.local (by decide) lengthRead (by intro same; cases same)))
        (.cons (local_evaluates program.core (owned.local (by decide) offsetRead (by intro same; cases same)))
          (.cons (local_evaluates program.core (owned.local (by decide) nodesRead (by intro same; cases same)))
            (.cons (local_evaluates program.core (owned.local (by decide) countRead (by intro same; cases same)))
              (.cons (local_evaluates program.core output) (.cons
                (local_evaluates program.core (owned.local (by decide) capacityRead (by intro same; cases same)))
                (.cons (local_evaluates program.core (Assertion.localPointsTo_local _ _ _ _ owned.cursor)) (.nil _ _)))))))))

end Lanius.Extraction.CompactOutput.Unit
