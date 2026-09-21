import Lanius.Extraction.CurrentSourceClosure

open Lanius.Extraction
open Lanius.Extraction.CurrentSourceClosure
open Lanius.Extraction.SyntaxCheck

/-! Independent checker entrypoint for the current extractor's combined
    frontend/emitter compact artifact.  Source bytes are read from the
    checked checkout by `CurrentSourceClosure`; the compact payload remains
    untrusted input and is accepted only through the existing decoder,
    lexer, parser, and Surface checks. -/

def report {encoded : String} {expectedSources : List SourceFile}
    (kind : String)
    (result : Except PackCheckStage (CheckedSourcePack encoded expectedSources)) : IO UInt32 := do
  match result with
  | .ok checked =>
      IO.println s!"current {kind} source closure accepted: {checked.compact.pack.units.length} units, exact bytes and reconstructed Surface"
      pure 0
  | .error failure =>
      IO.eprintln s!"current {kind} source closure rejected: {repr failure}"
      pure 1

def main (args : List String) : IO UInt32 := do
  let encoded ← (← IO.getStdin).readToEnd
  if args.any (· == "--compiler") then
    report "compiler" (checkCompiler encoded)
  else
    report "extractor" (checkExtractor encoded)
