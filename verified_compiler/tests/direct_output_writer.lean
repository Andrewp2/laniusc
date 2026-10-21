import SelfOutputByte
import Lanius.Extraction.WriterCursor

namespace OutputWriterProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open OutputNaturalProof

/-- Uniform output effects for the actual byte/text helpers. Their existing
    execution proofs establish writes; callers only supply buffer/environment. -/
theorem byte (buffer : Buffer state) (value : Fin 256)
    (room : buffer.position + 1 ≤ buffer.capacity) (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state
      (OutputByteProof.byteCall (.rawSlice (.scalar (.signed .i32)) buffer.address buffer.words)
        buffer.capacity buffer.position value.val)
      (.signed .i32 (buffer.position + 1 : Nat)) after ∧
      WriterFrame state after (buffer.address + buffer.position) [UInt8.ofNat value.val] := by
  let input : OutputByteProof.ByteBuffer state := {
    address := buffer.address, words := buffer.words, capacity := buffer.capacity, cursor := buffer.position
    capacityFits := buffer.fits, available := by omega, storage := buffer.storage
    readable := buffer.readable.subrange (by have storage := buffer.storage; omega) }
  obtain ⟨after, run, written, cells, world, views⟩ := OutputByteProof.actualCall_writes input value
    environment.formed environment.noViews environment.unique
  exact ⟨after, run, ⟨.write ((BytesWrite.refl environment.unique).snoc written), cells, world, views⟩⟩

theorem text (buffer : Buffer state) (value : String)
    (room : buffer.position + (World.utf8Bytes value).length ≤ buffer.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state
      (OutputTextProof.textCall (.rawSlice (.scalar (.signed .i32)) buffer.address buffer.words)
        buffer.capacity buffer.position value (World.utf8Bytes value).length)
      (.signed .i32 (buffer.position + (World.utf8Bytes value).length : Nat)) after ∧
      WriterFrame state after (buffer.address + buffer.position) (World.utf8Bytes value) := by
  let input : OutputTextProof.TextBuffer state value := {
    address := buffer.address, words := buffer.words, capacity := buffer.capacity, position := buffer.position
    capacityFits := buffer.fits, space := room, storage := buffer.storage, readable := buffer.readable }
  obtain ⟨after, run, written, cells, world, views⟩ := OutputTextProof.actualCall_copies input
    environment.formed environment.noViews environment.below environment.unique
  exact ⟨after, run, ⟨.borrow _ environment.below written, cells, world, views⟩⟩

/-- Output effects retain the writable buffer and advance its position. -/
def _root_.OutputNaturalProof.Buffer.afterWriter (buffer : Buffer base)
    (frame : WriterFrame base current (buffer.address + buffer.position) front) : Buffer current := {
  buffer with
  position := buffer.position + front.length
  readable := frame.output.readable buffer.readable }

/-- Cursor-relative calls normalize address and result arithmetic once, while
    retaining the actual primitive's execution and exact output effect. -/
theorem byteAt (buffer : Buffer base)
    (frame : WriterFrame base current (buffer.address + buffer.position) front) (value : Fin 256)
    (room : buffer.position + (front ++ [UInt8.ofNat value.val]).length ≤ buffer.capacity)
    (environment : WriterEnvironment base) :
    ∃ after, RunsExpr extractedProgram current
      (OutputByteProof.byteCall (.rawSlice (.scalar (.signed .i32)) buffer.address buffer.words)
        buffer.capacity (buffer.position + front.length : Nat) value.val)
      (.signed .i32 (buffer.position + (front ++ [UInt8.ofNat value.val]).length : Nat)) after ∧
      WriterFrame current after ((buffer.address + buffer.position) + front.length) [UInt8.ofNat value.val] := by
  simpa only [Buffer.afterWriter, List.length_append, List.length_cons, List.length_nil, Nat.add_assoc] using
    byte (buffer.afterWriter frame) value
      (by simpa only [Buffer.afterWriter, List.length_append, List.length_cons, List.length_nil, Nat.add_assoc] using room)
      (environment.afterWrite frame)

theorem textAt (buffer : Buffer base)
    (frame : WriterFrame base current (buffer.address + buffer.position) front) (value : String)
    (length : Nat) (lengthIs : (World.utf8Bytes value).length = length)
    (room : buffer.position + (front ++ World.utf8Bytes value).length ≤ buffer.capacity)
    (environment : WriterEnvironment base) :
    ∃ after, RunsExpr extractedProgram current
      (OutputTextProof.textCall (.rawSlice (.scalar (.signed .i32)) buffer.address buffer.words)
        buffer.capacity (buffer.position + front.length : Nat) value length)
      (.signed .i32 (buffer.position + (front ++ World.utf8Bytes value).length : Nat)) after ∧
      WriterFrame current after ((buffer.address + buffer.position) + front.length) (World.utf8Bytes value) := by
  simpa only [Buffer.afterWriter, List.length_append, Nat.add_assoc, lengthIs] using
    text (buffer.afterWriter frame) value
      (by simpa only [Buffer.afterWriter, List.length_append, Nat.add_assoc] using room)
      (environment.afterWrite frame)

#print axioms byte
#print axioms text
#print axioms byteAt
#print axioms textAt

end OutputWriterProof
