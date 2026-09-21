import Lanius.X86.Machine.Scalar

namespace Lanius.X86.Machine

/- A chunk keeps the compiler/emitter payload abstract while making its exact
   machine bytes available to layout and execution proofs. -/
structure Chunk (α : Type) where
  payload : α
  bytes : List UInt8

def blockBytes : List (Chunk α) → List UInt8
  | [] => []
  | chunk :: tail => chunk.bytes ++ blockBytes tail

/- `ChunksAt memory address chunks` is the byte-level layout invariant: each
   chunk starts immediately after the preceding chunk's bytes. -/
def ChunksAt (memory : Memory) (address : Address) : List (Chunk α) → Prop
  | [] => True
  | chunk :: tail =>
      CodeAt memory address chunk.bytes ∧
        ChunksAt memory (address + BitVec.ofNat 64 chunk.bytes.length) tail

theorem chunksAt_of_codeAt {memory : Memory} {address : Address}
    {chunks : List (Chunk α)}
    (loaded : CodeAt memory address (blockBytes chunks)) :
    ChunksAt memory address chunks := by
  induction chunks generalizing address with
  | nil => simp [ChunksAt]
  | cons chunk tail ih =>
      simp only [blockBytes] at loaded
      exact ⟨loaded.prefix, ih loaded.suffix⟩

structure ChunkStep (α : Type) (chunk : Chunk α)
    (before after : State) where
  loaded : CodeAt before.memory before.rip chunk.bytes
  step : Step before after

def ChunkSteps (chunks : List (Chunk α)) (before after : State) : Prop :=
  match chunks with
  | [] => before = after
  | chunk :: tail =>
      ∃ middle, ChunkStep α chunk before middle ∧ ChunkSteps tail middle after

theorem chunkSteps_toSteps {chunks : List (Chunk α)}
    {before after : State} (proof : ChunkSteps chunks before after) :
    Steps chunks.length before after := by
  induction chunks generalizing before after with
  | nil =>
      simp only [ChunkSteps] at proof
      subst after
      exact Steps.refl _
  | cons chunk tail ih =>
      simp only [ChunkSteps] at proof
      obtain ⟨middle, head, rest⟩ := proof
      simpa using Steps.cons head.step (ih rest)

end Lanius.X86.Machine
