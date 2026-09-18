import Lanius.X86.Transport.Core
import Lanius.Extraction.CoreSynthesis.Provenance
import Lanius.Extraction.ExtractorContract

/-! Bootstrap serialization of authenticated Core syntax. The Lanius backend,
not this tool, performs lowering, linking, runtime emission and ELF layout.
Source-to-Core still runs in Lean; this is not the final self-hosted frontend. -/
namespace Lanius.X86.Tools.Transport
open Lanius.Core Lanius.Extraction Lanius.Extraction.CoreSynthesis.Program

def main (arguments : List String) : IO UInt32 := do
  let modulePath :: output :: paths := arguments
    | throw (IO.userError "expected extracted module, output Core transport, and exact ordered sources")
  let emitted ← IO.FS.readFile modulePath
  unless emitted.startsWith ExtractorContract.modulePrefix && emitted.endsWith ExtractorContract.moduleSuffix do
    throw (IO.userError "invalid extraction framing")
  let encoded := ((emitted.drop ExtractorContract.modulePrefix.length).dropEnd ExtractorContract.moduleSuffix.length).toString
  let sources ← paths.mapM fun (path : String) => do
    let bytes ← IO.FS.readBinFile path
    pure ({ path, bytes := bytes.toList.map UInt8.toNat } : SourceFile)
  let .success checked := checkCompactCoreSourcePack encoded sources
    | throw (IO.userError "exact source/Core authentication failed")
  let some entry := checkSourceFunction? checked.program ["app", "main"] "main"
    | throw (IO.userError "missing app::main::main")
  let some words := Lanius.X86.Transport.program? checked.program.core entry.function.id
    | throw (IO.userError "unsupported Core closure or transport capacity")
  let bytes := words.flatMap Lanius.Semantics.i32Bytes
  IO.FS.writeBinFile output ⟨bytes.toArray⟩
  IO.println s!"Authenticated {sources.length} sources; serialized {words.length} Core words, including runtime identities."
  pure 0
end Lanius.X86.Tools.Transport

def main := Lanius.X86.Tools.Transport.main
