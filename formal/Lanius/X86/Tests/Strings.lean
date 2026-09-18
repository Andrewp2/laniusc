import Lanius.X86.Transport.Core
import Lanius.X86.Tests.Memory
import Lanius.Extraction.CoreSynthesis.Provenance
import Lanius.Extraction.ExtractorContract

open Lanius.Core Lanius.Semantics Lanius.Extraction
open Lanius.Extraction.CoreSynthesis.Program Lanius.X86.Tests

def main (arguments : List String) : IO UInt32 := do
  let [backend, modulePath, sourcePath, directory] := arguments
    | throw (IO.userError "expected backend, string extraction, exact source, and output directory")
  let directory := System.FilePath.mk directory
  IO.FS.createDirAll directory
  let emitted ← IO.FS.readFile modulePath
  unless emitted.startsWith ExtractorContract.modulePrefix && emitted.endsWith ExtractorContract.moduleSuffix do
    throw (IO.userError "invalid string fixture framing")
  let encoded := ((emitted.drop ExtractorContract.modulePrefix.length).dropEnd ExtractorContract.moduleSuffix.length).toString
  let source ← IO.FS.readBinFile sourcePath
  let checked ← match checkCompactCoreSourcePack encoded [⟨sourcePath, source.toList.map UInt8.toNat⟩] with
    | .success checked => pure checked
    | .failure stage => throw (IO.userError s!"string source validation failed: {stage}")
  let program := checked.program.core
  let mut results := 0
  let mut traps := 0
  let mut rejected := 0
  for name in ["literal", "constant", "empty", "empty_constant", "forward", "literal_word", "constant_word", "staged", "input_word",
      "fresh_pointer", "fresh_empty", "late", "self_before_set", "compound_before_set", "field_before_set", "late_string", "late_pair", "reset_each_iteration"] do
    let some located := checkSourceFunction? checked.program ["examples", "strings"] name
      | throw (IO.userError s!"missing {name}")
    let some transport := Lanius.X86.Transport.program? program located.function.id
      | throw (IO.userError s!"unsupported string closure {name}")
    let path := directory / s!"{name}.core"
    IO.FS.writeBinFile path ⟨(transport.flatMap i32Bytes).toArray⟩
    let (status, code) ← Harness.outputBytes "timeout" #["--kill-after=1s", "2s", backend, "--raw", path.toString]
    unless status == 0 && !code.isEmpty do throw (IO.userError s!"backend rejected {name}: {status}")
    let binary := directory / s!"{name}.bin"
    IO.FS.writeBinFile binary code
    for index in [-1, 0, 1, 2, 2147483647] do
      let args := if name == "input_word" then [.string "Aλ🙂\x00", .signed .i32 index]
        else [.signed .i32 index]
      if ← Memory.check program located.function.id binary directory args [] s!"{name}({index})" then
        traps := traps + 1
      else results := results + 1
    let constantStart := 6 + (program.structures.map fun record => 2 + record.fields.length).foldl (· + ·) 0
    let malformedString := if name == "constant" then
        [transport.set (constantStart + 2) (-1), transport.set (constantStart + 2) 2147483647,
          transport.set (constantStart + 3) 256]
      else []
    for bad in [transport.dropLast, transport ++ [0]] ++ malformedString do
      IO.FS.writeBinFile path ⟨(bad.flatMap i32Bytes).toArray⟩
      let (status, bytes) ← Harness.outputBytes "timeout" #["--kill-after=1s", "2s", backend, "--raw", path.toString]
      unless status == 7 && bytes.isEmpty do throw (IO.userError s!"malformed {name} published code")
      rejected := rejected + 1
  IO.println s!"{results} Core/native string/local results, {traps} classified bounds/uninitialized traps, {rejected} malformed rejections: exact UTF-8 and embedded NUL bytes, empty strings, constants, branching aggregate returns, stack arguments, raw i32 views, delayed initialization, RHS-before-initialization, compound/field reads, loop-scope flag reset, input preservation and caller ABI"
  pure 0
