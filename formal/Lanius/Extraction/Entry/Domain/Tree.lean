import Lanius.Extraction.Entry.Domain.Parser
import Lanius.Extraction.Frontend.Storage.Tree

namespace Lanius.Extraction.Entry
open Lanius.Compiler Lanius.Compiler.Lexer Lanius.Compiler.Parser Lanius.Extraction.Frontend

structure CheckedTreeDomain (accepted : EntrypointAnalysis.CheckedExtractorCoreSourcePack encoded sources) where
  units : CheckedParserTrees 4194304 1048576 65536 1024 accepted.checked.surface.pack.units

theorem CheckedTreeDomain.parser
    {accepted : EntrypointAnalysis.CheckedExtractorCoreSourcePack encoded sources}
    (checked : CheckedTreeDomain accepted) : ParserDomain sources := by
  unfold ParserDomain
  rw [← accepted.checked.surface.sources]
  exact checked.units.domains.1

theorem CheckedTreeDomain.tree
    {accepted : EntrypointAnalysis.CheckedExtractorCoreSourcePack encoded sources}
    (checked : CheckedTreeDomain accepted) : TreeDomain sources := by
  unfold TreeDomain
  rw [← accepted.checked.surface.sources]
  exact checked.units.domains.2

/-- One source-bound resource pass for parser capacity and all possible tree
layouts. The existing envelope transport is unchanged; no second parser or
second source extraction runs during budget calculation. -/
def CheckedExecution.checkParserTreeDomain?
    {accepted : EntrypointAnalysis.CheckedExtractorCoreSourcePack encoded sources}
    (_execution : CheckedExecution accepted) (candidates : List Envelope.Candidate) :
    Option (CheckedTreeDomain accepted) := do
  let storage ← checkUnitsParserTreeStorage? 4194304 1048576 65536 1024 _
    (checkedUnits_tokensValid accepted.checked.program.surfaceData) candidates
  pure ⟨storage⟩

end Lanius.Extraction.Entry
