import Lanius.X86.Transport.Core
import Lanius.X86.Tests.Memory
import Lanius.Extraction.CoreSynthesis.Provenance
import Lanius.Extraction.ExtractorContract

/-! Compile the actual extractor's complete raw-lexer call graph in Lanius.
The Core interpreter is the differential oracle; no test-generated lexer or
replacement frontend is passed to the backend. -/
open Lanius.Core Lanius.Semantics Lanius.Extraction
open Lanius.Extraction.CoreSynthesis.Program Lanius.X86.Tests

def main (arguments : List String) : IO UInt32 := do
  let backend :: modulePath :: directory :: paths := arguments
    | throw (IO.userError "expected backend, exact self-extraction, directory, and source paths")
  let directory := System.FilePath.mk directory
  IO.FS.createDirAll directory
  let emitted ← IO.FS.readFile modulePath
  unless emitted.startsWith ExtractorContract.modulePrefix && emitted.endsWith ExtractorContract.moduleSuffix do
    throw (IO.userError "invalid extractor pack framing")
  let encoded := ((emitted.drop ExtractorContract.modulePrefix.length).dropEnd ExtractorContract.moduleSuffix.length).toString
  let sources ← paths.mapM fun (path : String) => do
    let contents ← IO.FS.readBinFile path
    pure ({ path, bytes := contents.toList.map UInt8.toNat } : SourceFile)
  let .success checked := checkCompactCoreSourcePack encoded sources
    | throw (IO.userError "exact extractor sources failed validation")
  let program := checked.program.core
  let inputs := ["", "a", "alpha_9 + 123;", " \t\r\n", "0x12ab 0b101 0o77", "123.456e-2",
    "\"hi\\nthere\"", "'x' '\\n'", "// tail comment", "/* outer /* inner */ end */",
    "fn f(a: i32) -> i32 { return a << 2; }", "\"unterminated", "/* unterminated", "0x", "@", "λ"]
  let mut results := 0
  for name in ["scan_one", "lex_into"] do
    let some located := checkSourceFunction? checked.program ["verified", "raw_lexer"] name
      | throw (IO.userError s!"missing actual raw lexer {name}")
    let some transport := Lanius.X86.Transport.program? program located.function.id
      | throw (IO.userError s!"unsupported raw lexer call closure {name}")
    let path := directory / s!"{name}.core"
    IO.FS.writeBinFile path ⟨(transport.flatMap i32Bytes).toArray⟩
    let (status, code) ← Harness.outputBytes "timeout" #["--kill-after=1s", "2s", backend, "--raw", path.toString]
    unless status == 0 && !code.isEmpty do throw (IO.userError s!"backend rejected real raw lexer {name}: {status}")
    let binary := directory / s!"{name}.bin"
    IO.FS.writeBinFile binary code
    IO.println s!"{name}: {transport.length} Core words, {transport[5]!} linked functions, {code.size} x86 bytes"
    for (input, sample) in inputs.zipIdx do
      let source := input.toUTF8.toList.map fun byte => (byte.toNat : Int)
      let buffer := [999] ++ source ++ [888]
      let sourceValue : Value := .slice (.scalar (.signed .i32)) 0 [] 1 source.length
      let cases := if name == "scan_one" then [0, source.length / 2, source.length] else [0, 1, 32]
      for index in cases do
        let records : List Int := List.replicate (index * 3 + 8) (-333)
        let arguments := if name == "scan_one" then
            [sourceValue, .signed .i32 source.length, .signed .i32 index]
          else [sourceValue, .signed .i32 source.length,
            .slice (.scalar (.signed .i32)) 1 [] 2 (index * 3 + 4), .signed .i32 index]
        let trapped ← Memory.check program located.function.id binary directory arguments [buffer, records]
          s!"raw lexer {name}, source {sample}, argument {index}"
        if trapped then throw (IO.userError "well-bounded lexer invocation trapped instead of returning a classified result")
        results := results + 1
  IO.println s!"{results} actual raw-lexer Core/native comparisons: exact aggregate status/count/error results and token-buffer writes, malformed tokens, capacity exhaustion, nonzero slice origins, untouched source/output lanes, canaries, and ABI state"
  pure 0
