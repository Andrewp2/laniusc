import Lanius.Compiler.EndToEndCheck
import Lanius.Typing.Check

open Lanius.Extraction
open Lanius.Compiler
open Lanius.Compiler.CertificateLoweringCheck
open Lanius.Compiler.EndToEndCheck

def readCertificateSources (paths : List String) : IO (List SourceFile) :=
  paths.mapM fun path => do
    let contents ← IO.FS.readBinFile (System.FilePath.mk path)
    pure { path := path, bytes := contents.toList.map UInt8.toNat }

def main (args : List String) : IO UInt32 := do
  if args.isEmpty then
    IO.eprintln "usage: checkCertificate SOURCE... < certificate"
    return 1
  let encoded ← (← IO.getStdin).readToEnd
  let sources ← readCertificateSources args
  -- The standalone CLI has no host implementation for external functions.
  -- `noExternalBehavior` therefore rejects certificates containing externals;
  -- embedding callers should pass an explicit resolver instead.
  match EndToEndCheck.check encoded sources noExternalBehavior with
  | .ok checked =>
      let words := checked.certificate.certificate.certificate.transport.length
      let elf := checked.certificate.certificate.certificate.elf.length
      let functions := checked.certificate.certificate.certificate.functions.length
      IO.println s!"certificate accepted: exact source, declaration-aligned typed Core program, canonical context and ProgramLowering evidence, canonical transport ({words} words), ELF ({elf} bytes), spans ({functions}); external behavior is absent by CLI policy"
      return 0
  | .error failure =>
      IO.eprintln s!"certificate rejected: {repr failure}"
      return 1
