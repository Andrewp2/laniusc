import Lanius.Extraction.ArtifactQuote
import Lanius.Compiler.Lexer.UnaryI32Predicate

namespace Lanius.Compiler.Lexer.Artifact

open Lanius Lanius.Core Lanius.Extraction

def lexerProgram : Program :=
  artifact_core_program% (include_str "../../Extraction/Artifacts/lexer.json")

def lexerArtifactSource : String := artifact_source_text%
  (include_str "../../Extraction/Artifacts/lexer.json"),
  "verified_compiler/src/verified/lexer.lani"

def lexerSource : String :=
  include_str "../../../../verified_compiler/src/verified/lexer.lani"

/- The artifact embeds source bytes, so this is a kernel-checked provenance
   witness for the exact source file used by the current checkout. -/
theorem lexerSource_provenance : lexerArtifactSource = lexerSource := by
  rfl

def identifierStartPredicate : UnaryI32Predicate :=
  .or (.or (.and (.atom .greaterEqual 97) (.atom .lessEqual 122))
    (.and (.atom .greaterEqual 65) (.atom .lessEqual 90))) (.atom .equal 95)

def decimalPredicate : UnaryI32Predicate :=
  .and (.atom .greaterEqual 48) (.atom .lessEqual 57)

def whitespacePredicate : UnaryI32Predicate :=
  .or (.or (.or (.atom .equal 32) (.atom .equal 9)) (.atom .equal 10))
    (.atom .equal 13)

def symbolPredicate : UnaryI32Predicate :=
  .or (.or (.or (.or (.or (.or (.or (.or (.or (.or (.or (.or
    (.or (.or (.or (.or (.or (.or (.or (.or (.or (.or (.or
      (.atom .equal 40) (.atom .equal 41)) (.atom .equal 43))
      (.atom .equal 42)) (.atom .equal 61)) (.atom .equal 45))
      (.atom .equal 47)) (.atom .equal 33)) (.atom .equal 91))
      (.atom .equal 93)) (.atom .equal 123)) (.atom .equal 125))
      (.atom .equal 60)) (.atom .equal 62)) (.atom .equal 38))
      (.atom .equal 124)) (.atom .equal 37)) (.atom .equal 94))
      (.atom .equal 126)) (.atom .equal 44)) (.atom .equal 59))
      (.atom .equal 58)) (.atom .equal 63)) (.atom .equal 46)

def identifierStartFunction : Function :=
  unaryI32PredicateFunction 0 0 identifierStartPredicate
def decimalFunction : Function :=
  unaryI32PredicateFunction 2 0 decimalPredicate
def whitespaceFunction : Function :=
  unaryI32PredicateFunction 3 0 whitespacePredicate
def symbolStartFunction : Function :=
  unaryI32PredicateFunction 4 0 symbolPredicate

def identifierContinueFunction : Function := {
  id := 1, parameters := [(0, .scalar (.signed .i32))],
  returnType := .scalar .bool,
  body := some (.sequence (.returnValue (some
    (.binary .logicalOr (.call 0 [.local 0]) (.call 2 [.local 0])))) .skip)
}

theorem identifierStartFunction_found :
    lexerProgram.function? identifierStartFunction.id = some identifierStartFunction := by
  rfl
theorem decimalFunction_found :
    lexerProgram.function? decimalFunction.id = some decimalFunction := by rfl
theorem whitespaceFunction_found :
    lexerProgram.function? whitespaceFunction.id = some whitespaceFunction := by
  rfl
theorem symbolStartFunction_found :
    lexerProgram.function? symbolStartFunction.id = some symbolStartFunction := by
  rfl
theorem identifierContinueFunction_found :
    lexerProgram.function? identifierContinueFunction.id =
      some identifierContinueFunction := by
  rfl

end Lanius.Compiler.Lexer.Artifact
