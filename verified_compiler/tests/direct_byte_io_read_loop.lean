import verified_compiler.tests.direct_byte_io_read
import Lanius.Extraction.OutputLoop

namespace ByteIoReadProof.Loop

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics Lanius.Extraction

private def reader := Extracted.«verified::byte_io».Functions.«read_file».core
private def loop := reader.whileLoop 1
def encodeByte (byte : UInt8) : List UInt8 := i32Bytes byte.toNat

theorem encode_length (bytes : List UInt8) : (bytes.flatMap encodeByte).length = bytes.length * 4 := by
  simp [List.length_flatMap, encodeByte, i32Bytes, List.map_const', List.sum_replicate_nat]

/-- Buffer/cursor facts shared by the read and copy boundaries. Separation
    retains input bytes; it is not a language-wide ownership restriction. -/
structure Buffers (state : State) where
  address : Nat
  words : Nat
  destination : Nat
  capacity : Nat
  total : Nat
  inputRoom : state.heap.Readable address (words * 4)
  outputRoom : state.heap.Readable destination (capacity * 4)
  separate : destination + capacity * 4 ≤ address ∨ address + words * 4 ≤ destination
  formed : state.CellsWellFormed
  unique : HeapBlockBasesUnique state.heap
  noViews : state.i32ArrayViews = []
  packed : state.local? (reader.argumentId 3) = some (.rawSlice (.scalar (.signed .i32)) address words)
  output : state.local? (reader.argumentId 1) = some (.rawSlice (.scalar (.signed .i32)) destination capacity)
  cursor : state.local? (reader.bindingId 1) = some (.signed .i32 total)

/-- A loaded chunk and actual count binding extend the same buffer facts;
    successful execution is not part of the input domain. -/
structure Input (state : State) extends Buffers state where
  bytes : List UInt8
  fits : total + bytes.length < 2 ^ 31
  inputSize : bytes.length ≤ words * 4
  outputSize : total + bytes.length ≤ capacity
  loaded : state.heap.loadBytes address bytes.length = .ok bytes
  count : state.local? (reader.bindingId 5) = some (.signed .i32 bytes.length)

def Invariant (input : Input before) (after : State) (index : Nat) : Prop :=
  OutputState before after (reader.bindingId 6) index input.destination (input.total * 4)
    input.capacity input.bytes encodeByte

/-- Total correctness of the actual inner loop: every input byte is expanded
    to its native i32 word, the counter reaches the count, and the rest of memory
    and caller cells are framed. Outer reads, guards and scope are separate. -/
theorem run (input : Input before) : ∃ after,
    RunsStmt extractedProgram (before.bindLocal (reader.bindingId 6) (.signed .i32 0))
      (.whileLoop loop.1 loop.2) .next after ∧ Invariant input after input.bytes.length := by
  apply OutputState.run (items := input.bytes) (encode := encodeByte) (limit := input.bytes.length)
    (OutputState.start input.formed input.outputRoom input.unique)
  · intro state current
    core_facts [input, current]
    exact ⟨state, .whileFalse (by core_run), current⟩
  · intro index state inside current
    core_facts [input, current]
    have prefixSize : ((input.bytes.take index).flatMap encodeByte).length = index * 4 := by
      rw [encode_length, List.length_take, Nat.min_eq_left (Nat.le_of_lt inside)]
    have source := current.written.loadBytes_disjoint input.loaded (by
      dsimp only [Lanius.Address] at *
      rw [prefixSize]
      rcases input.separate with left | right
      · exact Or.inl (by omega)
      · exact Or.inr (by omega))
    have selected := Heap.loadBytes_get source (List.getElem?_eq_getElem inside)
    obtain ⟨heap, store, write⟩ := actualCopyByte (state := state) (words := input.words)
      (capacity := input.capacity) input.total index (by omega) (by omega) (by omega)
      (by core_local) (by core_local) current.counter (by core_local)
      (current.written.readable input.inputRoom) current.readable current.written.unique
      (current.views.trans input.noViews) selected
    let stored : State := { state with heap }
    have counter : CountedLocal before stored (reader.bindingId 6) index :=
      ⟨current.cells, current.locals, current.counter⟩
    obtain ⟨next, increment, counted, sameHeap, world, views⟩ :=
      counter.increment (program := extractedProgram) input.formed (by omega)
    have iteration : RunsStmt extractedProgram state loop.2 .next next := by core_stmt
    refine ⟨next, by core_run, iteration, current.advance inside ?_ counted world views⟩
    simpa only [sameHeap, stored, prefixSize, encodeByte, Nat.add_mul, Nat.add_assoc] using write

#print axioms run

/-- The actual index declaration, copy loop and computed total update, with
    their lexical scope. The enclosing read step must supply its fresh setup;
    the copy's data, execution and counter update are derived here. -/
theorem chunk (input : Input ready)
    (counter : CountedLocal base before (reader.bindingId 1) input.total)
    (formed : base.CellsWellFormed) (setup : FreshCellFrame before ready)
    (cell : ready.cellId? (reader.bindingId 1) = some base.nextCell) :
    ∃ after, RunsStmt extractedProgram ready (reader.bindingStatement 6) .next after ∧
      CountedLocal base (restoreLocals before after) (reader.bindingId 1) (input.total + input.bytes.length : Nat) ∧
      BytesWrite ready.heap after.heap (input.destination + input.total * 4) (input.bytes.flatMap encodeByte) ∧
      after.world = ready.world ∧ after.i32ArrayViews = ready.i32ArrayViews := by
  obtain ⟨copied, copy, output⟩ := run input
  have totalCell : copied.cellId? (reader.bindingId 1) = some base.nextCell := by
    simpa [State.cellId?, output.locals, show reader.bindingId 6 ≠ reader.bindingId 1 by decide] using cell
  have total := output.read _ _ (by decide) input.cursor
  have count := output.read _ _ (by decide) input.count
  obtain ⟨next, increment, counted, heap, world, views⟩ := counter.assignScoped
    (program := extractedProgram) (op := .add) (operand := input.bytes.length)
    (replacement := (input.total + input.bytes.length : Nat)) formed
    ((counter.cells.trans setup).trans output.cells) totalCell total
    (show RunsExpr extractedProgram copied (.local (reader.bindingId 5)) (.signed .i32 input.bytes.length) copied from by core_run)
    (by simpa only [evalAssignValue, assignOpBinary?] using
      eval_i32_addNat extractedProgram.target input.total input.bytes.length input.fits)
  refine ⟨restoreLocals ready next, by core_stmt, ?_, ?_, world.trans output.world, views.trans output.views⟩
  · simpa only [restoreLocals] using counted
  · change BytesWrite ready.heap next.heap _ _
    simpa only [heap, List.take_length] using output.written

#print axioms chunk

end ByteIoReadProof.Loop
