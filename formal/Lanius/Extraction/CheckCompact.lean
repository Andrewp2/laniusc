import Lanius.Extraction.SyntaxCheck.Pack

open Lanius.Extraction
open Lanius.Extraction.SyntaxCheck

def readExpectedSources (paths : List String) : IO (List SourceFile) :=
  paths.mapM fun path => do
    let contents ← IO.FS.readBinFile (System.FilePath.mk path)
    pure { path := path, bytes := contents.toList.map UInt8.toNat }

def main (paths : List String) : IO UInt32 := do
  let encoded ← (← IO.getStdin).readToEnd
  let sources ← readExpectedSources paths
  match checkCompactSourcePack encoded sources with
  | .ok _ =>
      IO.println
        "exact source identity, lexer trace, grammar derivation, and independently reconstructed Surface accepted"
      pure 0
  | .error _ =>
      IO.eprintln "compact source, lexer, grammar, or Surface certificate checking failed"
      pure 1
