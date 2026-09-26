import Lanius.Compiler.DirectCoreCheck
import GeneratedDirectCore

open Lanius Lanius.Extraction Lanius.Core

def main (args : List String) : IO UInt32 := do
  let [path] := args | return 1
  let bytes ← IO.FS.readBinFile (System.FilePath.mk path)
  let sources : List SourceFile :=
    [{ path, bytes := bytes.toList.map UInt8.toNat }]
  let resolver : Lanius.Compiler.ProgramLowering.ExternalBehaviorResolver :=
    fun _ => none
  match Lanius.Compiler.DirectCoreCheck.checkTyped
      (extractedFrontend sources) sources extractedProgram extractedEntrypoint resolver with
  | .error failure =>
      IO.eprintln s!"payload constructor rejected: {repr failure}"
      return 1
  | .ok _ => pure ()
  match extractedProgram.functions with
  | [mainFunction, makeFunction] =>
      match makeFunction.body with
      | some (.returnValue (some (.enumValue typeId variantId
          [.value (.signed .i32 42)]))) =>
          let wrongMake : Function := { makeFunction with
            body := some (.returnValue (some (.enumValue typeId variantId
              [.value (.signed .i32 43)]))) }
          let wrongProgram : Program := { extractedProgram with
            functions := [mainFunction, wrongMake] }
          match Lanius.Compiler.DirectCoreCheck.checkTyped
              (extractedFrontend sources) sources wrongProgram extractedEntrypoint resolver with
          | .error (.lowering .missingBodies) =>
              IO.println "payload constructor accepted; same-type wrong payload rejected"
              return 0
          | .error failure =>
              IO.eprintln s!"wrong payload rejected at unexpected boundary: {repr failure}"
              return 1
          | .ok _ =>
              IO.eprintln "same-type wrong payload was accepted"
              return 1
      | _ =>
          IO.eprintln "unexpected make body"
          return 1
  | _ =>
      IO.eprintln "expected two functions"
      return 1
