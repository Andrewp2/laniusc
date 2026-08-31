import Lanius.Extraction.VerifiedLexerProgram
import Lanius.Extraction.ArtifactQuote
import Lanius.FunctionalViewCoreStatefulReification

namespace Lanius.Extraction.RawLexer.LexInto.Functions

set_option maxRecDepth 1000000

open Lanius.Core
open Lanius.Typing
open Lanius.Extraction
open Lanius.FunctionalView.Core

/-! # Checked FunctionalView form of `raw_lexer.lani::lex_into`

The function is selected from the checked frontend pack by source path and
name.  The stateful view is mechanically reified from that exact Core body;
the proof boundary therefore cannot drift from the Lanius source unnoticed.
-/

private def lexIntoWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani",
    "lex_into"

def lexIntoFunction : Function := CoreDecode.function lexIntoWire

theorem lexInto_body_present : lexIntoFunction.body.isSome := by
  native_decide

def lexIntoBody : Stmt :=
  lexIntoFunction.body.get lexInto_body_present

theorem lexInto_has_body : lexIntoFunction.body = some lexIntoBody := by
  simp [lexIntoBody]

theorem verifiedFrontendCore_finds_lexInto :
    verifiedFrontendCore.function? lexIntoFunction.id =
      some lexIntoFunction := by
  rfl

private def reification? :=
  Lanius.FunctionalView.Core.Stateful.Reification.reifyCommand?
    verifiedFrontendCore lexIntoFunction.returnType
    (parameterContext lexIntoFunction.parameters) false
    (identityLayout (arity := 4)) 4 lexIntoBody

theorem lexInto_reification_exists : reification?.isSome := by
  native_decide

def lexIntoView :=
  reification?.get lexInto_reification_exists

theorem lexInto_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter identityLayout 4
        lexIntoView.command = lexIntoBody :=
  lexIntoView.toCoreExactly

end Lanius.Extraction.RawLexer.LexInto.Functions
