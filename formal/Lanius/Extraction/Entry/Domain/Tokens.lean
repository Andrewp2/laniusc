import Lanius.Extraction.Entry.Certificate
import Lanius.Extraction.Frontend.Storage.Pack
import Lanius.Extraction.Entry.File.Domain

namespace Lanius.Extraction.Entry
open Lanius.Compiler Lanius.Compiler.Lexer Lanius.Extraction.Frontend

def CheckedExecution.checkTokenDomain?
    {accepted : EntrypointAnalysis.CheckedExtractorCoreSourcePack encoded sources}
    (_execution : CheckedExecution accepted) :
    Option (PLift (TokenDomain sources)) := do
  let storage ← checkUnitsTokenStorage? 65536 65536 65536 accepted.checked.program.surfaceData
  pure ⟨by
    unfold TokenDomain
    rw [← accepted.checked.surface.sources]
    exact storage.down⟩

end Lanius.Extraction.Entry
