import Lanius.Extraction.VerifiedLexerProgram
import Lanius.Extraction.ArtifactQuote
import Lanius.FunctionalViewCoreStatefulReification

namespace Lanius.Extraction.RawLexer.ScanOne.Functions

set_option maxRecDepth 1000000

open Lanius.Core
open Lanius.Typing
open Lanius.Extraction
open Lanius.FunctionalView.Core

/-! # Checked FunctionalView form of `raw_lexer.lani::scan_one`

The function and its body are selected from the checked frontend pack.  The
stateful FunctionalView is mechanically recovered from that body and carries
an exact round-trip certificate; no independently maintained dispatcher is
used at the proof boundary.
-/

private def scanOneWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani",
    "scan_one"

def scanOneFunction : Function := CoreDecode.function scanOneWire

theorem scanOne_body_present : scanOneFunction.body.isSome := by
  native_decide

def scanOneBody : Stmt :=
  scanOneFunction.body.get scanOne_body_present

theorem scanOne_has_body : scanOneFunction.body = some scanOneBody := by
  simp [scanOneBody]

theorem verifiedFrontendCore_finds_scanOne :
    verifiedFrontendCore.function? scanOneFunction.id =
      some scanOneFunction := by
  rfl

private def reification? :=
  Lanius.FunctionalView.Core.Stateful.Reification.reifyCommand?
    verifiedFrontendCore scanOneFunction.returnType
    (parameterContext scanOneFunction.parameters) false
    (identityLayout (arity := 3)) 3 scanOneBody

theorem scanOne_reification_exists : reification?.isSome := by
  native_decide

def scanOneView :=
  reification?.get scanOne_reification_exists

theorem scanOne_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter identityLayout 3
        scanOneView.command = scanOneBody :=
  scanOneView.toCoreExactly

end Lanius.Extraction.RawLexer.ScanOne.Functions
