import Lanius.X86.Transport.Core
import Lanius.X86.Tests.Memory
import Lanius.Extraction.CoreSynthesis.Provenance
import Lanius.Extraction.ExtractorContract

/-! Execute the actual Lanius declaration collector over materialized trees
from the extractor, and compare its source-origin rows with independently
reconstructed Surface declarations. This does not prove general correctness. -/
namespace Lanius.X86.Tests.LoweringDeclarations

open Lanius.Core Lanius.Semantics Lanius.Extraction
open Lanius.Extraction.CoreSynthesis.Program

private def unframe (emitted : String) : IO String := do
  unless emitted.startsWith ExtractorContract.modulePrefix && emitted.endsWith ExtractorContract.moduleSuffix do
    throw (IO.userError "invalid declaration extraction framing")
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

private def nodeChild (artifact : Artifact) (node index : Nat) : Option Nat := do
  let .node child ← (← artifact.parse_nodes[node]?).children[index]? | none
  pure child

private def tokenChild (node : ParseNode) (index : Nat) : Option Nat := do
  let .token token ← node.children[index]? | none
  pure token

private def description : SurfaceItemValue → Nat × Bool × Int × Int
  | .structure record => (1, record.is_public, record.name.token, -1)
  | .type_alias name visible target => (2, visible, name.token, target.parse_node)
  | .constant name visible _ _ => (3, visible, name.token, -1)
  | .function function => (4, function.is_public, function.name.token, -1)
  | .extern_function function => (5, function.is_public, function.name.token, -1)
  | .module path => (6, false, -1, path.parse_node)
  | .import_path path => (7, false, -1, path.parse_node)

-- Find a declaration by the reconstructed name-token/path identity, without
-- copying the collector's item-list or public-wrapper traversal.
private def declaration (artifact : Artifact) (kind : Nat) (name target : Int) : Option Nat := do
  let production := [0, 258, 16, 208, 11, 15, 46, 43][kind]!
  let candidates := artifact.parse_nodes.zipIdx.filter fun (node, id) =>
    node.production == production &&
      if kind == 6 then nodeChild artifact id 1 == some target.toNat
      else if kind == 7 then
        ((nodeChild artifact id 1).bind fun tail => nodeChild artifact tail 0) == some target.toNat
      else tokenChild node (if kind == 5 then 3 else 1) == some name.toNat
  let [(_, id)] := candidates | none
  pure id

private def expected (artifact : Artifact) (surface : SurfaceFile) (unit : Nat) : Option (List Int) := do
  let mut header : List Int := List.replicate 8 0
  let mut rows : List Int := []
  for item in surface.value.items do
    let (kind, visible, name, target) := description item.value
    let selected ← declaration artifact kind name target
    rows := rows ++ [(unit : Int), kind, if visible then 1 else 0, item.parse_node, selected,
      name, target, header[kind]!]
    header := (header.set 0 (header[0]! + 1)).set kind (header[kind]! + 1)
  if header[6]! != 1 then none else pure (header ++ rows)

private def fixtures : List (String × String × Bool) := [
  ("all", "module sample::all; import other; type Count = i32; pub type Buffer = [i32]; " ++
    "struct Pair { x: i32, y: bool, } pub struct Public { value: Count, } " ++
    "const N: i32 = 7; pub const M: i32 = 9; " ++
    "fn identity(value: i32) -> i32 { let local: i32 = value; return local; } " ++
    "pub fn entry() -> i32 { return 0; } " ++
    "extern \"lanius_std\" fn argc() -> i32; pub extern \"lanius_std\" fn arg_len(index: i32) -> i32;", true),
  ("empty", "module sample::empty;", true),
  ("many", "module sample::many; " ++ String.join ((List.range 24).map fun index =>
    s!"const C{index}: i32 = {index}; "), true),
  ("missing_module", "fn f() -> i32 { return 0; }", false),
  ("duplicate_module", "module first; module second;", false),
  ("import_string", "module sample; import \"other\";", false),
  ("generic_function", "module sample; fn identity<T>(value: T) -> T { return value; }", false),
  ("generic_structure", "module sample; struct Box<T> { value: T, }", false),
  ("generic_alias", "module sample; type Box<T> = T;", false),
  ("generic_external", "module sample; pub extern \"lanius_std\" fn inspect<T>(value: T) -> i32;", false)]

private def runCase (program : Program) (function : Lanius.FunctionId)
    (binary directory : System.FilePath) (label : String)
    (artifact : Artifact) (records offsets : List Int) (capacity : Nat)
    (wanted : Option (List Int)) : IO _root_.Unit := do
  let output : List Int := List.replicate (capacity + 3) 777
  let buffers := [records, offsets, output]
  let args : List Value := [
    .slice (.scalar (.signed .i32)) 0 [] 0 records.length, .signed .i32 records.length,
    .slice (.scalar (.signed .i32)) 1 [] 0 offsets.length, .signed .i32 artifact.parse_nodes.length,
    .signed .i32 artifact.tokens.length, .signed .i32 (artifact.parse_root.getD 0),
    .signed .i32 37, .slice (.scalar (.signed .i32)) 2 [] 0 output.length, .signed .i32 capacity]
  let initial := Memory.state buffers
  match evalExpr 50000 program initial (.call function (args.map Expr.value)) with
  | .done (.signed .i32 value) after =>
    let expectedValue := match wanted with | some words => words[0]! | none => -1
    unless value == expectedValue do
      throw (IO.userError s!"{label}: returned {value}, expected {expectedValue}")
    for index in [0, 1] do
      unless after.cell? index == initial.cell? index do
        throw (IO.userError s!"{label}: mutated source tree buffer {index}")
    let some (.array actual) := after.cell? 2
      | throw (IO.userError s!"{label}: output buffer disappeared")
    unless actual.drop capacity == List.replicate 3 (.signed .i32 777) do
      throw (IO.userError s!"{label}: wrote outside output capacity")
    if let some words := wanted then
      unless actual == (words ++ List.replicate (output.length - words.length) 777).map (Value.signed .i32) do
        throw (IO.userError s!"{label}: collected headers differ from reconstructed Surface origins")
  | _ => throw (IO.userError s!"{label}: declaration collector trapped or exhausted fuel")
  if ← Memory.check program function binary directory args buffers label then
    throw (IO.userError s!"{label}: unexpected native trap")

def main (arguments : List String) : IO UInt32 := do
  let [backend, extractor, modulePath, sourcePath, treePath, parserPath, directory] := arguments
    | throw (IO.userError "expected backend, extractor, collection extraction, collector source, surface_tree source, parser source, and output directory")
  let directory := System.FilePath.mk directory
  IO.FS.createDirAll directory
  let encoded ← unframe (← IO.FS.readFile modulePath)
  let sources ← ([sourcePath, treePath, parserPath] : List String).mapM fun (path : String) => do
    let bytes ← IO.FS.readBinFile path
    pure ({ path, bytes := bytes.toList.map UInt8.toNat } : SourceFile)
  let checked ← match checkCompactCoreSourcePack encoded sources with
    | .success checked => pure checked
    | .failure stage => throw (IO.userError s!"collector source validation failed: {stage}")
  let program := checked.program.core
  let some located := checkSourceFunction? checked.program ["lowering", "declarations"] "collect"
    | throw (IO.userError "missing actual declaration collector")
  let some transport := Transport.program? program located.function.id
    | throw (IO.userError "collector closure is not representable by the existing backend")
  let corePath := directory / "declarations.core"
  IO.FS.writeBinFile corePath ⟨(transport.flatMap i32Bytes).toArray⟩
  let (status, code) ← Harness.outputBytes "timeout" #["--kill-after=1s", "2s", backend, "--raw", corePath.toString]
  unless status == 0 && !code.isEmpty do throw (IO.userError s!"backend rejected declaration collector: {status}")
  let binary := directory / "declarations.bin"
  IO.FS.writeBinFile binary code
  let mut count := 0
  for (name, text, accepted) in fixtures do
    let path := directory / s!"{name}.lani"
    IO.FS.writeFile path text
    let (status, emitted) ← Harness.outputBytes "timeout" #["--kill-after=1s", "2s", extractor, path.toString]
    unless status == 0 do throw (IO.userError s!"extractor rejected declaration fixture {name}: {status}")
    let encoded ← unframe (String.fromUTF8! emitted)
    let some pack := decodeCompactArtifactPack? encoded
      | throw (IO.userError s!"could not decode declaration fixture {name}")
    let [artifact] := pack.units | throw (IO.userError s!"{name}: wrong source unit count")
    unless artifact.sources == [⟨path.toString, text.toUTF8.toList.map UInt8.toNat⟩] && checkParseArtifact artifact do
      throw (IO.userError s!"{name}: source bytes or parse tree were not authenticated")
    let oracle ← if accepted then do
        let some surface := checkSurfaceArtifact? artifact
          | throw (IO.userError s!"{name}: Surface reconstruction failed")
        let some words := expected artifact surface.reconstructed 37
          | throw (IO.userError s!"{name}: no unique source-origin headers")
        pure (some words)
      else pure none
    let (records, offsets) := materialize artifact.parse_nodes
    let required := (oracle.map List.length).getD 128
    for capacity in [0, 7, 8, required - 1, required, required + 3] do
      let wanted := if capacity >= required then oracle else none
      runCase program located.function.id binary directory s!"{name}/capacity={capacity}"
        artifact records offsets capacity wanted
      count := count + 1
    if accepted then
      let root := artifact.parse_root.getD 0
      let offset := offsets[root]!.toNat
      for bad in [records.set offset 999, records.set (offset + 3) 0,
          records.set (offset + 4) 1, records.set (offset + 5) root] do
        runCase program located.function.id binary directory s!"{name}/malformed-root"
          artifact bad offsets required none
        count := count + 1
  IO.println s!"{count} source-authenticated Core/native declaration cases: actual extracted parse trees, independently reconstructed Surface origins, all header kinds and visibility, per-kind ordinals, module/import/alias roots, generics rejection, capacity and framing"
  pure 0

end Lanius.X86.Tests.LoweringDeclarations

def main := Lanius.X86.Tests.LoweringDeclarations.main
