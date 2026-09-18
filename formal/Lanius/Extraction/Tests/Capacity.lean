import Lanius.Semantics.Capacity.Execution
import Lanius.Core.Dependencies.Closure
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Capacity
open Lanius.Core Lanius.Semantics

private def i32 : Ty := .scalar (.signed .i32)
private def number (n : Int) : Expr := .value (.signed .i32 n)
private def read (n : VarId) : Expr := .local n
private def add (left right : Expr) : Expr := .binary .add left right
private def update (place : Place) (entry : Expr) : Stmt := .expression (.assign .add place entry)

private def loopBody : Stmt :=
  .sequence (update (.local 2) (.index (read 0) (read 3)))
    (update (.index (.local 0) (read 3)) (number 1))

private def fixture : Program := {
  constants := [⟨0, i32, .signed .i32 7⟩]
  functions := [
    ⟨0, [(0, .slice i32), (1, i32)], .structure 0, some
      (.letLocal 2 i32 (number 0)
        (.sequence (.forRange 3 (number 0) (some (read 1)) false loopBody)
          (.returnValue (some (.structValue 0 [read 2, read 0, .constant 0]))))), none⟩,
    ⟨1, [], i32, some
      (.letLocal 0 (.slice i32)
        (.i32SliceFromRawParts (.stringDataPtr (.value (.string "abcd"))) (number 1))
        (.returnValue (some (.index (read 0) (number 0))))), none⟩,
    ⟨2, [(0, .slice i32), (1, i32)], i32, some
      (.letLocal 2 i32 (number 0)
        (.sequence (.whileLoop (.binary .less (read 2) (read 1))
          (.sequence (update (.local 2) (number 1))
            (.ifThenElse (.binary .equal (read 2) (number 2)) .breakLoop .continueLoop)))
          (.returnValue (some (read 2))))), none⟩] }

private def initial (entries : List Value) : State := {
  cells := [⟨0, some (.array entries)⟩, ⟨1, some (.array [.signed .i32 71])⟩,
    ⟨2, some (.slice i32 900 [] 4 5)⟩]
  nextCell := 3 }

private def config (tail : List Value) : Lanius.Semantics.Capacity.Config := ⟨0, 3, fun root => root == 0 || root == 1, tail⟩

private def sameState (left right : State) : Bool :=
  left.locals == right.locals && left.nextCell == right.nextCell &&
    left.cells.map (fun entry => (entry.id, entry.value)) == right.cells.map (fun entry => (entry.id, entry.value)) &&
    left.heap.nextAddress == right.heap.nextAddress && left.heap.remaining == right.heap.remaining &&
    left.heap.blocks.map (fun block => (block.base, block.size, block.alignment, block.bytes, block.live, block.owned)) ==
      right.heap.blocks.map (fun block => (block.base, block.size, block.alignment, block.bytes, block.live, block.owned)) &&
    left.i32ArrayViews.map (fun view => (view.address, view.root, view.projections, view.length)) ==
      right.i32ArrayViews.map (fun view => (view.address, view.root, view.projections, view.length)) &&
    left.world.calls == right.world.calls && left.world.standardOutput == right.world.standardOutput

#eval show IO Unit from do
  unless Lanius.Semantics.Capacity.Fragment.check fixture (fun _ => true) do throw (IO.userError "capacity fixture rejected")
  for length in List.range 7 do
    for start in List.range 3 do
      for tail in ([[], [.signed .i32 99], [.signed .i32 (-2), .signed .i32 123]] : List (List Value)) do
        let source := (List.range (start + length)).map fun index => Value.signed .i32 (Int.ofNat (index * 17))
        let before := (initial source).bindLocals [(10, .slice i32 0 [] start length), (11, .signed .i32 length)]
        let cfg := config tail
        unless cfg.root < cfg.boundary && cfg.roots cfg.root && cfg.boundary ≤ before.nextCell &&
            before.locals.all (fun binding => cfg.boundary ≤ binding.2) &&
            before.cells.all (fun entry => !cfg.reachable entry.id || match entry.value with
              | none => true
              | some entry => Lanius.Semantics.Capacity.closed cfg entry) do
          throw (IO.userError "capacity fixture violates the execution theorem's initial invariants")
        for input in [Expr.call 0 [read 10, read 11], .call 1 [], .call 2 [read 10, read 11]] do
          let .done result after := evalExpr 120 fixture before input
            | throw (IO.userError "logical capacity fixture did not finish")
          let .done expanded expandedAfter := evalExpr 120 fixture (Lanius.Semantics.Capacity.state cfg before) input
            | throw (IO.userError "expanded capacity fixture did not finish")
          unless expanded == Lanius.Semantics.Capacity.value cfg result && sameState expandedAfter (Lanius.Semantics.Capacity.state cfg after) do
            throw (IO.userError s!"capacity transport changed execution: start={start}, length={length}, tail={tail.length}")
          unless expandedAfter.cell? 2 == before.cell? 2 do
            throw (IO.userError "unreachable historical caller slice was rewritten")
  IO.println "189 capacity execution comparisons passed (calls, indexed writes, offsets, loops, and borrowed string words)"

#eval show IO Unit from do
  let all := fun (_ : FunctionId) => true
  for forbidden in [Expr.i32SliceDataPtr (read 0), .i32ArrayDataPtr (read 0), .arrayToSlice i32 (read 0),
      .loadByte (read 0) (number 0), .storeByte (read 0) (number 0) (number 1),
      .value (.slice i32 0 [] 0 1), .dereference (read 0)] do
    if Lanius.Semantics.Capacity.Fragment.expression all forbidden then throw (IO.userError "capacity-sensitive expression accepted")
  if Lanius.Semantics.Capacity.Fragment.statement all (.forValues 0 (read 1) .skip) then throw (IO.userError "implicit slice iteration accepted")
  let external : Program := { functions := [⟨0, [], i32, none, some (.host .read)⟩] }
  if Lanius.Semantics.Capacity.Fragment.check external all then throw (IO.userError "synchronizing external accepted")
  let hidden : Program := { fixture with functions := fixture.functions ++
    [⟨3, [], i32, some (.expression (.i32SliceDataPtr (read 0))), none⟩] }
  if Lanius.Semantics.Capacity.Fragment.check hidden all then throw (IO.userError "unsupported nested callee accepted")
  let badConstant : Program := { fixture with constants := [⟨0, .slice i32, .slice i32 0 [] 0 1⟩] }
  if Lanius.Semantics.Capacity.Fragment.check badConstant all then throw (IO.userError "root-bearing constant accepted")

run_elab do
  for name in #[``Lanius.Semantics.Capacity.execution, ``Lanius.Semantics.Capacity.Fragment.checked,
      ``Lanius.Semantics.Capacity.slice_index, ``Lanius.Semantics.Capacity.writeResolvedPlace, ``Lanius.Semantics.Capacity.rawI32Slice] do
    for assumption in ← Lean.collectAxioms name do
      unless assumption == ``propext || assumption == ``Classical.choice || assumption == ``Quot.sound do
        throwError "Capacity theorem {name} depends on unexpected axiom {assumption}"

end Lanius.Extraction.Tests.Capacity
