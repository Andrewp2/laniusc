import Lanius.Extraction.CurrentSourceClosure
import Lanius.Compiler.SourcePackCheck
import Lanius.Compiler.ImportSynthesis

open Lanius.Extraction
open Lanius.Extraction.CurrentSourceClosure
open Lanius.Extraction.SyntaxCheck

def embeddedSourcesFresh (expectedSources : List SourceFile) : IO Bool := do
  for source in expectedSources do
    let current ← try
      IO.FS.readBinFile (System.FilePath.mk source.path)
    catch _ =>
      return false
    if current.toList.map UInt8.toNat != source.bytes then
      return false
  return true

/-! Independent checker entrypoint for the current extractor's combined
    frontend/emitter compact artifact.  Source bytes are read from the
    checked checkout by `CurrentSourceClosure`; the compact payload remains
    untrusted input and is accepted only through the existing decoder,
    lexer, parser, and Surface checks. -/

def report {encoded : String} {expectedSources : List SourceFile}
    (kind : String)
    (result : Unit → Except PackCheckStage (CheckedSourcePack encoded expectedSources)) : IO UInt32 := do
  unless ← embeddedSourcesFresh expectedSources do
    IO.eprintln s!"current {kind} source closure rejected: embedded source bytes are stale; rebuild Lanius.Extraction.CurrentSourceClosure"
    return 1
  match result () with
  | .ok checked =>
      let pack := Lanius.Compiler.SourcePackCheck.declaredPack checked
      if (Lanius.Compiler.SourcePackCheck.check checked).isNone then
        IO.eprintln s!"current {kind} source closure rejected: duplicate or invalid module identities"
        pure 1
      else if (Lanius.Compiler.ImportSynthesis.check pack).isNone then
        IO.eprintln s!"current {kind} source closure rejected: unresolved or invalid imports"
        pure 1
      else
        IO.println s!"current {kind} source closure accepted: {checked.compact.pack.units.length} units, exact bytes, reconstructed Surface, and closed imports"
        pure 0
  | .error failure =>
      IO.eprintln s!"current {kind} source closure rejected: {repr failure}"
      pure 1

def main (args : List String) : IO UInt32 := do
  let encoded ← (← IO.getStdin).readToEnd
  if args.any (· == "--compiler") then
    report "compiler" (fun _ => checkCompiler encoded)
  else
    report "extractor" (fun _ => checkExtractor encoded)
