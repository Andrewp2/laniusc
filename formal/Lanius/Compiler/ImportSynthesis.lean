import Lanius.Compiler.ImportCheck

namespace Lanius.Compiler.ImportSynthesis

open Lanius
open Lanius.Declarations

/- Import rows are derived in source order.  In particular, callers cannot
   inject a module edge or choose either side of an edge. -/
def synthesize? (pack : SourcePack) : Option (List CollectedImport) :=
  (ImportCheck.normalizedImportOccurrences pack).mapM
    (ImportCheck.expectedImport? pack)

structure Checked (pack : SourcePack) where
  imports : List CollectedImport
  checker : ImportCheck.Checked pack imports

/- The checker is the final boundary: synthesis only proposes rows, while the
   existing checker establishes coverage, matching, and per-source uniqueness. -/
def check (pack : SourcePack) : Option (Checked pack) := do
  let imports ← synthesize? pack
  let checked ← match ImportCheck.check pack imports with
    | .ok checked => some checked
    | .error _ => none
  pure { imports := imports, checker := checked }

theorem check_sound {pack : SourcePack} {checked : Checked pack}
    (_accepted : check pack = some checked) :
    ImportCollectionCovers pack checked.imports :=
  checked.checker.covers

end Lanius.Compiler.ImportSynthesis
