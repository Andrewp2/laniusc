import Lanius.X86.Transport.Core
import Lanius.X86.Tests.Memory
import Lanius.Extraction.CoreSynthesis.Provenance
import Lanius.Extraction.ExtractorContract

open Lanius.Core Lanius.Semantics Lanius.Extraction
open Lanius.Extraction.CoreSynthesis.Program Lanius.X86.Tests

def main (arguments : List String) : IO UInt32 := do
  let backend :: modulePath :: sourcePath :: directory :: [] := arguments
    | throw (IO.userError "expected backend, extracted slices fixture, exact source, and fixture directory")
  let directory := System.FilePath.mk directory
  IO.FS.createDirAll directory
  let emitted ← IO.FS.readFile modulePath
  unless emitted.startsWith ExtractorContract.modulePrefix && emitted.endsWith ExtractorContract.moduleSuffix do
    throw (IO.userError "invalid slices pack framing")
  let encoded := ((emitted.drop ExtractorContract.modulePrefix.length).dropEnd ExtractorContract.moduleSuffix.length).toString
  let source ← IO.FS.readBinFile sourcePath
  let checked ← match checkCompactCoreSourcePack encoded [⟨sourcePath, source.toList.map UInt8.toNat⟩] with
    | .success checked => pure checked
    | .failure stage => throw (IO.userError s!"actual slices source validation failed: {stage}")
  let program := checked.program.core
  let mut results := 0
  let mut traps := 0
  let mut failures : Array String := #[]
  for name in ["read", "read_wide", "set", "compound", "read_after_index", "resolved_once", "alias", "boxed", "fields", "fill",
      "raw_read", "raw_alias", "raw_alias_reverse", "raw_alias_twice", "raw_return",
      "data_pointer", "captured_pointer", "late_slice"] do
    let some located := checkSourceFunction? checked.program ["examples", "slices"] name
      | throw (IO.userError s!"missing {name}")
    let some transport := Lanius.X86.Transport.program? program located.function.id
      | throw (IO.userError s!"unsupported {name} call closure")
    let path := directory / s!"{name}.core"
    IO.FS.writeBinFile path ⟨(transport.flatMap i32Bytes).toArray⟩
    let (status, code) ← Harness.outputBytes "timeout" #["--kill-after=1s", "2s", backend, "--raw", path.toString]
    unless status == 0 && !code.isEmpty do throw (IO.userError s!"backend rejected {name}: {status}")
    let binary := directory / s!"{name}.bin"
    IO.FS.writeBinFile binary code
    let cases : List Int := if name == "fields" then [0, -1, 2147483647, -2147483648]
      else if name == "raw_read" || name.startsWith "raw_alias" then [0, 1, 4, 5, -1, -2147483648]
      else if name == "raw_return" then [0, 5, -1, -2147483648]
      else if name == "read_wide" then [0, 1, 2, 3, 4294967296, 18446744073709551615]
      else [0, 1, 2, 3, -1, -2147483648]
    for index in cases do
      let buffer := if name == "raw_return" && index == 0 then [] else [999, 10, 20, 30, 888]
      let data : Value := if name == "raw_read" || name == "raw_return" || name.startsWith "raw_alias" then
          .slice (.scalar (.signed .i32)) 0 [] 0 buffer.length
        else .slice (.scalar (.signed .i32)) 0 [] 1 3
      let arguments := if name == "fields" then [.signed .i32 index]
        else if name == "read_wide" then [data, .unsigned .usize index.toNat]
        else if name == "set" then [data, .signed .i32 index, .signed .i32 (-2147483648)]
        else if name == "alias" then [data, data, .signed .i32 index]
        else if name == "fill" then [data, .signed .i32 index, .signed .i32 2147483647]
        else [data, .signed .i32 index]
      try
        let trapped ← Memory.check program located.function.id binary directory arguments
          [buffer] s!"{name}({index})"
        if trapped then traps := traps + 1 else results := results + 1
      catch error =>
        let message := error.toString
        IO.eprintln message
        failures := failures.push message
  unless failures.isEmpty do
    throw (IO.userError s!"{failures.size} Core/native slice cases failed; {results} results and {traps} bounds traps agreed")
  IO.println s!"{results} Core/native slice/field cases and {traps} matching bounds traps: packed i32 addressing, nonzero-offset data pointers, raw-parts descriptors on valid backing blocks, negative lengths, aggregate-return trap ABI, aliasing, compound assignment ordering, index effects, full-width indices, nested field places, buffers/canaries, and caller ABI state"
  pure 0
