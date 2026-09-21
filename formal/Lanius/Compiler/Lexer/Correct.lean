import Lanius.Compiler.Lexer.Artifact
import Lanius.Compiler.Lexer.Predicate
import Lanius.Compiler.Lexer.Composition

namespace Lanius.Compiler.Lexer.Correct

open Lanius Lanius.Core Lanius.Semantics

def ImplementsBytePredicate (functionId : FunctionId) (spec : Byte → Bool) : Prop :=
  ∀ (byte : Byte) (before : State), before.CellsWellFormed →
    PurelyEvaluates Artifact.lexerProgram before
      (unaryI32PredicateCall functionId (Int.ofNat byte.val)) (.boolean (spec byte))

private theorem pureArtifactPredicate (functionId : FunctionId) (predicate : UnaryI32Predicate)
    (spec : Byte → Bool) (found : Artifact.lexerProgram.function? functionId = some (unaryI32PredicateFunction functionId 0 predicate))
    (accepts : ∀ byte : Byte, predicate.accepts (Int.ofNat byte.val) = spec byte) :
    ImplementsBytePredicate functionId spec := by
  intro byte before formed
  rw [← accepts byte]
  exact purelyEvaluates_unaryI32PredicateCall Artifact.lexerProgram before functionId 0
    predicate (Int.ofNat byte.val) found formed

theorem identifierStart_pure : ImplementsBytePredicate Artifact.identifierStartFunction.id isIdentifierStart :=
  pureArtifactPredicate _ _ _ (by simpa [Artifact.identifierStartFunction, unaryI32PredicateFunction] using Artifact.identifierStartFunction_found) identifierStartPredicate_accepts
theorem decimalDigit_pure : ImplementsBytePredicate Artifact.decimalFunction.id isDecimalDigit :=
  pureArtifactPredicate _ _ _ (by simpa [Artifact.decimalFunction, unaryI32PredicateFunction] using Artifact.decimalFunction_found) decimalPredicate_accepts
theorem whitespace_pure : ImplementsBytePredicate Artifact.whitespaceFunction.id isWhitespace :=
  pureArtifactPredicate _ _ _ (by simpa [Artifact.whitespaceFunction, unaryI32PredicateFunction] using Artifact.whitespaceFunction_found) whitespacePredicate_accepts
theorem symbolStart_pure : ImplementsBytePredicate Artifact.symbolStartFunction.id isSymbolStart :=
  pureArtifactPredicate _ _ _ (by simpa [Artifact.symbolStartFunction, unaryI32PredicateFunction] using Artifact.symbolStartFunction_found) symbolPredicate_accepts

theorem identifierContinue_pure : ImplementsBytePredicate Artifact.identifierContinueFunction.id isIdentifierContinue := by
  intro byte caller formed
  change PurelyEvaluates Artifact.lexerProgram caller
    (unaryI32PredicateCall Artifact.identifierContinueFunction.id (Int.ofNat byte.val)) (.boolean (isIdentifierStart byte || isDecimalDigit byte))
  rw [← identifierStartPredicate_accepts byte, ← decimalPredicate_accepts byte]
  rcases thresholdUnaryPredicateOr Artifact.lexerProgram caller 0 0 2
    Artifact.identifierStartPredicate Artifact.decimalPredicate (Int.ofNat byte.val)
    (by simpa [Artifact.identifierStartFunction, unaryI32PredicateFunction] using Artifact.identifierStartFunction_found)
    (by simpa [Artifact.decimalFunction, unaryI32PredicateFunction] using Artifact.decimalFunction_found)
    formed with ⟨after, bodyContract⟩
  exact (thresholdOneParameterCall Artifact.lexerProgram caller 1 0
    (.binary .logicalOr (.call 0 [.local 0]) (.call 2 [.local 0])) (Int.ofNat byte.val)
    (by simpa [Artifact.identifierContinueFunction, oneParameterBooleanFunction] using Artifact.identifierContinueFunction_found)
    formed (by simpa using bodyContract)).erase

end Lanius.Compiler.Lexer.Correct
