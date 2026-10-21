import verified_compiler.tests.direct_byte_io_read_interface

namespace ProofInterfaceReaderDomain

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics ByteIoReadInterface

-- Same allocated-storage construction as the existing reader domain fixture,
-- instantiated directly at the new public Input and File.call boundary.
private def output : Heap := {
  blocks := [{ base := 16, size := 16, alignment := 4, bytes := (List.replicate 4 (i32Bytes 11)).flatten, owned := false }]
  nextAddress := 32 }
private def file : World.FileEntry := { path := [1], bytes := [0, 255] }
private def handle : World.FileHandle := { id := 3, path := [1], readable := true }
private def before : State := ({
  heap := output.allocatedI32 16384 none
  world := { files := [file], fileHandles := [handle] } } : State).bindLocal 9 (.signed .i32 777)

private theorem below : HeapBlocksBelowNext output := by
  intro block member
  simp only [output, List.mem_cons, List.not_mem_nil, or_false] at member
  subst block
  decide

private theorem unique : HeapBlockBasesUnique output := by
  intro first firstMember second secondMember _
  simp only [output, List.mem_cons, List.not_mem_nil, or_false] at firstMember secondMember
  exact firstMember.trans secondMember.symm

private def input : Function.Input before := {
  address := 32, words := 16384, destination := 16, capacity := 4, handle := 3
  formed := by simp [before, State.CellsWellFormed, State.bindLocal, State.bindCell]
  capacityFits := by decide, scratchSize := by decide, separate := by decide
  inputRoom := Heap.allocatedI32_readable (words := 16384) (budget := none) below
  outputRoom := Heap.allocatedI32_oldReadable (heap := output) (words := 16384) (budget := none)
    (Heap.Readable.of_loadBytes
      (show output.loadBytes 16 16 = .ok (List.replicate 4 (i32Bytes 11)).flatten from rfl))
  unique := Heap.allocatedI32_unique (words := 16384) (budget := none) below unique
  noViews := rfl }

theorem inhabitedInput : Nonempty (Function.Input before) := ⟨input⟩

theorem inhabitedCursor : World.FileCursor before.world input.handle file handle := ⟨rfl, rfl, rfl⟩

theorem actualFileContract : ∃ after,
    RunsExpr extractedProgram before (.call reader.id (input.values.map Expr.value)) (.signed .i32 2) after ∧
    after.heap.loadBytes 16 8 = .ok ([0, 255].flatMap ByteIoReadProof.Loop.encodeByte) ∧
    after.heap.loadByte 16 8 = .ok 11 ∧ after.locals = before.locals := by
  obtain ⟨value, after, run, _, final, locals, _⟩ := File.call input (by decide) inhabitedCursor (by decide)
  have returned : value = .signed .i32 2 := Option.some.inj (Completion.returned.inj final.1)
  subst value
  exact ⟨after, run, final.loaded (by decide),
    (final.tail (index := 8) (by decide) (by decide)).trans (by rfl), locals⟩

#print axioms inhabitedInput
#print axioms inhabitedCursor
#print axioms actualFileContract

end ProofInterfaceReaderDomain
