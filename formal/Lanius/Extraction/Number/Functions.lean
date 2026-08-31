import Lanius.Extraction.VerifiedLexerProgram
import Lanius.FunctionalViewCoreStatefulReification

namespace Lanius.Extraction.Number.Functions

set_option maxRecDepth 1000000

open Lanius.Core
open Lanius.Typing
open Lanius.Extraction
open Lanius.FunctionalView.Core

/-! # Checked FunctionalView forms for `number.lani`

Both functions are selected from the checked frontend pack by source path and
function name.  Their FunctionalView commands are therefore exact views of the
Core bodies produced from `number.lani`, rather than parallel handwritten
implementations.
-/

private def scanNumberWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/number.lani",
    "scan_number"

private def scanLeadingDotNumberWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/number.lani",
    "scan_leading_dot_number"

def scanNumberFunction : Function := CoreDecode.function scanNumberWire

def scanLeadingDotNumberFunction : Function :=
  CoreDecode.function scanLeadingDotNumberWire

theorem scanNumber_body_present : scanNumberFunction.body.isSome := by
  native_decide

theorem scanLeadingDotNumber_body_present :
    scanLeadingDotNumberFunction.body.isSome := by
  native_decide

def scanNumberBody : Stmt :=
  scanNumberFunction.body.get scanNumber_body_present

def scanLeadingDotNumberBody : Stmt :=
  scanLeadingDotNumberFunction.body.get scanLeadingDotNumber_body_present

private def reification? (function : Function) (body : Stmt) :=
  Lanius.FunctionalView.Core.Stateful.Reification.reifyCommand?
    verifiedFrontendCore function.returnType
    (parameterContext function.parameters) false
    (identityLayout (arity := 3)) 3 body

theorem scanNumber_reification_exists :
    (reification? scanNumberFunction scanNumberBody).isSome := by
  native_decide

theorem scanLeadingDotNumber_reification_exists :
    (reification? scanLeadingDotNumberFunction
      scanLeadingDotNumberBody).isSome := by
  native_decide

def scanNumberView :=
  (reification? scanNumberFunction scanNumberBody).get
    scanNumber_reification_exists

def scanLeadingDotNumberView :=
  (reification? scanLeadingDotNumberFunction
    scanLeadingDotNumberBody).get scanLeadingDotNumber_reification_exists

theorem scanNumber_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter identityLayout 3
        scanNumberView.command = scanNumberBody :=
  scanNumberView.toCoreExactly

theorem scanLeadingDotNumber_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter identityLayout 3
        scanLeadingDotNumberView.command = scanLeadingDotNumberBody :=
  scanLeadingDotNumberView.toCoreExactly

end Lanius.Extraction.Number.Functions
