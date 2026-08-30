import Lanius.Extraction.VerifiedParserAppend
import Lanius.FunctionalViewCoreStatefulReification

namespace Lanius.Extraction.Parser.Append

open Lanius.Core
open Lanius.Typing
open Lanius.Extraction
open Lanius.Extraction.ParserAppend
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.FunctionalView.Core.Stateful.Reification

/-! # Source-derived FunctionalView for `parser.lani::append_state`

The complete mutable command is mechanically recovered from the function
decoded from the checked parser artifact.  Its semantic contract is
`ParserAppend.extractedParserAppendStateCall_evaluates`.
-/

def body : Stmt := extractedParserAppendStateFunction.body.getD .skip

private def reification? :=
  reifyCommand? verifiedParserCore extractedParserAppendStateFunction.returnType
    (parameterContext extractedParserAppendStateFunction.parameters) false
    (identityLayout (arity := 6)) 6 body

theorem reification_exists : reification?.isSome := by
  native_decide

def view := reification?.get reification_exists

theorem view_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      (identityLayout (arity := 6)) 6 view.command = body :=
  view.toCoreExactly

theorem view_is_checked_body :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt actionAdapter
      (identityLayout (arity := 6)) 6 view.command = parserAppendStateBody := by
  rw [view_toCore_exactly]
  simp [body, extractedParserAppendState_body_eq]

end Lanius.Extraction.Parser.Append
