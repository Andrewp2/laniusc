import Lanius.Extraction.Entry.Files.History

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

variable {program : CoreSynthesis.Program.CheckedProgram artifacts}
variable {pipeline : File.Load.Pipeline program} {before after : State}
variable {input : File.Load.Input pipeline before} {output : File.SavedBuffer input}

/-- Read the complete appended history directly from the emitted interval.
Unlike next-iteration reconstruction, this also applies to the last file,
where there is no next requested path to load. -/
theorem History.emitted {count : Nat} {units : List CompactDecode.UnitData} {sources : List SourceFile}
    {position : Int} {cursor : VarId}
    (history : History count units sources position output.contents)
    (remaining : units.length < count) (capacity : output.contents.length = 16777216)
    (emitted : File.Emitted input output position cursor after)
    (sameLocals : after.locals = before.locals) :
    ∃ unit : CompactDecode.UnitData, ∃ nextPosition : Int, ∃ nextContents : List Int,
      History count (units ++ [unit])
        (sources ++ [{ path := input.path, bytes := input.file.bytes.map UInt8.toNat }]) nextPosition nextContents ∧
      nextContents.length = 16777216 ∧
      after.cellEntry? output.view.root = some { id := output.view.root, value := some (.array (signedI32Values nextContents)) } ∧
      after.local? cursor = some (.signed .i32 nextPosition) := by
  obtain ⟨unit, encodable, nonempty, accepted, source, _, room, stored, read⟩ := emitted
  have offset : position.toNat = (bytes count units).length := by
    rw [history.cursor, Int.toNat_natCast]
  have restored : restoreLocals before after = after := by
    unfold restoreLocals
    rw [← sameLocals]
  rw [offset] at stored room
  rw [restored, offset] at read
  refine ⟨unit, _, _, history.append unit _ encodable nonempty accepted source remaining, ?_, stored, read⟩
  simp only [List.length_append, List.length_take, List.length_map, List.length_drop, capacity]
  omega

/-- Transport the history through the actual successful file-step result.
The next iteration may recover its buffer contents and cursor independently;
their shared physical cell values prove they are exactly the emitted ones. -/
theorem History.afterFile {count : Nat} {units : List CompactDecode.UnitData} {sources : List SourceFile}
    {position nextPosition : Int} {cursor : VarId} {nextContents : List Int}
    (history : History count units sources position output.contents)
    (remaining : units.length < count)
    (emitted : File.Emitted input output position cursor after)
    (sameLocals : after.locals = before.locals)
    (nextRead : after.local? cursor = some (.signed .i32 nextPosition))
    (nextStored : after.cellEntry? output.view.root = some {
      id := output.view.root, value := some (.array (signedI32Values nextContents)) }) :
    ∃ unit : CompactDecode.UnitData,
      History count (units ++ [unit])
        (sources ++ [{ path := input.path, bytes := input.file.bytes.map UInt8.toNat }]) nextPosition nextContents := by
  obtain ⟨unit, encodable, nonempty, accepted, source, _, _, stored, read⟩ := emitted
  have offset : position.toNat = (bytes count units).length := by
    rw [history.cursor, Int.toNat_natCast]
  have restored : restoreLocals before after = after := by
    unfold restoreLocals
    rw [← sameLocals]
  rw [restored, offset] at read
  have cursorEqual : nextPosition = ((bytes count units).length + unit.encoding.length : Nat) := by
    simpa only [Option.some.injEq, Value.signed.injEq, true_and] using nextRead.symm.trans read
  have cells := congrArg Cell.value (Option.some.inj (nextStored.symm.trans stored))
  have encoded := Value.array.inj (Option.some.inj cells)
  have contentsEqual := signedI32Values_injective encoded
  rw [offset] at contentsEqual
  refine ⟨unit, ?_⟩
  rw [cursorEqual, contentsEqual]
  exact history.append unit _ encodable nonempty accepted source remaining

end Lanius.Extraction.Entry.Files
