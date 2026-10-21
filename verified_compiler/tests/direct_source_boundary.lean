import Lanius.Extraction.CurrentSourceClosure

open Lanius.Extraction.CurrentSourceClosure

-- Check the actual import graph, not only a manually filtered inventory.
private def closure (entry : String) : IO (Std.HashSet String) := do
  let mut pending := [entry]
  let mut visited : Std.HashSet String := {}
  while !pending.isEmpty do
    let path := pending.head!
    pending := pending.tail!
    if visited.contains path then continue
    visited := visited.insert path
    let source ← IO.FS.readFile ("../" ++ path)
    for line in source.splitOn "\n" do
      let line := line.trimAscii.toString
      if line.startsWith "import " then
        unless line.endsWith ";" do
          throw (IO.userError s!"{path}: unsupported import layout in boundary audit: {line}")
        let name := ((line.drop 7).dropEnd 1).toString
        pending := ("verified_compiler/src/" ++ name.replace "::" "/" ++ ".lani") :: pending
  return visited

private def samePaths (label : String) (actual : Std.HashSet String)
    (expected : List String) : IO Unit := do
  let inventory := Std.HashSet.ofList expected
  if inventory.size != expected.length then
    throw (IO.userError s!"{label}: duplicate inventory paths")
  let missing := actual.toList.filter (!inventory.contains ·)
  let extra := expected.filter (!actual.contains ·)
  unless missing.isEmpty && extra.isEmpty do
    throw (IO.userError s!"{label}: missing {missing}; extra {extra}")

def main : IO Unit := do
  let extractor ← closure "verified_compiler/src/extractor.lani"
  let compiler ← closure "verified_compiler/src/compiler.lani"
  samePaths "extractor" extractor (extractorSources.map (·.path))
  samePaths "compiler" compiler (compilerSources.map (·.path))
  let all := compiler.toList.foldl (fun paths path => paths.insert path) extractor
  samePaths "combined Lean inventory" all (compilerExtractorSources.map (·.path))
  let manifest ← IO.FS.readFile "../verified_compiler/source-closure.txt"
  samePaths "source manifest" all ((manifest.splitOn "\n").filter (!·.isEmpty))
  for path in extractor do
    if path.startsWith "verified_compiler/src/x86/" ||
        ["backend/runtime", "backend/runtime_record", "runtime/arguments",
         "runtime/heap", "runtime/io", "verified/core_transport", "verified/core_body"].any
          (fun module => path == "verified_compiler/src/" ++ module ++ ".lani") then
      throw (IO.userError s!"extractor depends on native emission or wire decoding: {path}")
  IO.println s!"source boundaries checked: {extractor.size} extractor, {compiler.size} compiler, {all.size} combined units"
