import Lanius.Compiler.DirectCoreCheck
import GeneratedDirectCore

open Lanius Lanius.Extraction Lanius.Core

def main (args : List String) : IO UInt32 := do
  let [sourcePath] := args | return 1
  let bytes ← IO.FS.readBinFile (System.FilePath.mk sourcePath)
  let sources : List SourceFile :=
    [{ path := sourcePath, bytes := bytes.toList.map UInt8.toNat }]
  let [function] := extractedProgram.functions | return 1
  let some (.letLocal id type initializer
      (.returnValue (some (.matchValue scrutinee
        [first, (secondPattern, _)])))) := function.body | return 1
  let wrongBody : Stmt :=
    .letLocal id type initializer
      (.returnValue (some (.matchValue scrutinee
        [first, (secondPattern, .value (.signed .i32 3))])))
  let wrongProgram : Program :=
    { extractedProgram with
      functions := [{ function with body := some wrongBody }] }
  match Lanius.Compiler.DirectCoreCheck.checkTyped
      (extractedFrontend sources) sources wrongProgram extractedEntrypoint
      (fun _ => none) with
  | .error (.lowering .missingBodies) =>
      IO.println "enum match accepts source body and rejects a same-type changed arm"
      return 0
  | .error failure =>
      IO.eprintln s!"wrong match arm rejected at unexpected boundary: {repr failure}"
      return 1
  | .ok _ =>
      IO.eprintln "wrong match arm was accepted"
      return 1
