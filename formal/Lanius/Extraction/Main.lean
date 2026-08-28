import Lanius.Extraction.CoreTypingChecker
import Lanius.Extraction.EvidenceStructureChecker
import Lanius.Extraction.CompleteChecker
import Lean.Data.Json.Parser

open Lean

namespace Lanius.Extraction

def reportError (message : String) : IO UInt32 := do
  IO.eprintln message
  pure 1

def checkFile (path : System.FilePath) : IO UInt32 := do
  let contents ← IO.FS.readFile path
  let json ← match Json.parse contents with
    | .ok value => pure value
    | .error message => return ← reportError s!"invalid extraction JSON: {message}"
  let artifact ← match fromJson? json with
    | .ok value => pure value
    | .error message => return ← reportError s!"invalid extraction artifact: {message}"
  if !checkSurfaceArtifact artifact then
    reportError "source, token, parse, or Surface certificate rejected"
  else if artifact.core_program.isNone then
    IO.println "source, token, parse, and reconstructed Surface certificates accepted; no Core proposal"
    pure 0
  else if (CompleteChecker.checkArtifact? artifact).isSome then
    IO.println "source through verified source-to-Core certificates accepted"
    pure 0
  else
    reportError "source-to-Core extraction certificate rejected"

def checkPackFile (path : System.FilePath) : IO UInt32 := do
  let contents ← IO.FS.readFile path
  let json ← match Json.parse contents with
    | .ok value => pure value
    | .error message => return ← reportError s!"invalid extraction JSON: {message}"
  let pack : ArtifactPack ← match fromJson? json with
    | .ok value => pure value
    | .error message =>
        return ← reportError s!"invalid extraction artifact pack: {message}"
  if (CompleteChecker.checkPack? pack).isSome then
    IO.println "source pack through verified source-to-Core certificates accepted"
    pure 0
  else
    reportError "source-pack extraction certificate rejected"

end Lanius.Extraction

def main (arguments : List String) : IO UInt32 :=
  match arguments with
  | [path] => Lanius.Extraction.checkFile path
  | ["--pack", path] => Lanius.Extraction.checkPackFile path
  | _ => Lanius.Extraction.reportError
      "usage: lanius-check-extraction [--pack] <artifact.json>"
