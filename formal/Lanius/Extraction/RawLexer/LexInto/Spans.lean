import Lanius.Extraction.RawLexer.LexInto.Model
import Lanius.Compiler.LexerSpanBounds

namespace Lanius.Extraction.RawLexer.LexInto.Model
open Lanius.Compiler.Lexer

/-- Capacity limiting retains a prefix of already valid raw-token spans,
including the accepted prefix of a lexical failure. -/
theorem emittedTokens_validSpans (source : List Byte) (capacity : Nat) :
    ∀ token ∈ emittedTokens (lexInto source capacity),
      token.start ≤ token.finish ∧ token.finish ≤ source.length := by
  have spans := lexRaw_validSpans source
  unfold lexInto
  cases scanned : lexRaw source <;> simp only [scanned, RawLexResult.ValidSpans] at spans <;>
    simp only [limitResult]
  all_goals first
    | exact spans
    | skip
  all_goals
    unfold limitAccepted
    split
    · exact spans
    · intro token member
      exact spans token (List.mem_of_mem_take member)

end Lanius.Extraction.RawLexer.LexInto.Model
