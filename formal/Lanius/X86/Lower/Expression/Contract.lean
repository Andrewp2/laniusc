import Lanius.X86.Lower.Expression.Literal.State
import Lanius.CallContracts.CellSpec

namespace Lanius.X86.Lower.Expression

open Lanius.Core Lanius.Semantics Lanius.Separation Lanius.CallContracts Lanius.X86.Buffer

/-- An expression invocation's buffers and logical cursors, independent of its
syntax case. No execution or validity is built into this description. -/
structure Context where
  input : CellId
  output : CellId
  work : CellId
  transport : List Int
  values : List Int
  workspace : List Int
  length : Nat
  position : Nat
  depth : Nat
  active : Value
  capacity : Nat
  start : Nat
  top : Int
  context : Value
  contextLength : Value

namespace Context

variable {c : Context}

def arguments (c : Context) : List Value :=
  Literal.inputValues c.input c.work c.output c.transport.length c.workspace.length c.values.length
    c.length c.capacity c.depth c.active c.context c.contextLength

/-- The three buffers are distinct; arguments cannot alias them as arrays. -/
structure Memory (c : Context) (state : State) : Prop where
  plain : ∀ value ∈ c.arguments, ∀ elements, value ≠ .array elements
  inputBacking : state.cellEntry? c.input = some { id := c.input, value := some (.array (signedI32Values c.transport)) }
  outputBacking : state.cellEntry? c.output = some { id := c.output, value := some (.array (signedI32Values c.values)) }
  workBacking : state.cellEntry? c.work = some { id := c.work, value := some (.array (signedI32Values c.workspace)) }
  inputOutput : c.input ≠ c.output
  inputWork : c.input ≠ c.work
  outputWork : c.output ≠ c.work

/-- Shared input/resource invariants, not an assumption that compilation succeeds. -/
structure Valid (c : Context) : Prop where
  current : c.workspace[0]? = some (c.position : Int)
  cursor : c.workspace[1]? = some (c.start : Int)
  healthy : c.workspace[4]? = some 0
  topFound : c.workspace[6]? = some c.top
  depthBound : c.depth < 512
  storage : c.length ≤ c.transport.length
  bounded : c.length ≤ 2147483647
  outputStorage : c.capacity ≤ c.values.length
  outputBound : c.capacity ≤ 2147483647

/-- Parameter bindings and buffer ownership inside the actual source call. -/
abbrev Ready (c : Context) (state : State) (frontier : Nat) : Prop :=
  Literal.Ready state c.arguments frontier c.input c.output c.work c.transport c.values c.workspace

theorem Ready.memory (ready : c.Ready state frontier) : c.Memory state :=
  ⟨ready.plain, ready.inputBacking, ready.outputBacking, ready.workBacking,
    ready.inputOutput, ready.inputWork, ready.outputWork⟩

/-- Retain the exact workspace and proved output facts across call boundaries. -/
def Result (c : Context) (nextWorkspace : List Int) (post : List Int → Prop) (after : State) : Prop :=
  ∃ emitted,
    after.cellEntry? c.output = some { id := c.output, value := some (.array (signedI32Values emitted)) } ∧
    after.cellEntry? c.work = some { id := c.work, value := some (.array (signedI32Values nextWorkspace)) } ∧ post emitted

/-- Shared total-call contract, including rejection and partial output. -/
def Call (c : Context) (program : Program) (function : FunctionId) (kind : Int)
    (nextWorkspace : List Int) (post : List Int → Prop) : Prop :=
  CellSpec program function c.arguments (.signed .i32 kind) c.Memory
    (fun _ => c.Result nextWorkspace post) (Literal.writes c.output c.work)

/-- Total execution of the actual source call, with exact emitted bytes,
workspace, and unchanged storage outside the two writable buffers. A native
property applies to the actual output window, not an independently built code list. -/
def Emits (c : Context) (program : Program) (function : FunctionId) (kind : Int)
    (code : List UInt8) (nextWorkspace : List Int) (native : List UInt8 → Prop := fun _ => True) : Prop :=
  c.Call program function kind nextWorkspace
    (fun emitted => Emission c.values c.start code emitted ∧ native (byteSlice emitted c.start code.length))

/-- Attach native correctness using the retained byte equality; no re-execution. -/
theorem Emits.refines {native : List UInt8 → Prop} (emits : c.Emits program function kind code nextWorkspace)
    (correct : native code) : c.Emits program function kind code nextWorkspace native := by
  constructor
  intro caller arguments before wellFormed evaluated memory
  obtain ⟨after, run, ⟨emitted, output, work, window, _⟩, effect, heap⟩ :=
    emits.call wellFormed evaluated memory
  exact ⟨after, run, ⟨emitted, output, work, window, window.bytes.symm ▸ correct⟩, effect, heap⟩

end Context
end Lanius.X86.Lower.Expression
