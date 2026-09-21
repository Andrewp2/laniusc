import Lanius.Compiler.ELFExecutionCheck
import Lanius.Compiler.CertificateLoweringCheck

open Lanius.Extraction
open Lanius.Compiler
open Lanius.Compiler.CertificateLoweringCheck
open Lanius.Compiler.ELFExecutionCheck

def readExecutionSources (paths : List String) : IO (List SourceFile) :=
  paths.mapM fun path => do
    let contents ← IO.FS.readBinFile (System.FilePath.mk path)
    pure { path := path, bytes := contents.toList.map UInt8.toNat }

def main (args : List String) : IO UInt32 := do
  if args.isEmpty then
    IO.eprintln "usage: checkELFExecution SOURCE... < certificate"
    return 1
  let encoded ← (← IO.getStdin).readToEnd
  let sources ← readExecutionSources args
  match ELFExecutionCheck.check encoded sources noExternalBehavior with
  | .error failure =>
      IO.eprintln s!"ELF execution rejected: {repr failure}"
      return 1
  | .ok checked =>
      let branch := match checked.endToEnd.program with
        | .standard _ => "standard"
        | .direct _ _ => "direct"
      IO.println s!"ELF execution accepted: startup-displacement={repr checked.displacement} entry-address={repr checked.entrySlice.image.address} entry-length={checked.entrySlice.image.bytes.length} program={branch}"
      return 0
