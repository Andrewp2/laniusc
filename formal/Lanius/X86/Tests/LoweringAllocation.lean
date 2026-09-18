import Lanius.X86.Transport.Core
import Lanius.X86.Tests.Memory
import Lanius.Extraction.CoreSynthesis.Provenance
import Lanius.Extraction.ExtractorContract

/-! Source tree → actual Lanius collector → actual Lanius ID allocator.
The reference IDs come from CoreSynthesis.Program.allocate on independently
reconstructed multiunit Surface programs, never from hand-authored ID rows. -/
namespace Lanius.X86.Tests.LoweringAllocation

open Lanius.Core Lanius.Semantics Lanius.Extraction
open Lanius.Extraction.CoreSynthesis.Program

private def unframe (emitted : String) : IO String := do
  unless emitted.startsWith ExtractorContract.modulePrefix && emitted.endsWith ExtractorContract.moduleSuffix do
    throw (IO.userError "invalid allocation extraction framing")
  pure ((emitted.drop ExtractorContract.modulePrefix.length).dropEnd ExtractorContract.moduleSuffix.length).toString

private def materialize (nodes : List ParseNode) : List Int × List Int := Id.run do
  let mut records : List Int := []
  let mut offsets : List Int := []
  for node in nodes do
    offsets := offsets ++ [(records.length : Int)]
    records := records ++ [(node.production : Int), node.position_start, node.position_end, node.children.length] ++
      node.children.flatMap (fun child => match child with
        | .token token => [1, (token : Int), 0]
        | .node node => [2, (node : Int), 0])
  return (records, offsets)

private def descriptor : SurfaceItemValue → Nat × Bool × Int × Int
  | .structure record => (1, record.is_public, record.name.token, -1)
  | .type_alias name visible target => (2, visible, name.token, target.parse_node)
  | .constant name visible _ _ => (3, visible, name.token, -1)
  | .function function => (4, function.is_public, function.name.token, -1)
  | .extern_function function => (5, function.is_public, function.name.token, -1)
  | .module path => (6, false, -1, path.parse_node)
  | .import_path path => (7, false, -1, path.parse_node)

private structure Fixture where
  artifact : Artifact
  located : SurfaceFile
  surface : Lanius.Surface.File
  modulePath : Lanius.Names.ModulePath

private def fixtureTexts : List String := [
  "module allocation::first; import allocation::second; " ++
    "pub extern \"lanius_std\" fn argc() -> i32; pub fn first() -> i32 { return 1; } " ++
    "extern \"lanius_std\" fn arg_len(index: i32) -> i32; fn second() -> i32 { return 2; } " ++
    "struct Pair { value: i32, } pub type Count = i32; const N: i32 = 3;",
  "module allocation::second; " ++
    "pub struct Pair { value: bool, } struct Empty {} type Count = usize; type Buffer = [i32]; " ++
    "pub const N: i32 = 4; const M: i32 = 5; fn one() -> i32 { return 1; } " ++
    "pub extern \"lanius_std\" fn argc() -> i32; pub fn two() -> i32 { return 2; }",
  "module allocation::empty;",
  "module allocation::externs; extern \"lanius_std\" fn argc() -> i32; " ++
    "pub extern \"lanius_std\" fn arg_len(index: i32) -> i32; const N: i32 = 9;"]

private def compile (backend : String) (directory : System.FilePath)
    (program : Program) (id : Lanius.FunctionId) (name : String) : IO System.FilePath := do
  let some transport := Transport.program? program id
    | throw (IO.userError s!"unsupported actual {name} closure")
  let path := directory / s!"{name}.core"
  IO.FS.writeBinFile path ⟨(transport.flatMap i32Bytes).toArray⟩
  let (status, code) ← Harness.outputBytes "timeout" #["--kill-after=1s", "2s", backend, "--raw", path.toString]
  unless status == 0 && !code.isEmpty do throw (IO.userError s!"backend rejected {name}: {status}")
  let binary := directory / s!"{name}.bin"
  IO.FS.writeBinFile binary code
  pure binary

private def collect (program : Program) (function : Lanius.FunctionId)
    (binary directory : System.FilePath) (fixture : Fixture) (unit : Nat) : IO (List Int) := do
  let (records, offsets) := materialize fixture.artifact.parse_nodes
  let capacity := 8 + fixture.located.value.items.length * 8
  let output : List Int := List.replicate (capacity + 3) 777
  let buffers := [records, offsets, output]
  let args : List Value := [
    .slice (.scalar (.signed .i32)) 0 [] 0 records.length, .signed .i32 records.length,
    .slice (.scalar (.signed .i32)) 1 [] 0 offsets.length, .signed .i32 offsets.length,
    .signed .i32 fixture.artifact.tokens.length, .signed .i32 (fixture.artifact.parse_root.getD 0),
    .signed .i32 unit, .slice (.scalar (.signed .i32)) 2 [] 0 output.length, .signed .i32 capacity]
  let initial := Memory.state buffers
  let label := s!"collector unit {unit}"
  let words ← match evalExpr 30000 program initial (.call function (args.map Expr.value)) with
    | .done (.signed .i32 result) after => do
      unless result == fixture.located.value.items.length do throw (IO.userError s!"{label}: rejected actual Surface unit")
      let some (.array values) := after.cell? 2 | throw (IO.userError s!"{label}: no output")
      let some words := values.mapM (fun value => match value with | .signed .i32 value => some value | _ => none)
        | throw (IO.userError s!"{label}: non-i32 output")
      unless words.drop capacity == [777, 777, 777] do throw (IO.userError s!"{label}: damaged canaries")
      pure (words.take capacity)
    | _ => throw (IO.userError s!"{label}: trapped or exhausted")
  if ← Memory.check program function binary directory args buffers label then
    throw (IO.userError s!"{label}: unexpected native trap")
  pure words

private def oracle (fixtures : List Fixture) (tables : List (List Int)) : IO (List Int) := do
  let units := fixtures.zipIdx.map fun (fixture, unit) =>
    ({ moduleId := unit, modulePath := fixture.modulePath, surface := fixture.surface } : CoreSynthesis.Program.Unit)
  let allocations := CoreSynthesis.Program.allocate units
  let mut output : List Int := []
  let mut totals : List Int := List.replicate 8 0
  for (((fixture, table), allocation), unit) in ((fixtures.zip tables).zip allocations).zipIdx do
    let mut counts : List Nat := List.replicate 8 0
    unless table[0]! == fixture.located.value.items.length do throw (IO.userError "collector row count differs from Surface")
    for (item, row) in fixture.located.value.items.zipIdx do
      let (kind, visible, name, target) := descriptor item.value
      let original := (table.drop (8 + row * 8)).take 8
      unless original[0]! == unit && original[1]! == kind && original[2]! == (if visible then 1 else 0) &&
          original[3]! == item.parse_node && original[5]! == name && original[6]! == target && original[7]! == counts[kind]! do
        throw (IO.userError "collector origin/ordinal differs from independently reconstructed Surface")
      let ordinal := counts[kind]!
      let (declaration, core) : Int × Int := match kind with
        | 1 => (allocation.structureDeclarationStart + ordinal, allocation.structureTypeStart + ordinal)
        | 2 => (allocation.typeAliasDeclarationStart + ordinal, -1)
        | 3 => (allocation.constantDeclarationStart + ordinal, allocation.constantIdStart + ordinal)
        | 4 => (allocation.functionDeclarationStart + ordinal, allocation.functionIdStart + ordinal)
        | 5 => (allocation.externDeclarationStart + ordinal, allocation.externIdStart + ordinal)
        | _ => (-1, -1)
      output := output ++ original ++ [declaration, core]
      counts := counts.set kind (ordinal + 1)
      totals := (totals.set 1 (totals[1]! + 1))
      if kind <= 5 then totals := totals.set (kind + 1) (totals[kind + 1]! + 1)
  totals := totals.set 0 fixtures.length
  totals := totals.set 7 ((totals.drop 2).take 5).sum
  pure (totals ++ output)

private def runCase (program : Program) (function : Lanius.FunctionId)
    (binary directory : System.FilePath) (label : String) (input : List Int)
    (length units capacity : Int) (wanted : Option (List Int)) : IO _root_.Unit := do
  let output : List Int := List.replicate (capacity.toNat + 3) 777
  let buffers := [input, output]
  let args : List Value := [.slice (.scalar (.signed .i32)) 0 [] 0 input.length, .signed .i32 length,
    .signed .i32 units, .slice (.scalar (.signed .i32)) 1 [] 0 output.length, .signed .i32 capacity]
  let initial := Memory.state buffers
  match evalExpr 30000 program initial (.call function (args.map Expr.value)) with
  | .done (.signed .i32 result) after =>
    unless result == (wanted.map fun words => (words.length : Int)).getD (-1) do
      throw (IO.userError s!"{label}: wrong result {result}")
    unless after.cell? 0 == initial.cell? 0 do throw (IO.userError s!"{label}: changed source-origin tables")
    let some (.array actual) := after.cell? 1 | throw (IO.userError s!"{label}: missing allocation table")
    unless actual.drop capacity.toNat == List.replicate 3 (.signed .i32 777) do
      throw (IO.userError s!"{label}: wrote past capacity")
    if let some expected := wanted then
      unless actual == (expected ++ List.replicate (output.length - expected.length) 777).map (Value.signed .i32) do
        throw (IO.userError s!"{label}: IDs differ from CoreSynthesis.Program.allocate")
  | _ => throw (IO.userError s!"{label}: trapped or exhausted")
  if ← Memory.check program function binary directory args buffers label then
    throw (IO.userError s!"{label}: unexpected native trap")

def main (arguments : List String) : IO UInt32 := do
  let [backend, extractor, modulePath, allocationPath, declarationPath, treePath, parserPath, directory] := arguments
    | throw (IO.userError "expected backend, extractor, source extraction, allocation/declaration/tree/parser sources, and output directory")
  let directory := System.FilePath.mk directory
  IO.FS.createDirAll directory
  let encoded ← unframe (← IO.FS.readFile modulePath)
  let sources ← ([allocationPath, declarationPath, treePath, parserPath] : List String).mapM fun (path : String) => do
    let bytes ← IO.FS.readBinFile path
    pure ({ path, bytes := bytes.toList.map UInt8.toNat } : SourceFile)
  let checked ← match checkCompactCoreSourcePack encoded sources with
    | .success checked => pure checked
    | .failure stage => throw (IO.userError s!"allocator source validation failed: {stage}")
  let program := checked.program.core
  let some collector := checkSourceFunction? checked.program ["lowering", "declarations"] "collect"
    | throw (IO.userError "missing actual collector")
  let some allocator := checkSourceFunction? checked.program ["lowering", "allocation"] "allocate"
    | throw (IO.userError "missing actual allocator")
  let collectorBinary ← compile backend directory program collector.function.id "collector"
  let allocatorBinary ← compile backend directory program allocator.function.id "allocator"
  let mut fixtures : List Fixture := []
  for (text, index) in fixtureTexts.zipIdx do
    let path := directory / s!"unit{index}.lani"
    IO.FS.writeFile path text
    let (status, emitted) ← Harness.outputBytes "timeout" #["--kill-after=1s", "2s", extractor, path.toString]
    unless status == 0 do throw (IO.userError s!"extractor rejected allocation fixture {index}: {status}")
    let encoded ← unframe (String.fromUTF8! emitted)
    let some pack := decodeCompactArtifactPack? encoded | throw (IO.userError "fixture did not decode")
    let [artifact] := pack.units | throw (IO.userError "wrong fixture source count")
    unless artifact.sources == [⟨path.toString, text.toUTF8.toList.map UInt8.toNat⟩] do
      throw (IO.userError "fixture source binding differs")
    let some surface := checkSurfaceArtifact? artifact | throw (IO.userError "fixture Surface/source validation failed")
    let some modulePath := ArtifactPackContextChecker.declaredModulePath? surface.surface
      | throw (IO.userError "fixture module path invalid")
    fixtures := fixtures ++ [⟨artifact, surface.reconstructed, surface.surface, modulePath⟩]
  let mut count := 0
  for (selection, scenario) in [fixtures, fixtures.reverse, fixtures.drop 2 ++ fixtures.take 2,
      fixtures.take 1, (fixtures.drop 2).take 1, []].zipIdx do
    let tables ← selection.zipIdx.mapM fun (fixture, unit) =>
      collect program collector.function.id collectorBinary directory fixture unit
    let input := tables.flatten
    let wanted ← oracle selection tables
    for capacity in [-1, 0, 7, 8, (wanted.length : Int) - 1, wanted.length, (wanted.length : Int) + 3] do
      runCase program allocator.function.id allocatorBinary directory s!"pack {scenario}/capacity {capacity}"
        input input.length selection.length capacity (if capacity >= wanted.length then some wanted else none)
      count := count + 1
    if scenario == 0 then
      let malformed := [input.dropLast, input ++ [0], input.set 0 (-1), input.set 0 2147483647,
        input.set 1 (-1), input.set 1 2147483647, input.set 6 0, input.set 6 2,
        input.set 8 1, input.set 9 0, input.set 9 8, input.set 10 2,
        input.set 13 0, input.set 14 (-1), input.set 15 1,
        input.set 12 input[11]!, input.set 15 2147483647]
      for (bad, index) in malformed.zipIdx do
        runCase program allocator.function.id allocatorBinary directory s!"malformed pack {index}"
          bad bad.length selection.length wanted.length none
        count := count + 1
      for (length, units) in [((-1 : Int), (selection.length : Int)), (input.length, -1),
          (input.length, 2147483647), (input.length, 0), (input.length, (selection.length : Int) - 1)] do
        runCase program allocator.function.id allocatorBinary directory "bad pack dimensions"
          input length units wanted.length none
        count := count + 1
  IO.println s!"{count} source-authenticated Core/native allocator cases: actual collector outputs from multiunit Surface fixtures, category bases, function-before-extern IDs, source-order permutations, preserved origins, empty units/packs, malformed counts/ordinals, capacity and overflow guards"
  pure 0

end Lanius.X86.Tests.LoweringAllocation

def main := Lanius.X86.Tests.LoweringAllocation.main
