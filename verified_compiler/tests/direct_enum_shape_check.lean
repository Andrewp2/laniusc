import Lanius.Compiler.FrontendBoundary
import Lanius.Compiler.CoreBoundary
import Lanius.Compiler.TypeLoweringCheck
import Lanius.Compiler.BodyCheck
import GeneratedDirectCore

open Lanius Lanius.Extraction

def checkShape (sourcePath : String) (wrongPayload : Bool) : IO UInt32 := do
      let bytes ← IO.FS.readBinFile (System.FilePath.mk sourcePath)
      let source : SourceFile :=
        { path := sourcePath, bytes := bytes.toList.map UInt8.toNat }
      match Lanius.Compiler.FrontendBoundary.checkTyped
          (extractedFrontend [source]) [source] with
      | .error failure =>
          IO.eprintln s!"enum frontend rejected: {repr failure}"
          return 1
      | .ok frontend =>
          if wrongPayload then
            match extractedProgram.enumerations with
            | [enumeration] =>
                let wrongEnum : Core.EnumDecl :=
                  { enumeration with variants := [[.scalar .bool], []] }
                let wrongProgram : Core.Program :=
                  { extractedProgram with enumerations := [wrongEnum] }
                match Lanius.Compiler.CoreBoundary.checkInput
                    (Lanius.Compiler.FrontendBoundary.typedCoreInput frontend)
                    wrongProgram with
                | .error .enumShapes =>
                    IO.println "enum shape check rejects different payload types"
                    return 0
                | _ =>
                    IO.eprintln "wrong payload was not rejected as an enum shape"
                    return 1
            | _ =>
                IO.eprintln "expected one enum for wrong-payload check"
                return 1
          match Lanius.Compiler.CoreBoundary.checkInput
              (Lanius.Compiler.FrontendBoundary.typedCoreInput frontend) extractedProgram with
          | .error failure =>
              IO.eprintln s!"enum declaration boundary rejected: {repr failure}"
              IO.eprintln s!"catalog: {repr (frontend.catalog.catalog.headers.map (fun h => (h.kind, h.declaration)))}"
              IO.eprintln s!"Core types: {repr (extractedProgram.enumerations.map (·.id))}"
              IO.eprintln s!"Core functions: {repr (extractedProgram.functions.map (·.id))}"
              return 1
          | .ok boundary =>
              let pack := Lanius.Compiler.FrontendBoundary.typedFrontendPack
                frontend.frontend
              let surfaceEnums := pack.files.flatMap fun file =>
                file.contents.items.filterMap fun item =>
                  match item with
                  | .enumeration declaration => some declaration
                  | _ => none
              match surfaceEnums, extractedProgram.enumerations with
              | [surfaceEnum], [coreEnum] =>
                  let context := Lanius.Compiler.CoreBoundary.enumContextInput
                    (Lanius.Compiler.FrontendBoundary.typedCoreInput frontend)
                    extractedProgram boundary.declarations
                  if context.variants.length != coreEnum.variants.length ||
                      context.variantConstructors.length != coreEnum.variants.length ||
                      context.monomorphization.resolveNominal coreEnum.id [] [] !=
                        some (.enumeration coreEnum.id) then
                    IO.eprintln "enum context tables do not match direct Core"
                    IO.eprintln s!"variant rows: {context.variants.length}, constructor rows: {context.variantConstructors.length}, Core variants: {coreEnum.variants.length}"
                    IO.eprintln s!"nominal resolution: {repr (context.monomorphization.resolveNominal coreEnum.id [] [])}"
                    return 1
                  let sourceType : Surface.TypeExpr :=
                    .path [.mk surfaceEnum.name []]
                  if (Lanius.Compiler.TypeLoweringCheck.check context sourceType
                      (.enumeration coreEnum.id)).isNone then
                    IO.eprintln "source enum type does not ground to direct Lean Core"
                    return 1
                  let sourceLocal : List Surface.Stmt :=
                    [.letLocal "value" (some sourceType) none]
                  let coreLocal : Core.Stmt :=
                    .letUninitialized 0 (.enumeration coreEnum.id) .skip
                  if (Lanius.Compiler.BodyCheck.checkStmts context 0
                      sourceLocal coreLocal).isNone then
                    IO.eprintln "annotated enum local does not lower to direct Lean Core"
                    return 1
                  let wrongLocal : Core.Stmt :=
                    .letUninitialized 0 (.structure coreEnum.id) .skip
                  if (Lanius.Compiler.BodyCheck.checkStmts context 0
                      sourceLocal wrongLocal).isSome then
                    IO.eprintln "annotated enum local accepted the wrong Core kind"
                    return 1
                  IO.println "enum declaration, payloads, and context match direct Lean Core"
                  return 0
              | _, _ =>
                  IO.eprintln "expected one source enum and one Core enum"
                  return 1

def main (args : List String) : IO UInt32 := do
  match args with
  | [sourcePath] => checkShape sourcePath false
  | ["--wrong-payload", sourcePath] => checkShape sourcePath true
  | _ =>
      IO.eprintln "usage: direct_enum_shape_check [--wrong-payload] SOURCE"
      return 1
