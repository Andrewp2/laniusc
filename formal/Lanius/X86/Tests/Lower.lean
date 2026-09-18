import Lanius.X86.Lower.Implementation
import Lanius.Extraction.ExtractorContract

namespace Lanius.X86.Tests.Lower

open Lanius.Core Lanius.Semantics Lanius.X86.Source Lanius.X86.Source.Lower
open Lanius.X86.Lower.Parameter

private def dirty : List Int := (List.range 32).map (fun n => -700 + Int.ofNat n)

private def initial (words : List Int) (aliasOutput : Bool) : State :=
  let cells := if aliasOutput then [⟨0, some (.array (signedI32Values words))⟩]
    else [⟨0, some (.array (signedI32Values dirty))⟩, ⟨1, some (.array (signedI32Values words))⟩]
  (List.range 12).foldl (fun state id => state.bindLocal id (.signed .i32 (900 + id : Nat)))
    { cells, nextCell := if aliasOutput then 1 else 2,
      world := { arguments := ["keep"], standardOutput := [65], standardError := [66] } }

private def checkFrame (before after : State) (mayWrite : Bool) : IO Unit := do
  unless after.locals == before.locals do throw (IO.userError "lowering did not restore caller locals")
  for cell in before.cells do
    if !mayWrite || cell.id != 0 then
      unless after.cell? cell.id == cell.value do throw (IO.userError s!"lowering modified framed cell {cell.id}")
  unless after.world.arguments == before.world.arguments && after.world.standardOutput == before.world.standardOutput &&
      after.world.standardError == before.world.standardError && after.world.calls.isEmpty &&
      after.heap.blocks.isEmpty && after.heap.nextAddress == before.heap.nextAddress &&
      after.heap.remaining == before.heap.remaining && after.i32ArrayViews.isEmpty do
    throw (IO.userError "lowering modified the host/heap frame")

private def words (count position base : Nat) (trailing : Bool) : List Int :=
  [1, 64, 123, 1, (count : Int), if trailing then 6 else 4] ++
    (List.range count).flatMap (fun index => [((base + index * 7 : Nat) : Int), 1]) ++
    (if trailing then [2] else []) ++ [10, 1, 1, ((base + position * 7 : Nat) : Int)] ++
    (if trailing then [0] else [])

private def runCase (checked : CheckedCompile emitters) (transport : List Int) (position : Fin 6)
    (start capacity : Int) (success : Bool) (aliasOutput : Bool := false) : IO Unit := do
  let before := initial transport aliasOutput
  let original := if aliasOutput then transport else dirty
  let inputCell := if aliasOutput then 0 else 1
  -- An unusable output on rejection detects accidental partial emission or
  -- output access before the complete-function reservation.
  let output := if success then Value.slice i32 0 [] 0 original.length else .unit
  let inputs := compileInputs (.slice i32 inputCell [] 0 transport.length) transport.length output capacity start
  match evalExpr 4000 emitters.pack.program.core before (.call checked.internal.source.function.id (inputs.map Expr.value)) with
  | .done (.signed .i32 result) after =>
      let expected : List Int := if success then original.take start.toNat ++ (code position).map Int.ofNat ++
        original.drop (start.toNat + codeSize position) else original
      let wanted : Int := if success then start + codeSize position else -1
      unless result == wanted && after.cell? 0 == some (.array (signedI32Values expected)) do
        throw (IO.userError s!"wrong compile result or output window: pos={position.val} cursor={start} capacity={capacity}")
      checkFrame before after success
  | _ => throw (IO.userError "actual Lanius compile body trapped or failed to terminate")

def check (arguments : List String) : IO UInt32 := do
  let modulePath :: paths := arguments | throw (IO.userError "expected extracted backend module and its exact ordered sources")
  let emitted ← IO.FS.readFile modulePath
  unless emitted.startsWith Lanius.Extraction.ExtractorContract.modulePrefix &&
      emitted.endsWith Lanius.Extraction.ExtractorContract.moduleSuffix do
    throw (IO.userError "bad backend source-pack framing")
  let encoded := ((emitted.drop Lanius.Extraction.ExtractorContract.modulePrefix.length).dropEnd
    Lanius.Extraction.ExtractorContract.moduleSuffix.length).toString
  let sources ← paths.mapM fun (path : String) => do
    let contents ← IO.FS.readBinFile path
    pure ({ path, bytes := contents.toList.map UInt8.toNat } : Lanius.Extraction.SourceFile)
  let emitters ← IO.ofExcept (checkBuffer encoded sources)
  let some checked := checkCompile? emitters | throw (IO.userError "Lanius selector/mapping/compile source authentication failed")
  have _success := fun {before caller : State} {arguments : List Expr} {cell inputCell : CellId}
      {values : List Int} {function : Function} =>
    compile_function_certified (before := before) (caller := caller) (arguments := arguments) (cell := cell)
      (values := values) (inputCell := inputCell) (function := function) checked
  have _rejection := fun {before caller : State} {arguments : List Expr} {inputCell : CellId}
      {output : Value} {function : Function} =>
    compile_function_rejects_capacity (before := before) (caller := caller) (arguments := arguments)
      (inputCell := inputCell) (output := output) (function := function) checked
  have _invalid := fun {before caller : State} {arguments : List Expr} {input output : Value} {length : Int} =>
    compile_selection_reject (before := before) (caller := caller) (arguments := arguments)
      (input := input) (output := output) (length := length) checked
  for wrong in [compileBody checked.selector.source.function.id checked.mapping.internal.source.function.id
      emitters.fits.source.function.id emitters.returnNear.source.function.id (emitters.registerWrappers .move).source.function.id checked.resultRegister.id,
      compileBody checked.mapping.internal.source.function.id checked.selector.source.function.id
        emitters.fits.source.function.id (emitters.registerWrappers .move).source.function.id emitters.returnNear.source.function.id checked.resultRegister.id] do
    unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["backend", "parameter"] "compile" compileParameters i32 wrong).isNone do
      throw (IO.userError "source authentication accepted swapped compiler callees")
  unless (Lanius.Extraction.Source.checkInternal? emitters.pack.program ["backend", "parameter"] "argument_register"
      [(0, i32)] i32 (Table.body checked.mapping.rows.reverse)).isNone do
    throw (IO.userError "source authentication accepted reversed ABI argument registers")
  let mut successful := 0
  let mut rejected := 0
  for count in [1, 2, 3, 4, 5, 6] do
    for position in List.finRange 6 do
      if position.val < count then
        for base in [0, 2147483600] do
          for trailing in [false, true] do
            let transport := words count position.val base trailing
            let start := if trailing then 5 else 0
            runCase checked transport position start (start + codeSize position) true
            successful := successful + 1
            for (cursor, capacity) in [(start, start + codeSize position - 1), (-1, 32), (2147483647, 2147483647)] do
              runCase checked transport position cursor capacity false
              rejected := rejected + 1
  for position in List.finRange 6 do
    runCase checked (words 6 position.val 100 true) position 0 (codeSize position) true true
    successful := successful + 1
  -- Parameter order, not local-ID order, determines the ABI register. Include
  -- zero and the exact i32 maximum among deliberately unsorted identifiers.
  let permuted : List Int := [2147483647, 0, 91, 7, 12345, 2]
  for position in List.finRange 6 do
    for trailing in [false, true] do
      let transport := [1, 64, 2147483647, 1, 6, if trailing then 6 else 4] ++
        permuted.flatMap (fun id => [id, 1]) ++ (if trailing then [2] else []) ++
        [10, 1, 1, permuted[position.val]!] ++ (if trailing then [0] else [])
      runCase checked transport position 0 (codeSize position) true
      successful := successful + 1
  let valid := words 6 0 0 true
  let invalid := (List.range valid.length).map valid.take ++ [valid ++ [0], valid.set 0 2, valid.set 1 32,
    valid.set 2 (-1), valid.set 3 2, valid.set 4 0, valid.set 4 7, valid.set 5 5,
    valid.set 6 (-1), valid.set 8 0, valid.set 7 2, valid.set 22 99]
  for transport in invalid do
    runCase checked transport ⟨0, by decide⟩ 0 32 false
    rejected := rejected + 1
  for position in ([-2147483648, -1, 0, 1, 2, 3, 4, 5, 6, 2147483647] : List Int) do
    let before := initial [] false
    match evalExpr 100 emitters.pack.program.core before
        (.call checked.mapping.internal.source.function.id [.value (.signed .i32 position)]) with
    | .done (.signed .i32 value) after =>
        unless value == Table.lookup argumentEntries position do throw (IO.userError "ABI mapping result differs")
        checkFrame before after false
    | _ => throw (IO.userError "ABI mapping did not return an i32")
  IO.println s!"source-linked Lanius lowering: {successful} successful full compile calls, {rejected} rejection calls without output access, 10 ABI mappings; all caller/input/host frames preserved, including 6 input/output-alias cases"
  pure 0

end Lanius.X86.Tests.Lower

def main (arguments : List String) : IO UInt32 := Lanius.X86.Tests.Lower.check arguments
