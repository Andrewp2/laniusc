import Lanius.Extraction.Entry.Domain.Syntax
import Lanius.Extraction.Frontend.Storage.Parser

namespace Lanius.Extraction.Entry
open Lanius.Compiler Lanius.Compiler.Lexer Lanius.Compiler.Parser Lanius.Extraction.Frontend

theorem checkedUnits_tokensValid : {artifacts : List Artifact} →
    ArtifactPackChecker.CheckedUnitSurfaces artifacts → ∀ artifact ∈ artifacts, TokenArtifactValid artifact
  | [], .nil, _, member => by cases member
  | _ :: _, .cons head tail, artifact, member => by
    rcases List.mem_cons.mp member with same | later
    · subst artifact; exact head.valid.1.1
    · exact checkedUnits_tokensValid tail artifact later

def CheckedExecution.checkParserDomain?
    {accepted : EntrypointAnalysis.CheckedExtractorCoreSourcePack encoded sources}
    (_execution : CheckedExecution accepted) (candidates : List Envelope.Candidate) :
    Option (PLift (ParserDomain sources)) := do
  let storage ← checkUnitsParserStorage? 4194304 _
    (checkedUnits_tokensValid accepted.checked.program.surfaceData) candidates
  pure ⟨by
    unfold ParserDomain
    rw [← accepted.checked.surface.sources]
    exact storage.down⟩

end Lanius.Extraction.Entry
