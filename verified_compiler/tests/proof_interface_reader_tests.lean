import verified_compiler.tests.direct_byte_io_read
import Lanius.Memory.Allocation

namespace ProofInterfaceReaderTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics

private def reader := Extracted.«verified::byte_io».Functions.«read_file».core
private def call (capacity handle : Int) (scratch : Nat) : Expr :=
  .call reader.id ([.signed .i32 handle, .rawSlice (.scalar (.signed .i32)) 16 4,
    .signed .i32 capacity, .rawSlice (.scalar (.signed .i32)) scratch 16384].map Expr.value)

private def outputHeap : Heap := {
  blocks := [
    { base := 16, size := 16, alignment := 4, bytes := (List.replicate 4 (i32Bytes 11)).flatten },
    { base := 40, size := 4, alignment := 4, bytes := [71, 72, 73, 74] }]
  nextAddress := 64, remaining := some 0 }

private def input (contents : List UInt8) : State := ({
  heap := outputHeap.allocatedI32 16384 (some 0)
  world := {
    files := [{ path := [1], bytes := 99 :: contents }]
    fileHandles := [{ id := 3, path := [1], offset := 1, readable := true }]
    standardOutput := [88]
    standardError := [89] } } : State).bindLocal 9 (.signed .i32 777)

private def early (capacity : Int) : IO Unit := do
  let before : State := { world := { standardOutput := [88] } }
  let .done result after := evalExpr 1000 extractedProgram before (call capacity 3 0)
    | throw (IO.userError "negative/null reader guard did not return")
  unless result == .signed .i32 (-2) && after.world.calls.isEmpty && after.heap.blocks.isEmpty &&
      after.world.standardOutput == before.world.standardOutput do
    throw (IO.userError "negative/null reader guard accessed unused memory or IO")

private def check (contents : List UInt8) (handle expected : Int) (reads cursor : Nat)
    (copied : Bool) : IO Unit := do
  let before := input contents
  let .done result after := evalExpr 10000 extractedProgram before (call 4 handle 64)
    | throw (IO.userError "actual whole reader did not finish")
  let expectedOutput := if copied then contents.flatMap (fun byte => i32Bytes byte.toNat)
    else (List.replicate 4 (i32Bytes 11)).flatten
  unless result == .signed .i32 expected && after.world.calls.length == reads &&
      ((after.world.handle? 3).map World.FileHandle.offset) == some cursor &&
      (after.heap.loadBytes 16 16).toOption == some expectedOutput do
    throw (IO.userError s!"reader mismatch result={repr result}, reads={after.world.calls.length}, cursor={repr ((after.world.handle? 3).map World.FileHandle.offset)}")
  unless (after.heap.loadBytes 40 4).toOption == some [71, 72, 73, 74] &&
      after.locals == before.locals && after.local? 9 == before.local? 9 &&
      after.heap.nextAddress == before.heap.nextAddress && after.heap.remaining == some 0 &&
      after.world.standardOutput == before.world.standardOutput &&
      after.world.standardError == before.world.standardError &&
      after.world.files.map (fun file => (file.path, file.bytes)) ==
        before.world.files.map (fun file => (file.path, file.bytes)) do
    throw (IO.userError "reader changed protected caller, gap, budget, or unrelated modeled world")

-- These are deterministic World.readFileBytes executions, not OS claims.
-- Zero remaining allocator budget is compatible with reading into existing
-- buffers; read_file allocates nothing. The owned fixture covers allocator OOM.
#eval (do
  early (-1)
  early 4
  check [0, 127, 128, 255] 3 4 2 5 true
  check [0, 127, 128, 255, 42] 3 (-2) 1 6 false
  check [0, 127, 128, 255] 99 (-1) 1 1 false
  IO.println "reader interface regression: negative/null, exact bytes, overflow, bad handle, zero budget, modeled world" : IO Unit)

end ProofInterfaceReaderTests
