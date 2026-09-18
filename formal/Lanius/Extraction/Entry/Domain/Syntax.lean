import Lanius.Extraction.Entry.Domain.Tokens
import Lanius.Extraction.Parse.Language.Artifact

namespace Lanius.Extraction.Entry
open Lanius.Compiler Lanius.Compiler.Lexer Lanius.Compiler.Parser Lanius.Extraction.Frontend

/-- The singular checked embedding already certifies input syntax. This is
proof projection and composition, not another executable parser/checker. -/
theorem CheckedExecution.syntaxDomain
    {accepted : EntrypointAnalysis.CheckedExtractorCoreSourcePack encoded sources}
    (_execution : CheckedExecution accepted) : SyntaxDomain sources := by
  unfold SyntaxDomain
  rw [← accepted.checked.surface.sources]
  exact accepted.checked.program.surfaceData.sourceSyntax

end Lanius.Extraction.Entry
