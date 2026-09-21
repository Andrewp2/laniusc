import Lanius.Compiler.Lexer.ArtifactClassifier
import Lanius.Compiler.Lexer.Classifier
import Lanius.Compiler.Lexer.Predicate

namespace Lanius.Compiler.Lexer.Correct

open Lanius.Core Lanius.Semantics

private def classifyStartTree : I32DecisionTree :=
  .branch Artifact.identifierStartPredicate (.leaf 0 1)
    (.branch Artifact.decimalPredicate (.leaf 1 2)
      (.branch Artifact.whitespacePredicate (.leaf 2 3)
        (.branch (.atom .equal 34) (.leaf 4 5)
          (.branch (.atom .equal 39) (.leaf 5 6)
            (.branch Artifact.symbolPredicate (.leaf 3 4) (.leaf 6 7))))))

private theorem classifyStartTree_accepts : ∀ byte : Byte,
    classifyStartTree.accepts (Int.ofNat byte.val) =
      Int.ofNat (classifyStartCode byte) := by decide +kernel +revert

theorem classifyStart_pure : ∀ (byte : Byte) (before : State),
    before.CellsWellFormed →
      PurelyEvaluates Artifact.lexerProgram before
        (.call Artifact.classifyStartFunction.id
          [.value (.signed .i32 (Int.ofNat byte.val))])
        (.signed .i32 (Int.ofNat (classifyStartCode byte))) := by
  intro byte before formed
  have tree := purelyEvaluates_i32DecisionTreeCall classifyStartTree
    Artifact.lexerProgram before 5 0 (Int.ofNat byte.val)
    (by rw [show i32DecisionTreeFunction 5 0 classifyStartTree =
      Artifact.classifyStartFunction from rfl]; exact Artifact.classifyStartFunction_found)
    (by repeat' first | constructor | exact ⟨_, rfl, rfl⟩) formed
  rw [classifyStartTree_accepts byte] at tree
  simpa [Artifact.classifyStartFunction] using tree

end Lanius.Compiler.Lexer.Correct
