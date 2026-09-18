import Lanius.Extraction.CompactOutput.Text.Source
import Lanius.Extraction.CompactOutput.Byte

namespace Lanius.Extraction.CompactOutput.Text

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

/-- The text helper reads the original string's encoded byte, including all
four lanes and signed packed words. No second string decoder is assumed. -/
theorem readValue (program : Program) (before : State)
    (values : List Int) (storage : List UInt8) (index : Nat) (value : UInt8)
    (bounded : index ≤ 2147483647)
    (inputRead : before.local? 5 = some (.slice i32 inputCell [] 0 values.length))
    (indexRead : before.local? 7 = some (.signed .i32 index))
    (contents : before.cellEntry? inputCell = some {
      id := inputCell, value := some (.array (signedI32Values values)) })
    (encoded : encodeI32Array (signedI32Values values) = .ok storage)
    (selected : storage[index]? = some value) :
    Evaluates program before valueExpression (.signed .i32 value.toNat) before :=
  Input.evaluates_encoded_byte program before (read 5) (read 7) inputCell values storage index value
    bounded (local_evaluates program inputRead) (local_evaluates program indexRead)
    contents encoded selected

/-- The actual helper call appends the selected byte and changes only the
output backing cell. Scope/cursor updates are handled by the enclosing loop. -/
theorem appendValue (byte : CheckedByte program) (position capacity : Nat) (value : UInt8)
    (wellFormed : StateWellFormed before) (room : position < capacity)
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (outputRead : before.local? 0 = some (.slice i32 outputCell [] 0 original.length))
    (capacityRead : before.local? 1 = some (.signed .i32 capacity))
    (positionRead : before.local? 6 = some (.signed .i32 position))
    (valueRead : before.local? 8 = some (.signed .i32 value.toNat))
    (contents : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) }) :
    ∃ after, Evaluates program.core before (writeCall byte.source.function.id)
        (.signed .i32 (position + 1 : Nat)) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values (original.set position value.toNat))) } ∧
      CellEffect (CellSet.singleton outputCell) before after ∧ HeapFrame before after := by
  exact (byte.append position capacity value.toNat room capacityBound capacityFit value.toNat_lt).call
    wellFormed (.cons (local_evaluates program.core outputRead)
      (.cons (local_evaluates program.core capacityRead)
        (.cons (local_evaluates program.core positionRead)
          (.cons (local_evaluates program.core valueRead) (.nil _ _))))) contents

end Lanius.Extraction.CompactOutput.Text
