import Lanius.Semantics.CellOnly.Region
import Lanius.Semantics.I32Views
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.CellOnly

open Lanius.Core Lanius.Semantics

private def i32 : Ty := .scalar (.signed .i32)
private def number (value : Int) : Expr := .value (.signed .i32 value)
private def read (id : VarId) : Expr := .local id
private def update (index : Expr) : Stmt :=
  .expression (.assign .add (.index (.local 1) index) (number 1))

private def recursiveBody : Stmt :=
  .ifThenElse (.binary .equal (read 0) (number 0)) (.returnValue (some (number 0)))
    (.sequence (update (.binary .subtract (read 0) (number 1)))
      (.returnValue (some (.binary .add
        (.call 0 [.binary .subtract (read 0) (number 1), read 1]) (number 1)))))

private def rangeBody : Stmt :=
  .sequence (.forRange 2 (number 0) (some (read 0)) false (update (read 2)))
    (.returnValue (some (read 0)))

private def whileBody : Stmt :=
  .letLocal 2 i32 (number 0)
    (.sequence (.whileLoop (.binary .less (read 2) (read 0))
      (.sequence (update (read 2))
        (.sequence (.expression (.assign .add (.local 2) (number 1)))
          (.ifThenElse (.binary .equal (read 2) (read 0)) .breakLoop .continueLoop))))
      (.returnValue (some (read 2))))

private def fixture : Program := { functions :=
  ([recursiveBody, rangeBody, whileBody].zipIdx).map fun (body, id) =>
    ⟨id, [(0, i32), (1, .slice i32)], i32, some body, none⟩ }

private def register (before : State) (words : List Int) : IO State := do
  let .allocated address heap := before.heap.allocate (words.length * 4) 4
    | throw (IO.userError "cell-only fixture allocation failed")
  let .done _ registered := mapRawI32Slice { before with heap } address words.length
    | throw (IO.userError "cell-only fixture registration failed")
  let some ready := registered.assignCell before.nextCell (.array (signedI32Values words))
    | throw (IO.userError "cell-only fixture initialization failed")
  pure ready

private def sameNative (before after : State) : Bool :=
  before.heap.nextAddress == after.heap.nextAddress && before.heap.remaining == after.heap.remaining &&
    before.heap.blocks.map (fun block => (block.base, block.size, block.alignment, block.bytes, block.live, block.owned)) ==
      after.heap.blocks.map (fun block => (block.base, block.size, block.alignment, block.bytes, block.live, block.owned)) &&
    before.i32ArrayViews.map (fun view => (view.address, view.root, view.projections, view.length)) ==
      after.i32ArrayViews.map (fun view => (view.address, view.root, view.projections, view.length))

#eval show IO Unit from do
  for body in [recursiveBody, rangeBody, whileBody] do
    unless (Lanius.Semantics.CellOnly.checkRegion? fixture body).isSome do
      throw (IO.userError "recursive or looping cell-only closure rejected")
  for length in List.range 7 do
    for offset in List.range 3 do
      let original := List.replicate (offset + length + 2) (-17)
      let source ← register {} original
      let before ← register source [-2147483648, 2147483647]
      for function in List.range 3 do
        let .done result after := evalExpr 180 fixture before (.call function
            [number length, .value (.slice i32 0 [] offset length)])
          | throw (IO.userError s!"cell-only execution failed: function={function}, length={length}, offset={offset}")
        let expected := original.take offset ++ List.replicate length (-16) ++ original.drop (offset + length)
        unless result == .signed .i32 length && after.cell? 0 == some (.array (signedI32Values expected)) &&
            after.cell? 1 == before.cell? 1 && after.locals == before.locals && sameNative before after do
          throw (IO.userError "cell-only recursion/loop changed native storage or failed to update exactly its slice")
  IO.println "63 cell-only executions preserve native heap/views while updating exact array slices"

#eval show IO Unit from do
  let all := fun (_ : FunctionId) => true
  let forbidden : List Expr := [
    .alloc (number 4) (number 4), .realloc (read 0) (number 4) (number 8) (number 4),
    .dealloc (read 0) (number 4) (number 4), .loadByte (read 0) (number 0),
    .storeByte (read 0) (number 0) (number 1), .i32ArrayDataPtr (read 0),
    .i32SliceDataPtr (read 0), .i32SliceFromRawParts (read 0) (number 1),
    .stringDataPtr (.value (.string "abcd"))]
  for operation in forbidden do
    for body in [.expression operation,
        .ifThenElse (.value (.boolean false)) (.expression operation) .skip] do
      if (Lanius.Semantics.CellOnly.checkRegion? fixture body).isSome then
        throw (IO.userError "native operation accepted, including on an untaken branch")
  let host : Program := { functions := [⟨0, [], i32, none, some (.host .argc)⟩] }
  if (Lanius.Semantics.CellOnly.checkRegion? host (.returnValue (some (.call 0 [])))).isSome then
    throw (IO.userError "synchronizing host call accepted")
  let hidden : Program := { functions := [
    ⟨0, [], i32, some (.returnValue (some (.call 1 []))), none⟩,
    ⟨1, [], i32, some (.returnValue (some (.stringDataPtr (.value (.string "abcd"))))), none⟩] }
  if (Lanius.Semantics.CellOnly.checkRegion? hidden (.returnValue (some (.call 0 [])))).isSome then
    throw (IO.userError "native operation hidden in a transitive callee accepted")
  if Lanius.Semantics.CellOnly.check fixture (fun id => id != 0) then
    pure ()
  else throw (IO.userError "independent cell-only functions rejected")
  unless Lanius.Semantics.CellOnly.check fixture all do
    throw (IO.userError "recursive closed call set rejected")

run_elab do
  for name in #[``Lanius.Semantics.CellOnly.execution, ``Lanius.Semantics.CellOnly.checked,
      ``Lanius.Semantics.CellOnly.Region.executes] do
    for assumption in ← Lean.collectAxioms name do
      unless assumption == ``propext || assumption == ``Classical.choice || assumption == ``Quot.sound do
        throwError "Cell-only theorem {name} adds unexpected axiom {assumption}"

end Lanius.Extraction.Tests.CellOnly
