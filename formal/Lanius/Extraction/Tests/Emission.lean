import Lanius.Extraction.ExtractorContract

open Lanius.Extraction
open Lanius.Extraction.CoreSynthesis.Program
open Lanius.Extraction.ExtractorContract

/-! Integration check of the actual emitted module against both contracts.
Run with: emitted-module source-file accept-core|reject-core.
This is a test driver, not another extraction implementation. -/

def main (arguments : List String) : IO UInt32 := do
  let [modulePath, sourcePath, expectation] := arguments
    | throw (IO.userError "expected emitted-module source-file accept-core|reject-core")
  unless expectation == "accept-core" || expectation == "reject-core" do
    throw (IO.userError "unknown Core acceptance expectation")
  let emitted ← IO.FS.readFile modulePath
  unless emitted.startsWith modulePrefix && emitted.endsWith moduleSuffix do
    throw (IO.userError "emitted module framing differs from the extraction contract")
  let encoded := ((emitted.drop modulePrefix.length).dropEnd moduleSuffix.length).toString
  unless renderedModule encoded == emitted do
    throw (IO.userError "emitted module does not round-trip through the contract")
  let contents ← IO.FS.readBinFile sourcePath
  let source : SourceFile := {
    path := sourcePath
    bytes := contents.toList.map UInt8.toNat
  }
  unless (checkCompactSyntaxArtifactPackSources? encoded [source]).isSome do
    throw (IO.userError "faithful syntax extraction rejected")
  let changed : SourceFile := { source with bytes := source.bytes ++ [10] }
  if (checkCompactSyntaxArtifactPackSources? encoded [changed]).isSome then
    throw (IO.userError "syntax certificate accepted different source bytes")
  let typed := (checkCompactCoreSourcePack? encoded [source]).isSome
  unless typed == (expectation == "accept-core") do
    throw (IO.userError "unexpected typed-Core acceptance result")
  IO.println (sourcePath ++ ": faithful syntax accepted; Core " ++
    (if typed then "accepted" else "rejected"))
  return 0
