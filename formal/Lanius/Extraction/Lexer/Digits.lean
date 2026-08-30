import Lanius.Extraction.VerifiedLexerProgram
import Lanius.FunctionalViewCoreReification
import Lanius.FunctionalViewCoreStatefulReification

namespace Lanius.Extraction.Lexer.Digits

set_option maxRecDepth 1000000

open Lanius.Core
open Lanius.Typing
open Lanius.Extraction
open Lanius.FunctionalView.Core

/-! # Source-derived FunctionalView coverage for `digits.lani`

Every function in the checked source unit is quoted from the frontend artifact
and mechanically reified.  A successful reification carries its own exact
round-trip theorem, so these views cannot drift from the compiled source.
-/

private def digitScanSucceededWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani",
    "digit_scan_succeeded"

private def digitScanEndOffsetWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani",
    "digit_scan_end_offset"

private def digitScanErrorOffsetWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/digits.lani",
    "digit_scan_error_offset"

def digitScanSucceededFunction : Function :=
  CoreDecode.function digitScanSucceededWire

def digitScanEndOffsetFunction : Function :=
  CoreDecode.function digitScanEndOffsetWire

def digitScanErrorOffsetFunction : Function :=
  CoreDecode.function digitScanErrorOffsetWire

theorem digitScanSucceededFunction_body_present :
    digitScanSucceededFunction.body.isSome := by
  native_decide

theorem digitScanEndOffsetFunction_body_present :
    digitScanEndOffsetFunction.body.isSome := by
  native_decide

theorem digitScanErrorOffsetFunction_body_present :
    digitScanErrorOffsetFunction.body.isSome := by
  native_decide

theorem successfulDigitsFunction_body_present :
    extractedSuccessfulDigitsFunction.body.isSome := by
  native_decide

theorem failedDigitsFunction_body_present :
    extractedFailedDigitsFunction.body.isSome := by
  native_decide

theorem isDigitForBaseFunction_body_present :
    extractedIsDigitForBaseFunction.body.isSome := by
  native_decide

theorem scanDigitRunFunction_body_present :
    extractedScanDigitRunFunction.body.isSome := by
  native_decide

def digitScanSucceededBody : Stmt :=
  digitScanSucceededFunction.body.get digitScanSucceededFunction_body_present

def digitScanEndOffsetBody : Stmt :=
  digitScanEndOffsetFunction.body.get digitScanEndOffsetFunction_body_present

def digitScanErrorOffsetBody : Stmt :=
  digitScanErrorOffsetFunction.body.get digitScanErrorOffsetFunction_body_present

def successfulDigitsBody : Stmt :=
  extractedSuccessfulDigitsFunction.body.get successfulDigitsFunction_body_present

def failedDigitsBody : Stmt :=
  extractedFailedDigitsFunction.body.get failedDigitsFunction_body_present

def isDigitForBaseBody : Stmt :=
  extractedIsDigitForBaseFunction.body.get isDigitForBaseFunction_body_present

def scanDigitRunBody : Stmt :=
  extractedScanDigitRunFunction.body.get scanDigitRunFunction_body_present

private def pureReification? (function : Function) (arity : Nat) (body : Stmt) :=
  Lanius.FunctionalView.Core.Reification.reifyBlock?
    verifiedFrontendDigitsCore function.returnType
    (parameterContext function.parameters) false
    (identityLayout (arity := arity)) arity body

theorem digitScanSucceededReification_exists :
    (pureReification? digitScanSucceededFunction 1
      digitScanSucceededBody).isSome := by
  native_decide

theorem digitScanEndOffsetReification_exists :
    (pureReification? digitScanEndOffsetFunction 1
      digitScanEndOffsetBody).isSome := by
  native_decide

theorem digitScanErrorOffsetReification_exists :
    (pureReification? digitScanErrorOffsetFunction 1
      digitScanErrorOffsetBody).isSome := by
  native_decide

theorem successfulDigitsReification_exists :
    (pureReification? extractedSuccessfulDigitsFunction 1
      successfulDigitsBody).isSome := by
  native_decide

theorem failedDigitsReification_exists :
    (pureReification? extractedFailedDigitsFunction 1 failedDigitsBody).isSome := by
  native_decide

theorem isDigitForBaseReification_exists :
    (pureReification? extractedIsDigitForBaseFunction 2
      isDigitForBaseBody).isSome := by
  native_decide

def digitScanSucceededView :=
  (pureReification? digitScanSucceededFunction 1 digitScanSucceededBody).get
    digitScanSucceededReification_exists

def digitScanEndOffsetView :=
  (pureReification? digitScanEndOffsetFunction 1 digitScanEndOffsetBody).get
    digitScanEndOffsetReification_exists

def digitScanErrorOffsetView :=
  (pureReification? digitScanErrorOffsetFunction 1 digitScanErrorOffsetBody).get
    digitScanErrorOffsetReification_exists

def successfulDigitsView :=
  (pureReification? extractedSuccessfulDigitsFunction 1 successfulDigitsBody).get
    successfulDigitsReification_exists

def failedDigitsView :=
  (pureReification? extractedFailedDigitsFunction 1 failedDigitsBody).get
    failedDigitsReification_exists

def isDigitForBaseView :=
  (pureReification? extractedIsDigitForBaseFunction 2 isDigitForBaseBody).get
    isDigitForBaseReification_exists

theorem digitScanSucceededView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 digitScanSucceededView.block =
      digitScanSucceededBody :=
  digitScanSucceededView.toCoreExactly

theorem digitScanEndOffsetView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 digitScanEndOffsetView.block =
      digitScanEndOffsetBody :=
  digitScanEndOffsetView.toCoreExactly

theorem digitScanErrorOffsetView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 digitScanErrorOffsetView.block =
      digitScanErrorOffsetBody :=
  digitScanErrorOffsetView.toCoreExactly

theorem successfulDigitsView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 successfulDigitsView.block =
      successfulDigitsBody :=
  successfulDigitsView.toCoreExactly

theorem failedDigitsView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 failedDigitsView.block =
      failedDigitsBody :=
  failedDigitsView.toCoreExactly

theorem isDigitForBaseView_toCore_exactly :
    toCoreStmt (identityLayout (arity := 2)) 2 isDigitForBaseView.block =
      isDigitForBaseBody :=
  isDigitForBaseView.toCoreExactly

private def scanDigitRunReification? :=
  Lanius.FunctionalView.Core.Stateful.Reification.reifyCommand?
    verifiedFrontendDigitsCore extractedScanDigitRunFunction.returnType
    (parameterContext extractedScanDigitRunFunction.parameters) false
    (identityLayout (arity := 4)) 4
    scanDigitRunBody

theorem scanDigitRunReification_exists :
    scanDigitRunReification?.isSome := by
  native_decide

def scanDigitRunView :=
  scanDigitRunReification?.get scanDigitRunReification_exists

theorem scanDigitRunView_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter
        (identityLayout (arity := 4)) 4 scanDigitRunView.command =
      scanDigitRunBody :=
  scanDigitRunView.toCoreExactly

end Lanius.Extraction.Lexer.Digits
