import Lanius.Extraction.ArtifactQuote

namespace Lanius.Extraction
open Lean Elab Term

/-- Quote independent file bytes as ordinary input data. The logical path
    must match the extractor's argument; the physical path is relative to this
    Lean file. Use in a noncomputable definition: this proof-only quotation
    deliberately skips native code generation. No checker result or proof is
    imported from native execution. -/
elab "source_file% " physical:str " as " logical:str : term => do
  let some parent := (System.FilePath.mk (← getFileName)).parent
    | throwError "source quotation needs a saved Lean file"
  let bytes ← IO.FS.readBinFile (parent / physical.getString)
  let source : SourceFile := { path := logical.getString, bytes := bytes.toList.map UInt8.toNat }
  quoteBounded source (compile := false)

end Lanius.Extraction
