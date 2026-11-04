module

public import Lanius.Memory
public import Lanius.IEEE
public import Lanius.Files.Model

@[expose] public section

/-! Core's world's data: its state and the results of a host call. The
meanings of the services are `Lanius.World`'s, and the file services'
`Lanius.World.Files`' (not exposed). -/

namespace Lanius.World

open Lanius
open Lanius.Core
open Lanius.Memory

abbrev FileEntry := Files.Entry

abbrev FileHandle := Files.Handle

/-- A user-defined external function is outside the closed Lanius world. Its
    result is therefore supplied as part of the initial semantic environment,
    just like process arguments, clocks, and entropy. Responses are ordered so
    replay remains deterministic, and carry semantic values so aggregate
    returns do not depend on a target calling convention. -/
inductive OpaqueOutcome where
  | returned (value : Value)
  | trapped (reason : Trap)
deriving Repr

structure OpaqueResponse where
  external : ExternId
  outcome : OpaqueOutcome
deriving Repr

structure OpaqueCall where
  external : ExternId
  arguments : List Value
deriving Repr

/-- External inputs are part of the initial semantic state. Randomness and
    clocks are explicit streams/values, which makes a run reproducible without
    pretending that these services are pure. -/
structure State where
  arguments : List String := []
  environment : List (String × String) := []
  currentDirectory : String := "."
  standardInput : List UInt8 := []
  standardOutput : List UInt8 := []
  standardError : List UInt8 := []
  unixTimeSeconds : Int := 0
  /-- The readings (seconds, nanoseconds) the monotonic clock gives, one a
  read, in turn: a stream fixed before the run, as the kernel's clock is
  outside the program (SEMANTIC_DECISIONS.md, "Clock readings and secure
  bytes"). -/
  monotonicReadings : List (Int × Nat) := []
  /-- The readings the system (real-time) clock gives, one a read. -/
  systemReadings : List (Int × Nat) := []
  secureU32Stream : List Nat := []
  secureByteStream : List UInt8 := []
  /-- The files and directories under the current directory, and the open
  file descriptors besides 0, 1 and 2 (the standard streams, always open:
  closing one is not modeled), as Linux's file system calls see them
  (`Lanius.Files`, which the x86 kernel's model shares). -/
  fs : Files.System := {}
  calls : List HostService := []
  opaqueResponses : List OpaqueResponse := []
  opaqueCalls : List OpaqueCall := []
deriving Repr

inductive OpaqueCallResult where
  | returned (value : Value) (world : State)
  | trapped (reason : Trap) (world : State)
  | unmodeled (world : State)

inductive CallResult where
  | returned (value : Value) (world : State)
  | exited (code : Int) (world : State)
  | unavailable (service : HostService) (world : State)
  | trapped (reason : Trap) (world : State)
  | typeMismatch (world : State)

inductive EffectResult where
  | returned (value : Value) (heap : Heap) (world : State)
  | exited (code : Int) (heap : Heap) (world : State)
  | unavailable (service : HostService) (heap : Heap) (world : State)
  | trapped (reason : Trap) (heap : Heap) (world : State)
  | typeMismatch (heap : Heap) (world : State)

/-- The most bytes one `read(2)` or `write(2)` transfers (Linux's `MAX_RW_COUNT`). -/
def transferLimit : Nat := 0x7ffff000

end Lanius.World
