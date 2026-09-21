import Lanius.Extraction.CorePhaseCertificate

open Lanius.Extraction
open Lanius.Extraction.CorePhaseCertificate

def readExpectedSources (paths : List String) : IO (List SourceFile) :=
  paths.mapM fun path => do
    let contents ← IO.FS.readBinFile (System.FilePath.mk path)
    pure { path := path, bytes := contents.toList.map UInt8.toNat }

def main (args : List String) : IO UInt32 := do
  if args.isEmpty then
    IO.eprintln "usage: checkCorePhase SOURCE... < certificate"
    return 1
  let encoded ← (← IO.getStdin).readToEnd
  let sources ← readExpectedSources args
  match CorePhaseCertificate.check encoded sources with
  | .ok checked =>
      let words := checked.lowering.certificate.certificate.transport.length
      IO.println s!"core phase accepted: exact compact source, checked ProgramLowering program, canonical transport ({words} words), and empty image/span phase"
      return 0
  | .error failure =>
      IO.eprintln s!"core phase rejected: {repr failure}"
      return 1
