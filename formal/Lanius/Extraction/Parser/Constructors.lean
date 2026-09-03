import Lanius.Extraction.VerifiedFrontend.Parser.Append
import Lanius.Extraction.VerifiedFrontend.Parser.Result
import Lanius.FunctionalViewCoreReification

namespace Lanius.Extraction.Parser.Constructors

open Lanius.Core
open Lanius.Typing
open Lanius.Extraction
open Lanius.Extraction.ParserAppend
open Lanius.Extraction.ParserResult
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Reification

/-! # Source-derived FunctionalView parser constructors

These views are mechanically reified from the functions decoded from the
checked `parser.lani` artifact.  Their exact-round-trip theorems make the
decoded function bodies, rather than parallel handwritten terms, the source
of truth.  The semantic call contracts remain the contracts proved beside the
workspace model in `VerifiedParserAppend` and `VerifiedParserResult`.
-/

private def functionBody (function : Function) : Stmt :=
  function.body.getD .skip

private def reification? (function : Function) (arity : Nat) :=
  reifyBlock? verifiedParserCore function.returnType
    (parameterContext function.parameters) false
    (identityLayout (arity := arity)) arity (functionBody function)

theorem parseResultReification_exists :
    (reification? extractedParserParseResultFunction 4).isSome := by
  native_decide

theorem stateSeedReification_exists :
    (reification? extractedParserStateSeedFunction 7).isSome := by
  native_decide

theorem appendResultReification_exists :
    (reification? extractedParserAppendResultFunction 4).isSome := by
  native_decide

theorem appendOrFullReification_exists :
    (reification? extractedParserAppendOrFullFunction 2).isSome := by
  native_decide

def parseResultView :=
  (reification? extractedParserParseResultFunction 4).get
    parseResultReification_exists

def stateSeedView :=
  (reification? extractedParserStateSeedFunction 7).get
    stateSeedReification_exists

def appendResultView :=
  (reification? extractedParserAppendResultFunction 4).get
    appendResultReification_exists

def appendOrFullView :=
  (reification? extractedParserAppendOrFullFunction 2).get
    appendOrFullReification_exists

theorem parseResultView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 4)) 4 parseResultView.block =
      functionBody extractedParserParseResultFunction :=
  parseResultView.toCoreExactly

theorem stateSeedView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 7)) 7 stateSeedView.block =
      functionBody extractedParserStateSeedFunction :=
  stateSeedView.toCoreExactly

theorem appendResultView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 4)) 4 appendResultView.block =
      functionBody extractedParserAppendResultFunction :=
  appendResultView.toCoreExactly

theorem appendOrFullView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 2)) 2 appendOrFullView.block =
      functionBody extractedParserAppendOrFullFunction :=
  appendOrFullView.toCoreExactly

theorem parseResultView_is_checked_body :
    toCoreStmt (identityLayout (arity := 4)) 4 parseResultView.block =
      parserParseResultBody := by
  rw [parseResultView_toCore_exactly]
  simp [functionBody,
    extractedParserParseResult_function_shape.2.2.2.1]

theorem stateSeedView_is_checked_body :
    toCoreStmt (identityLayout (arity := 7)) 7 stateSeedView.block =
      parserStateSeedBody := by
  rw [stateSeedView_toCore_exactly]
  simp [functionBody, extractedParserStateSeed_function_shape.2.2.2.1]

theorem appendResultView_is_checked_body :
    toCoreStmt (identityLayout (arity := 4)) 4 appendResultView.block =
      parserAppendResultBody := by
  rw [appendResultView_toCore_exactly]
  simp [functionBody,
    extractedParserAppendResult_function_shape.2.2.2.1]

theorem appendOrFullView_is_checked_body :
    toCoreStmt (identityLayout (arity := 2)) 2 appendOrFullView.block =
      parserAppendOrFullBody := by
  rw [appendOrFullView_toCore_exactly]
  simp [functionBody,
    extractedParserAppendOrFull_function_shape.2.2.2.1]

end Lanius.Extraction.Parser.Constructors
