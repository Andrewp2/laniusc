import Lanius.Extraction.Entry.Domain.Tree
import Lanius.Extraction.Frontend.Storage.Output

namespace Lanius.Extraction.Entry
open Lanius.Compiler Lanius.Compiler.Lexer Lanius.Compiler.Parser
open Lanius.Extraction.Frontend Lanius.Extraction.SemanticTokens
open Lanius.Extraction.ParserTreeLayout Lanius.Extraction.CompactOutput

def OutputDomain (sources : List SourceFile) (capacity : Nat) : Prop :=
  ∃ bounds, SourcesOutputBounds sources bounds ∧ moduleFramingBytes + bounds.sum ≤ capacity

structure CheckedOutputDomain (sources : List SourceFile) (capacity : Nat) where
  units : CheckedOutputStorage sources
  fits : moduleFramingBytes + units.bounds.sum ≤ capacity

theorem CheckedOutputDomain.domain (checked : CheckedOutputDomain sources capacity) : OutputDomain sources capacity :=
  ⟨checked.units.bounds, checked.units.valid, checked.fits⟩

def checkOutputCapacity? (storage : CheckedOutputStorage sources) (capacity : Nat) :
    Option (CheckedOutputDomain sources capacity) :=
  if fits : moduleFramingBytes + storage.bounds.sum ≤ capacity then some ⟨storage, fits⟩ else none

/-- Bind already proved syntax and resource conditions to the exact ordered
files selected by this process. Only host lookup and source equality execute;
the lexer, parser, resource checkers, and extractor do not run again. -/
def CheckedOutputDomain.checkSuccessDomain? (checked : CheckedOutputDomain sources 16777216)
    (tokens : TokenDomain sources) (syntaxValid : SyntaxDomain sources)
    (parser : ParserDomain sources) (tree : TreeDomain sources) (world : Lanius.World.State) :
    Option (PLift (SuccessDomain world)) :=
  if selected : ExtractorContract.requestedSources? world = some sources then
    some ⟨⟨sources, checked.units.bounds, selected,
      SourceDomains.of_domains tokens syntaxValid parser tree checked.units.valid, checked.fits⟩⟩
  else none

/-- A linear pass over already accepted unit evidence. Neither tokenization,
chart validation, tree-budget calculation nor source extraction runs again. -/
def CheckedTreeDomain.checkOutputDomain?
    {accepted : EntrypointAnalysis.CheckedExtractorCoreSourcePack encoded sources}
    (trees : CheckedTreeDomain accepted) (capacity : Nat) : Option (CheckedOutputDomain sources capacity) := do
  let storage ← checkUnitsOutputStorage? trees.units
    (checkedUnits_tokensValid accepted.checked.program.surfaceData)
  let ordered : CheckedOutputStorage sources := ⟨storage.bounds,
    Eq.mp (congrArg (fun files => SourcesOutputBounds files storage.bounds) accepted.checked.surface.sources) storage.valid⟩
  checkOutputCapacity? ordered capacity

end Lanius.Extraction.Entry
