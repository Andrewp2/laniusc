import verified_compiler.tests.direct_byte_io_read_loop
import verified_compiler.tests.direct_host_views

namespace ByteIoReadInterface

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics ByteIoReadProof

def reader := Extracted.«verified::byte_io».Functions.«read_file».core

namespace ReadStep

/-- The source-bound read domain and host initializer, factored away from
the old whole step/outer/call implementation. -/
def continuation : Stmt := match reader.bindingStatement 5 with
  | .letLocal _ _ _ body => body
  | _ => .skip

structure Input (state : State) extends Loop.Buffers state where
  handle : Int
  request : Nat
  capacityFits : capacity < 2 ^ 31
  totalBound : total ≤ capacity
  requestFits : request < 2 ^ 31
  requestRoom : request ≤ words * 4
  handleFound : state.local? (reader.argumentId 0) = some (.signed .i32 handle)
  pointerFound : state.local? (reader.bindingId 0) = some (.pointer address)
  sizeFound : state.local? (reader.bindingId 4) = some (.unsigned .usize request)
  requestFound : state.local? (reader.bindingId 2) = some (.signed .i32 request)
  remainingFound : state.local? (reader.bindingId 3) = some (.signed .i32 (capacity - total : Nat))

structure Specification where
  address : Nat
  destination : Nat
  capacity : Nat
  total : Nat
  handle : Int
  request : Nat

def Input.specification (input : Input state) : Specification :=
  ⟨input.address, input.destination, input.capacity, input.total, input.handle, input.request⟩

def Specification.mutable (spec : Specification) (location : Address) : Prop :=
  (spec.address ≤ location ∧ location < spec.address + spec.request) ∨
  (spec.destination ≤ location ∧ location < spec.destination + spec.capacity * 4)

theorem initial (input : Input state) :
    ∃ value heap world, RunsExpr extractedProgram state (reader.bindingInitializer 5)
      value { state with heap, world } ∧
      FileReadResult state.heap state.world input.handle input.address input.request value heap world := by
  have readable : state.heap.Readable input.address input.request := by
    simpa only [Nat.add_zero] using input.inputRoom.subrange
      (start := 0) (length := input.request) (by simpa only [Nat.zero_add] using input.requestRoom)
  obtain ⟨value, heap, world, called, result⟩ :=
    HostViewsProof.readRaw (handle := input.handle) input.noViews input.unique readable
  core_facts [input]
  refine ⟨value, heap, world, ?_, result⟩
  apply RunsExpr.callArguments (values := [.signed .i32 input.handle, .pointer input.address, .unsigned .usize input.request]) ?_ called
  core_arguments

/-- A successful modeled read supplies the byte-copy loop's storage facts;
the real capacity guard supplies the independent output-space bound. -/
def Input.chunk (input : Input state)
    (written : BytesWrite state.heap heap input.address bytes)
    (within : bytes.length ≤ input.request)
    (bounded : input.total + bytes.length ≤ input.capacity) :
    Loop.Input (({ state with heap, world } : State).bindLocal (reader.bindingId 5) (.signed .i32 bytes.length)) := by
  let read : State := { state with heap, world }
  core_facts [input]
  refine {
    address := input.address, words := input.words, destination := input.destination
    capacity := input.capacity, total := input.total, bytes := bytes
    fits := by omega, inputSize := Nat.le_trans within input.requestRoom, outputSize := bounded
    inputRoom := written.readable input.inputRoom, outputRoom := written.readable input.outputRoom
    loaded := written.loadBytes, separate := input.separate
    formed := input.formed.bindLocal (reader.bindingId 5) (.signed .i32 bytes.length)
    unique := written.unique, noViews := input.noViews, packed := ?_, output := ?_, cursor := ?_
    count := State.bindLocal_local? read input.formed (reader.bindingId 5) (.signed .i32 bytes.length) }
  all_goals
    apply State.bindLocal_local?_of_ne read input.formed <;> first | decide | exact input.packed | exact input.output | exact input.cursor

end ReadStep
end ByteIoReadInterface
