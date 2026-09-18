import Lanius.X86.Transport.Core
import Lanius.X86.Tests.Memory
import Lanius.Extraction.CoreSynthesis.Provenance
import Lanius.Extraction.ExtractorContract

/-! Actual source → declaration collector → module/import path materializer.
The oracle uses independently reconstructed Surface paths and plainPath?,
not a second walk over the implementation's grammar productions. -/
namespace Lanius.X86.Tests.LoweringModules

open Lanius.Core Lanius.Semantics Lanius.Extraction

private def unframe (emitted : String) : IO String := do
  unless emitted.startsWith ExtractorContract.modulePrefix && emitted.endsWith ExtractorContract.moduleSuffix do
    throw (IO.userError "invalid module-path extraction framing")
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

private def fixtures : List (String × String × Bool × Bool) := [
  ("left", "module pkg::left; import pkg::right; import pkg::right; import solo; fn f() -> i32 { return 0; }", true, true),
  ("right", "module pkg::right; import pkg::left; pub type Word = i32;", true, true),
  ("solo", "module solo; import pkg::right;", true, true),
  ("deep", "module a:: /* original spelling */ ab::_same::A0; import a::ab::_same::A0; import missing;", true, true),
  ("boundaries", "module ab::c; import a::bc; import A::bc; import ab::c;", true, true),
  ("empty", "module no_imports;", true, true),
  ("late_import", "module late_import; const N: i32 = 0; import pkg::left;", true, true),
  ("generic_module", "module generic<i32>;", true, false),
  ("generic_import", "module good; import other::nested<i32>;", true, false),
  ("late_module", "const N: i32 = 0; module late;", true, false),
  ("string_import", "module good; import \"other\";", false, false),
  ("duplicate_module", "module first; module second;", false, false)]

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
    (binary directory : System.FilePath) (artifact : Artifact) (unit : Nat)
    (accepted : Bool) : IO (Option (List Int)) := do
  let (records, offsets) := materialize artifact.parse_nodes
  let capacity := 8 + artifact.tokens.length * 8
  let output : List Int := List.replicate (capacity + 3) 777
  let buffers := [records, offsets, output]
  let args : List Value := [
    .slice (.scalar (.signed .i32)) 0 [] 0 records.length, .signed .i32 records.length,
    .slice (.scalar (.signed .i32)) 1 [] 0 offsets.length, .signed .i32 offsets.length,
    .signed .i32 artifact.tokens.length, .signed .i32 (artifact.parse_root.getD 0), .signed .i32 unit,
    .slice (.scalar (.signed .i32)) 2 [] 0 output.length, .signed .i32 capacity]
  let found ← match evalExpr 30000 program (Memory.state buffers) (.call function (args.map Expr.value)) with
    | .done (.signed .i32 result) after => do
      unless decide (result >= 0) == accepted do throw (IO.userError s!"collector acceptance differs for unit {unit}")
      if result < 0 then pure none else do
        let some (.array values) := after.cell? 2 | throw (IO.userError "collector missing output")
        let some words := values.mapM (fun value => match value with | .signed .i32 value => some value | _ => none)
          | throw (IO.userError "collector non-i32 output")
        pure (some (words.take (8 + result.toNat * 8)))
    | _ => throw (IO.userError "collector trapped or exhausted")
  if ← Memory.check program function binary directory args buffers s!"collector unit {unit}" then
    throw (IO.userError "unexpected collector native trap")
  pure found

-- The collector's rows are real outputs. Expected path segments are obtained
-- from checked Surface values, whose name text is compared with source bytes.
private def oracle (artifact : Artifact) (table : List Int) (unit : Nat) : IO (Option (List Int)) := do
  let some checked := checkSurfaceArtifact? artifact | throw (IO.userError "fixture Surface validation failed")
  if (ArtifactPackContextChecker.declaredModulePath? checked.surface).isNone then return none
  let mut output : List Int := []
  let mut paths : Nat := 0
  let mut segments : Nat := 0
  for ((located, plain), row) in (checked.reconstructed.value.items.zip checked.surface.items).zipIdx do
    let selected : Option (SurfacePath × Lanius.Surface.Path × Nat) := match located.value, plain with
      | .module path, .module plain => some (path, plain, 6)
      | .import_path path, .importPath plain => some (path, plain, 7)
      | _, _ => none
    if let some (path, plain, kind) := selected then
      let some names := Lanius.Declarations.plainPath? plain | return none
      let original := (table.drop (8 + row * 8)).take 8
      unless original[0]! == unit && original[1]! == kind && original[3]! == located.parse_node &&
          original[6]! == path.parse_node && names.length == path.value.segments.length do
        throw (IO.userError "collector path origin differs from Surface")
      output := output ++ original ++ [(names.length : Int)]
      for (segment, name) in path.value.segments.zip names do
        let some token := artifact.tokens[segment.name.token]? | throw (IO.userError "Surface name token missing")
        let some source := artifact.sources[token.span.file]? | throw (IO.userError "Surface source missing")
        unless segment.name.text == name &&
            ((source.bytes.drop token.span.start).take (token.span.finish - token.span.start)) == name.toUTF8.toList.map UInt8.toNat do
          throw (IO.userError "Surface spelling differs from exact source span")
        output := output ++ [(segment.parse_node : Int), segment.name.token, token.span.start,
          token.span.finish - token.span.start]
        segments := segments + 1
      paths := paths + 1
  pure (some ([(unit : Int), paths, segments, output.length + 4] ++ output))

private def runCase (program : Program) (function : Lanius.FunctionId)
    (binary directory : System.FilePath) (label : String)
    (source tokens records offsets table : List Int) (sourceLength tokenCount tableLength capacity : Int)
    (wanted : Option (List Int)) : IO Unit := do
  let output : List Int := List.replicate (capacity.toNat + 3) 777
  let buffers := [source, tokens, records, offsets, table, output]
  let args : List Value := [
    .slice (.scalar (.signed .i32)) 1 [] 0 tokens.length, .signed .i32 tokenCount, .signed .i32 sourceLength,
    .slice (.scalar (.signed .i32)) 2 [] 0 records.length, .signed .i32 records.length,
    .slice (.scalar (.signed .i32)) 3 [] 0 offsets.length, .signed .i32 offsets.length,
    .slice (.scalar (.signed .i32)) 4 [] 0 table.length, .signed .i32 tableLength,
    .slice (.scalar (.signed .i32)) 5 [] 0 output.length, .signed .i32 capacity]
  let initial := Memory.state buffers
  match evalExpr 30000 program initial (.call function (args.map Expr.value)) with
  | .done (.signed .i32 result) after =>
    unless result == (wanted.map fun words => (words.length : Int)).getD (-1) do
      throw (IO.userError s!"{label}: wrong result {result}")
    for id in List.range 5 do
      unless after.cell? id == initial.cell? id do throw (IO.userError s!"{label}: modified input buffer {id}")
    let some (.array actual) := after.cell? 5 | throw (IO.userError s!"{label}: missing output")
    unless actual.drop capacity.toNat == List.replicate 3 (.signed .i32 777) do
      throw (IO.userError s!"{label}: wrote past capacity")
    if let some expected := wanted then
      unless actual == (expected ++ List.replicate (output.length - expected.length) 777).map (Value.signed .i32) do
        throw (IO.userError s!"{label}: paths/spans differ from Surface/plainPath?")
  | _ => throw (IO.userError s!"{label}: trapped or exhausted")
  if ← Memory.check program function binary directory args buffers label then
    throw (IO.userError s!"{label}: unexpected native trap")

def main (arguments : List String) : IO UInt32 := do
  let backend :: extractor :: modulePath :: directory :: sourcePaths := arguments
    | throw (IO.userError "expected backend, extractor, source extraction, output directory, and exact source closure")
  unless sourcePaths.length == 5 do throw (IO.userError "expected module/declaration/tree/parser/token sources")
  let directory := System.FilePath.mk directory
  IO.FS.createDirAll directory
  let encoded ← unframe (← IO.FS.readFile modulePath)
  let sources ← sourcePaths.mapM fun (path : String) => do
    let bytes ← IO.FS.readBinFile path
    pure ({ path, bytes := bytes.toList.map UInt8.toNat } : SourceFile)
  let checked ← match CoreSynthesis.Program.checkCompactCoreSourcePack encoded sources with
    | .success checked => pure checked
    | .failure stage => throw (IO.userError s!"module materializer source validation failed: {stage}")
  let program := checked.program.core
  let some collector := CoreSynthesis.Program.checkSourceFunction? checked.program ["lowering", "declarations"] "collect"
    | throw (IO.userError "missing actual collector")
  let some modules := CoreSynthesis.Program.checkSourceFunction? checked.program ["lowering", "modules"] "materialize"
    | throw (IO.userError "missing actual module materializer")
  let collectorBinary ← compile backend directory program collector.function.id "collector"
  let moduleBinary ← compile backend directory program modules.function.id "modules"
  let mut fixturePaths : List System.FilePath := []
  for (name, text, _, _) in fixtures do
    let path := directory / s!"{name}.lani"
    IO.FS.writeFile path text
    fixturePaths := fixturePaths ++ [path]
  let (status, emitted) ← Harness.outputBytes "timeout"
    (#["--kill-after=1s", "2s", extractor] ++ (fixturePaths.map System.FilePath.toString).toArray)
  unless status == 0 do throw (IO.userError s!"extractor rejected actual multiunit path fixtures: {status}")
  let encoded ← unframe (String.fromUTF8! emitted)
  let some pack := decodeCompactArtifactPack? encoded | throw (IO.userError "fixture pack did not decode")
  unless pack.units.length == fixtures.length do throw (IO.userError "wrong fixture source count")
  let mut count := 0
  for ((((name, text, collectorAccepted, materializerAccepted), path), artifact), unit) in
      ((fixtures.zip fixturePaths).zip pack.units).zipIdx do
    unless artifact.sources == [⟨path.toString, text.toUTF8.toList.map UInt8.toNat⟩] && checkParseArtifact artifact do
      throw (IO.userError "fixture source/parse binding failed")
    let found ← collect program collector.function.id collectorBinary directory artifact unit collectorAccepted
    if let some table := found then
      let wanted ← oracle artifact table unit
      unless wanted.isSome == materializerAccepted do throw (IO.userError s!"Surface oracle differs for {name}")
      let required := (wanted.map List.length).getD 80
      let source := text.toUTF8.toList.map (fun byte => (byte.toNat : Int))
      let tokens := artifact.tokens.flatMap fun token => [(token.kind : Int), token.span.start, token.span.finish]
      let (records, offsets) := materialize artifact.parse_nodes
      for capacity in [-1, 0, 3, 4, (required : Int) - 1, required, (required : Int) + 3] do
        runCase program modules.function.id moduleBinary directory s!"{name}/capacity {capacity}"
          source tokens records offsets table source.length artifact.tokens.length table.length capacity
          (if capacity >= required then wanted else none)
        count := count + 1
      if unit == 0 then
        let some expected := wanted | throw (IO.userError "first fixture lacks expected paths")
        let segment := expected[13]!.toNat
        let token := expected[14]!.toNat
        let root := table[14]!.toNat
        let rootOffset := offsets[root]!.toNat
        let segmentOffset := offsets[segment]!.toNat
        let badTables := [table.dropLast, table ++ [0], table.set 0 (-1), table.set 0 2147483647,
          table.set 6 0, table.set 6 2, table.set 7 (-1), table.set 7 2147483647,
          table.set 9 7, table.set 10 1, table.set 13 0, table.set 14 (-1), table.set 15 1,
          table.set 16 99, table.set 23 99]
        for (bad, index) in badTables.zipIdx do
          runCase program modules.function.id moduleBinary directory s!"malformed table {index}"
            source tokens records offsets bad source.length artifact.tokens.length bad.length required none
          count := count + 1
        let badTokens := [tokens.set (token * 3) 2, tokens.set (token * 3 + 1) (-1),
          tokens.set (token * 3 + 2) tokens[token * 3 + 1]!, tokens.set (token * 3 + 2) (source.length + 1)]
        for (bad, index) in badTokens.zipIdx do
          runCase program modules.function.id moduleBinary directory s!"malformed token span {index}"
            source bad records offsets table source.length artifact.tokens.length table.length required none
          count := count + 1
        for (bad, index) in [records.set rootOffset 48, records.set segmentOffset 49,
            records.set (rootOffset + 5) root, records.set (segmentOffset + 5) artifact.tokens.length].zipIdx do
          runCase program modules.function.id moduleBinary directory s!"malformed path node {index}"
            source tokens bad offsets table source.length artifact.tokens.length table.length required none
          count := count + 1
        for (sourceLength, tokenCount, tableLength) in [((-1 : Int), (artifact.tokens.length : Int), (table.length : Int)),
            (source.length, -1, table.length), (source.length, 715827883, table.length),
            (source.length, artifact.tokens.length, -1)] do
          runCase program modules.function.id moduleBinary directory "bad dimensions"
            source tokens records offsets table sourceLength tokenCount tableLength required none
          count := count + 1
  IO.println s!"{count} source-authenticated Core/native module-path cases plus {fixtures.length} collector cases: exact Surface/plainPath? spellings and segment origins, module/import order and duplicates, generic/string/late-module rejection, capacities and malformed metadata"
  pure 0

end Lanius.X86.Tests.LoweringModules

def main := Lanius.X86.Tests.LoweringModules.main
