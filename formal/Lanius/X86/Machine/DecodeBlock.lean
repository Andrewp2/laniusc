import Lanius.X86.Machine.Block

namespace Lanius.X86.Machine

/-! A block certificate authenticates only instruction boundaries and bytes.
    It deliberately says nothing about execution or Core meaning. -/

structure CheckedBlock (bytes : List UInt8) where
  chunks : List (Chunk Instruction)
  bytes_exact : blockBytes chunks = bytes
  decoded : ∀ chunk ∈ chunks,
    decode chunk.bytes = some (chunk.payload, chunk.bytes.length)

def decodeBlockAux : Nat → List UInt8 → Option (List (Chunk Instruction))
  | _, [] => some []
  | 0, _ :: _ => none
  | fuel + 1, bytes =>
      match decode bytes with
      | none => none
      | some (instruction, size) =>
          if valid : 0 < size ∧ size ≤ bytes.length then
            let chunkBytes := bytes.take size
            if decodedChunk : decode chunkBytes = some (instruction, size) then
              match decodeBlockAux fuel (bytes.drop size) with
              | none => none
              | some tail => some ({ payload := instruction, bytes := chunkBytes } :: tail)
            else none
          else none

def decodeBlock (bytes : List UInt8) : Option (List (Chunk Instruction)) :=
  decodeBlockAux bytes.length bytes

theorem decodeBlockAux_sound {fuel : Nat} {bytes : List UInt8}
    {chunks : List (Chunk Instruction)}
    (run : decodeBlockAux fuel bytes = some chunks) :
    blockBytes chunks = bytes ∧
      ∀ chunk ∈ chunks,
        decode chunk.bytes = some (chunk.payload, chunk.bytes.length) := by
  induction fuel generalizing bytes chunks with
  | zero =>
      cases bytes with
      | nil => simp [decodeBlockAux] at run; subst chunks; simp [blockBytes]
      | cons byte bytes => simp [decodeBlockAux] at run
  | succ fuel ih =>
      cases bytes with
      | nil => simp [decodeBlockAux] at run; subst chunks; simp [blockBytes]
      | cons byte bytes =>
          simp only [decodeBlockAux] at run
          split at run <;> try contradiction
          next instruction size decoded =>
            split at run <;> try contradiction
            next valid =>
              split at run <;> try contradiction
              next decodedChunk =>
                split at run <;> try contradiction
                next tail tailRun =>
                  have tailSound := ih tailRun
                  rcases tailSound with ⟨tailBytes, tailDecoded⟩
                  simp only [Option.some.injEq] at run
                  subst chunks
                  have sizeLen : (List.take size (byte :: bytes)).length = size :=
                    List.length_take_of_le valid.2
                  have joined : List.take size (byte :: bytes) ++
                      List.drop size (byte :: bytes) = byte :: bytes :=
                    List.take_append_drop size (byte :: bytes)
                  constructor
                  · simp only [blockBytes, List.cons_append]
                    rw [tailBytes, joined]
                  · intro chunk member
                    simp only [List.mem_cons] at member
                    rcases member with rfl | member
                    · simpa [sizeLen] using decodedChunk
                    · exact tailDecoded chunk member

theorem decodeBlock_sound {bytes : List UInt8} {chunks : List (Chunk Instruction)}
    (run : decodeBlock bytes = some chunks) :
    blockBytes chunks = bytes ∧
      ∀ chunk ∈ chunks,
        decode chunk.bytes = some (chunk.payload, chunk.bytes.length) := by
  exact decodeBlockAux_sound run

def checkBlock (bytes : List UInt8) : Option (CheckedBlock bytes) :=
  match run : decodeBlock bytes with
  | none => none
  | some chunks =>
      let sound := decodeBlock_sound run
      some ⟨chunks, sound.1, sound.2⟩

theorem checkBlock_sound {bytes : List UInt8} {checked : CheckedBlock bytes}
    (_run : checkBlock bytes = some checked) :
    blockBytes checked.chunks = bytes := checked.bytes_exact

end Lanius.X86.Machine
