import Lanius.Compiler.DirectCoreCheck
import GeneratedDirectCore

open Lanius Lanius.Extraction Lanius.Core

def checkDirect (sources : List SourceFile) (program : Program)
    (entrypoint : FunctionId) :
    Lanius.Compiler.DirectCoreCheck.TypedFailure → IO UInt32 := fun expected => do
  match Lanius.Compiler.DirectCoreCheck.checkTyped
      (extractedFrontend sources) sources program entrypoint (fun _ => none) with
  | .error failure =>
      if failure == expected then
        IO.println s!"typed direct checker rejected as expected: {repr failure}"
        return 0
      IO.eprintln s!"unexpected typed direct rejection: {repr failure}"
      return 1
  | .ok _ =>
      IO.eprintln "typed direct checker accepted a deliberate mismatch"
      return 1

def main (args : List String) : IO UInt32 := do
  let (mode, paths) := match args with
    | "--wrong-entry" :: paths => (1, paths)
    | "--mutate-return" :: paths => (2, paths)
    | paths => (0, paths)
  if paths.isEmpty then
    IO.eprintln "usage: direct_typed_core_check [--wrong-entry|--mutate-return] SOURCE..."
    return 1
  let sources ← paths.mapM fun path => do
    let bytes ← IO.FS.readBinFile (System.FilePath.mk path)
    let source : SourceFile :=
      { path, bytes := bytes.toList.map UInt8.toNat }
    pure source
  if mode == 1 then
    return ← checkDirect sources extractedProgram (extractedEntrypoint + 1) .entrypoint
  if mode == 2 then
    match extractedProgram.functions with
    | [function] =>
        let wrong : Function := { function with
          body := some (.returnValue (some (.value (.signed .i32 43)))) }
        let wrongProgram : Program :=
          { extractedProgram with functions := [wrong] }
        return ← checkDirect sources wrongProgram extractedEntrypoint
          (.lowering .missingBodies)
    | _ =>
        IO.eprintln "return mutation requires a one-function fixture"
        return 1
  match Lanius.Compiler.DirectCoreCheck.checkTyped
      (extractedFrontend sources) sources extractedProgram extractedEntrypoint
      (fun _ => none) with
  | .error failure =>
      IO.eprintln s!"typed source-to-Core rejected: {repr failure}"
      return 1
  | .ok checked =>
      let _ := Lanius.Compiler.DirectCoreCheck.checked_typed_source_and_program checked
      let _ := Lanius.Compiler.DirectCoreCheck.typed_emitted_executable_wellFormed checked
      IO.println "direct Lean frontend, Core, and entrypoint accepted without compact artifact"
      return 0
