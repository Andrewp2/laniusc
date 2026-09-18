import Lanius.Extraction.Entry.Source
import Lean.Util.CollectAxioms

namespace Lanius.Extraction.Tests.Provenance
open Lanius.Extraction.Entry Lanius.Extraction.CoreSynthesis.Program

/-- Instantiate the retained source relationships without rerunning preparation
or synthesis. Corrupting the supplied path, bytes, or order must fail at source
binding, before the more expensive frontend execution-proof construction. -/
def checkCertified (checked : CheckedSource encoded sources) : IO _root_.Unit := do
  have _metadata := checked.sourceBound.metadata
  have _sameCore := checked.coreUnique
  let first :: rest := sources
    | throw (IO.userError "source-provenance integration requires a nonempty closure")
  let started ← IO.monoNanosNow
  for changed in [
      { first with path := first.path ++ ".wrong" } :: rest,
      { first with bytes := first.bytes ++ [32] } :: rest,
      sources.reverse] do
    match checkSource encoded changed with
    | .error "self-embedding rejected at source-or-surface" => pure ()
    | .error reason => throw (IO.userError s!"source mutation failed at the wrong boundary: {reason}")
    | .ok _ => throw (IO.userError "source certificate admitted mismatched bytes, path, or source order")
  let finished ← IO.monoNanosNow
  IO.println s!"Source-bound Core/execution certificate retained; wrong path, bytes, and order rejected in {(finished - started) / 1000000} ms without entering execution-proof checking."

run_elab do
  let standard := #[``propext, ``Classical.choice, ``Quot.sound]
  for name in #[``SourceBound.metadata, ``SourceBound.unique, ``EntrypointAnalysis.sourceBound,
      ``CheckedSource.sourceBound, ``CheckedSource.coreUnique,
      ``EntrypointAnalysis.checkExtractorCoreSourcePack, ``Entry.checkExecution, ``Entry.checkSource] do
    for assumption in ← Lean.collectAxioms name do
      unless standard.contains assumption do
        throwError "Source provenance or certificate construction {name} adds unexpected axiom {assumption}"
  Lean.logInfo "Source validation, execution-proof construction, combined checking, and retained source/Core relationships use only standard Lean axioms."

end Lanius.Extraction.Tests.Provenance
