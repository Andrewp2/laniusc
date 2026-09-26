import Lanius.Compiler.DirectCoreCheck
import GeneratedDirectCore

open Lanius Lanius.Extraction Lanius.Core

def main (args : List String) : IO UInt32 := do
  match args with
  | [sourcePath] =>
      let bytes ← IO.FS.readBinFile (System.FilePath.mk sourcePath)
      let sources : List SourceFile :=
        [{ path := sourcePath, bytes := bytes.toList.map UInt8.toNat }]
      let resolver : Lanius.Compiler.ProgramLowering.ExternalBehaviorResolver :=
        fun _ => none
      match Lanius.Compiler.DirectCoreCheck.checkTyped (extractedFrontend sources) sources
          extractedProgram extractedEntrypoint resolver with
      | .error failure =>
          IO.eprintln s!"nullary enum program rejected: {repr failure}"
          return 1
      | .ok _ => pure ()
      match extractedProgram.functions, extractedProgram.enumerations with
      | [function], [enumeration] =>
          match function.body, enumeration.variants with
          | some (.letLocal id type (.enumValue enumId 0 []) tail), [[], []] =>
              if enumId != enumeration.id then return 1
              let wrongBody : Stmt :=
                .letLocal id type (.enumValue enumId 1 []) tail
              let wrongProgram : Program :=
                { extractedProgram with
                  functions := [{ function with body := some wrongBody }] }
              match Lanius.Compiler.DirectCoreCheck.checkTyped (extractedFrontend sources) sources
                  wrongProgram extractedEntrypoint resolver with
              | .error (.lowering .missingBodies) =>
                  IO.println "nullary enum body accepted; valid wrong variant rejected"
                  return 0
              | .error failure =>
                  IO.eprintln s!"wrong variant rejected at unexpected boundary: {repr failure}"
                  return 1
              | .ok _ =>
                  IO.eprintln "wrong variant was accepted"
                  return 1
          | _, _ =>
              IO.eprintln "unexpected nullary enum body shape"
              return 1
      | _, _ =>
          IO.eprintln "unexpected nullary enum program shape"
          return 1
  | _ =>
      IO.eprintln "usage: direct_enum_nullary_check SOURCE"
      return 1
