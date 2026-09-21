import Lanius.Compiler.Lexer.Artifact

namespace Lanius.Compiler.Lexer

theorem identifierStartPredicate_accepts : ∀ byte : Byte,
    (Artifact.identifierStartPredicate).accepts (Int.ofNat byte.val) =
      isIdentifierStart byte := by
  decide +kernel +revert

theorem decimalPredicate_accepts : ∀ byte : Byte,
    (Artifact.decimalPredicate).accepts (Int.ofNat byte.val) =
      isDecimalDigit byte := by
  decide +kernel +revert

theorem whitespacePredicate_accepts : ∀ byte : Byte,
    (Artifact.whitespacePredicate).accepts (Int.ofNat byte.val) =
      isWhitespace byte := by
  decide +kernel +revert

theorem symbolPredicate_accepts : ∀ byte : Byte,
    (Artifact.symbolPredicate).accepts (Int.ofNat byte.val) =
      isSymbolStart byte := by
  decide +kernel +revert

end Lanius.Compiler.Lexer
