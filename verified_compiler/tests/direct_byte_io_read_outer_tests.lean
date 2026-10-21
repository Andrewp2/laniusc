import verified_compiler.tests.direct_byte_io_read_loop

namespace ByteIoReadOuterTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics ByteIoReadProof

private def reader := Extracted.«verified::byte_io».Functions.«read_file».core
private def fileBytes : List UInt8 := [0, 127, 128, 255, 255, 1, 128, 255, 42, 9, 17, 33]
private def loaded (heap : Heap) (address : Nat) (bytes : List UInt8) : Bool :=
  match heap.loadBytes address bytes.length with
  | .ok actual => actual == bytes
  | _ => false

-- Full-size scratch storage tests the real outer body, rather than supplying
-- request/count locals. The reference request is capped remaining capacity + 1.
private def check (capacity total length offset : Nat) (handle : Int) (readable present : Bool) : IO Unit := do
  let bytes := fileBytes.take length
  let destination := 65544
  let before : State := ({
    heap := {
      blocks := [
        { base := 4, size := 65536, alignment := 4, bytes := List.replicate 65536 0, owned := false },
        { base := destination, size := capacity * 4, alignment := 4,
          bytes := List.flatten (List.replicate capacity (i32Bytes 11)), owned := false }]
      nextAddress := destination + max (capacity * 4) 1 },
    world := {
      files := if present then [{ path := [1], bytes }] else [],
      fileHandles := [{ id := 3, path := [1], readable, offset }] } } : State)
    |>.bindLocal (reader.argumentId 0) (.signed .i32 handle)
    |>.bindLocal (reader.argumentId 1) (.rawSlice (.scalar (.signed .i32)) destination capacity)
    |>.bindLocal (reader.argumentId 2) (.signed .i32 capacity)
    |>.bindLocal (reader.argumentId 3) (.rawSlice (.scalar (.signed .i32)) 4 16384)
    |>.bindLocal (reader.bindingId 0) (.pointer 4)
    |>.bindLocal (reader.bindingId 1) (.signed .i32 total)
    |>.bindLocal (reader.bindingId 2) (.signed .i32 91)
    |>.bindLocal (reader.bindingId 3) (.signed .i32 92)
    |>.bindLocal (reader.bindingId 4) (.unsigned .usize 93)
  let valid := handle == 3 && readable && present
  let delivered := if valid then (bytes.drop offset).take (min 65536 (capacity - total + 1)) else []
  let copies := valid && !delivered.isEmpty && total + delivered.length ≤ capacity
  let expected : Option Int := if !valid then some (-1)
    else if delivered.isEmpty then some total else if !copies then some (-2) else none
  match execStmt 100 extractedProgram before (reader.whileLoop 0).2 with
  | .done completion after =>
      let completed := match completion, expected with
        | .next, none => true
        | .returned (some (.signed .i32 actual)), some value => actual == value
        | _, _ => false
      let copied := if copies then
        loaded after.heap (destination + total * 4) (delivered.flatMap Loop.encodeByte)
        else loaded after.heap destination (List.flatten (List.replicate (min capacity 2) (i32Bytes 11)))
      let scratch := loaded after.heap 4 delivered
      let preservedHead := total == 0 || loaded after.heap destination (i32Bytes 11)
      let preservedTail := total + delivered.length ≥ capacity ||
        loaded after.heap (destination + (total + delivered.length) * 4) (i32Bytes 11)
      let counted := after.local? (reader.bindingId 1) ==
        some (.signed .i32 (if copies then total + delivered.length else total))
      let scopes := after.locals == before.locals &&
        after.local? (reader.bindingId 2) == some (.signed .i32 91) &&
        after.local? (reader.bindingId 3) == some (.signed .i32 92) &&
        after.local? (reader.bindingId 4) == some (.unsigned .usize 93) &&
        after.local? (reader.bindingId 5) == none && after.local? (reader.bindingId 6) == none
      let cursor := match after.world.handle? 3 with
        | some file => file.offset == offset + delivered.length
        | none => false
      unless completed && copied && scratch && preservedHead && preservedTail && counted && scopes && cursor &&
          after.world.calls == [.read] do
        throw (IO.userError s!"outer read body failed: capacity={capacity}, total={total}, length={length}, offset={offset}, handle={handle}, readable={readable}, present={present}")
  | _ => throw (IO.userError "outer read body did not complete")

#eval (do
  for total in List.range 9 do
    for length in [0, 1, 6, 8, 12] do
      for offset in [0, 2, 14] do check 8 total length offset 3 true true
    check 8 total 12 0 9 true true
    check 8 total 12 0 3 false true
    check 8 total 12 0 3 true false
  check 0 0 0 0 3 true true
  check 0 0 1 0 3 true true
  -- Boundary on both sides of the request guard, with small actual payloads.
  for capacity in [65535, 65536, 65537] do
    for length in [0, 1, 6] do check capacity 0 length 0 3 true true
    check capacity (capacity - 1) 6 0 3 true true
    check capacity capacity 1 0 3 true true : IO Unit)

#eval IO.println "proof-interface reader outer runtime: PASS"

end ByteIoReadOuterTests
