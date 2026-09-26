import Lanius.Compiler.FrontendBoundary
import Lanius.Compiler.CoreBoundary
import Lanius.Compiler.DirectCoreCheck
import GeneratedDirectCore

open Lanius Lanius.Extraction

def main (args : List String) : IO UInt32 := do
  match args with
  | [mainPath, auxiliaryPath] =>
      let mainBytes ← IO.FS.readBinFile (System.FilePath.mk mainPath)
      let auxiliaryBytes ← IO.FS.readBinFile (System.FilePath.mk auxiliaryPath)
      let sources : List SourceFile :=
        [{ path := mainPath, bytes := mainBytes.toList.map UInt8.toNat },
         { path := auxiliaryPath, bytes := auxiliaryBytes.toList.map UInt8.toNat }]
      match Lanius.Compiler.FrontendBoundary.checkTyped (extractedFrontend sources) sources with
      | .error failure =>
          IO.eprintln s!"enum frontend rejected: {repr failure}"
          return 1
      | .ok frontend =>
          match Lanius.Compiler.CoreBoundary.checkInput
              (Lanius.Compiler.FrontendBoundary.typedCoreInput frontend) extractedProgram with
          | .error failure =>
              IO.eprintln s!"multimodule enum boundary rejected: {repr failure}"
              return 1
          | .ok _ =>
              match Lanius.Compiler.DirectCoreCheck.checkTyped (extractedFrontend sources) sources
                  extractedProgram extractedEntrypoint (fun _ => none) with
              | .error failure =>
                  IO.eprintln s!"multimodule enum source-to-Core rejected: {repr failure}"
                  return 1
              | .ok _ =>
                  match extractedProgram.structures, extractedProgram.enumerations with
                  | [mainPayload, auxiliaryPayload], [coreEnum] =>
                      if mainPayload.id == auxiliaryPayload.id then
                        IO.eprintln "fixture has duplicate Payload IDs"
                        return 1
                      let wrongEnum : Core.EnumDecl :=
                        { coreEnum with variants := [[], [.structure mainPayload.id]] }
                      let wrongProgram : Core.Program :=
                        { extractedProgram with enumerations := [wrongEnum] }
                      match Lanius.Compiler.CoreBoundary.checkInput
                          (Lanius.Compiler.FrontendBoundary.typedCoreInput frontend) wrongProgram with
                      | .error .enumShapes =>
                          IO.println "auxiliary enum resolves its own Payload; main Payload is rejected"
                          return 0
                      | _ =>
                          IO.eprintln "wrong-module payload was not rejected as an enum shape"
                          return 1
                  | _, _ =>
                      IO.eprintln "expected two structures and one enum"
                      return 1
  | _ =>
      IO.eprintln "usage: direct_enum_multimodule_check MAIN AUXILIARY"
      return 1
