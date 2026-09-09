import Lanius.Extraction.CompactOutput.Bytes.Source
import Lanius.Extraction.CompactOutput.HexByte
import Lanius.Separation.I32Prefix

namespace Lanius.Extraction.CompactOutput.Bytes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts

/-- Derive the actual indexed input read and helper call. The input allocation
may have arbitrary spare contents beyond the logical byte sequence. -/
theorem read_write (hex : CheckedHexByte program byte digit)
    (values : List Nat) (index capacity : Nat) (position : Int)
    (wellFormed : StateWellFormed before)
    (input : I32PrefixLocal before 0 inputCell (values.map Int.ofNat))
    (indexBound : index < values.length)
    (byteBound : values[index] < 256)
    (indexRead : before.local? 6 = some (.signed .i32 index))
    (outputRead : before.local? 2 = some (.slice i32 outputCell [] 0 original.length))
    (capacityRead : before.local? 3 = some (.signed .i32 capacity))
    (positionRead : before.local? 5 = some (.signed .i32 position))
    (capacityBound : capacity ≤ original.length) (capacityFit : capacity ≤ 2147483647)
    (backing : before.cellEntry? outputCell = some {
      id := outputCell, value := some (.array (signedI32Values original)) }) :
    ∃ after, Evaluates program.core before (writeCall hex.source.function.id)
        (.signed .i32 (hexBytePosition capacity position)) after ∧
      after.cellEntry? outputCell = some {
        id := outputCell, value := some (.array (signedI32Values
          (hexByteOutput original capacity position values[index]))) } ∧
      CellEffect (CellSet.singleton outputCell) before after := by
  have selected := input.read program.core (read 6) index
    (by simpa only [List.length_map] using indexBound)
    (local_evaluates program.core indexRead)
  have valueRead : Evaluates program.core before (.index (read 0) (read 6))
      (.signed .i32 (values[index] : Nat)) before := by
    simpa only [List.get_eq_getElem, List.getElem_map, Int.ofNat_eq_natCast, read] using selected
  exact hex.write position capacity values[index] byteBound wellFormed capacityBound capacityFit backing
    (.cons (local_evaluates program.core outputRead)
      (.cons (local_evaluates program.core capacityRead)
        (.cons (local_evaluates program.core positionRead) (.cons valueRead (.nil _ _)))))

end Lanius.Extraction.CompactOutput.Bytes
