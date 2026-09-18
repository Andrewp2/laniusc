import Lanius.Extraction.CoreSynthesis.Provenance
import Lanius.Extraction.Entry.Check
import Lanius.Extraction.Entry.Host

namespace Lanius.Extraction.Entry
open Lanius.Extraction.EntrypointAnalysis

/-- Final source-to-execution certificate. The accepted source/embedding,
source-derived Core program, actual entrypoint, and whole-run execution proof
are retained together rather than assembled as unrelated checked records. -/
structure CheckedSource (encoded : String) (sources : List SourceFile) where
  accepted : CheckedExtractorCoreSourcePack encoded sources
  produced : checkExtractorCoreSourcePack encoded sources = .success accepted
  execution : CheckedExecution accepted

/-- Run each existing checking stage once. The match equation is retained as
proof, not checked by evaluating the same source-to-Core computation again. -/
def checkSource (encoded : String) (sources : List SourceFile) : Except String (CheckedSource encoded sources) :=
  match produced : checkExtractorCoreSourcePack encoded sources with
  | .failure stage => .error ("self-embedding rejected at " ++ stage)
  | .success accepted => do
    let execution ← checkExecution accepted
    pure ⟨accepted, produced, execution⟩

theorem CheckedSource.sourceBound (checked : CheckedSource encoded sources) :
    CoreSynthesis.Program.SourceBound checked.accepted.checked :=
  EntrypointAnalysis.sourceBound checked.produced

/-- The actual executable's program is uniquely tied to these exact source
and artifact inputs, not merely to metadata selected by an extractor. -/
theorem CheckedSource.coreUnique (left right : CheckedSource encoded sources) :
    left.accepted.checked.program.core = right.accepted.checked.program.core := by
  exact congrArg (fun checked => checked.program.core) (left.sourceBound.unique right.sourceBound)

end Lanius.Extraction.Entry
