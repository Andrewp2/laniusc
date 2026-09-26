import Lanius.Compiler.FrontendBoundary
import GeneratedDirectCore

open Lanius.Extraction

def main (args : List String) : IO UInt32 := do
  if args.isEmpty then
    IO.eprintln "usage: direct_typed_frontend_check SOURCE..."
    return 1
  let sources ← args.mapM fun path => do
    let bytes ← IO.FS.readBinFile (System.FilePath.mk path)
    let source : SourceFile :=
      { path, bytes := bytes.toList.map UInt8.toNat }
    pure source
  match Lanius.Compiler.FrontendBoundary.checkTyped
      (extractedFrontend sources) sources with
  | .error failure =>
      IO.eprintln s!"emitted typed frontend rejected: {repr failure}"
      return 1
  | .ok _ =>
      IO.println "emitted typed frontend accepted against source bytes"
      return 0
