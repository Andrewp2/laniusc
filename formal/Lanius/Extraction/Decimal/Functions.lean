import Lanius.Extraction.VerifiedLexerProgram
import Lanius.FunctionalViewCoreStatefulReification

namespace Lanius.Extraction.Decimal.Functions

set_option maxRecDepth 1000000

open Lanius.Core
open Lanius.Typing
open Lanius.Extraction
open Lanius.FunctionalView.Core

/-! # Checked FunctionalView forms for `decimal.lani`

Every definition in this file is selected by source path and function name
from the checked frontend pack.  Reification is checked against the complete
frontend Core program because the decimal functions call helpers from the
`digits` and `token_scan` units.
-/

private def integerScanWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani",
    "integer_scan"

private def floatScanWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani",
    "float_scan"

private def numberFailureWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani",
    "number_failure"

private def scanExponentWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani",
    "scan_exponent"

private def finishDecimalWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/decimal.lani",
    "finish_decimal"

def integerScanFunction : Function := CoreDecode.function integerScanWire
def floatScanFunction : Function := CoreDecode.function floatScanWire
def numberFailureFunction : Function := CoreDecode.function numberFailureWire
def scanExponentFunction : Function := CoreDecode.function scanExponentWire
def finishDecimalFunction : Function := CoreDecode.function finishDecimalWire

theorem integerScan_body_present : integerScanFunction.body.isSome := by native_decide
theorem floatScan_body_present : floatScanFunction.body.isSome := by native_decide
theorem numberFailure_body_present : numberFailureFunction.body.isSome := by native_decide
theorem scanExponent_body_present : scanExponentFunction.body.isSome := by native_decide
theorem finishDecimal_body_present : finishDecimalFunction.body.isSome := by native_decide

def integerScanBody : Stmt := integerScanFunction.body.get integerScan_body_present
def floatScanBody : Stmt := floatScanFunction.body.get floatScan_body_present
def numberFailureBody : Stmt := numberFailureFunction.body.get numberFailure_body_present
def scanExponentBody : Stmt := scanExponentFunction.body.get scanExponent_body_present
def finishDecimalBody : Stmt := finishDecimalFunction.body.get finishDecimal_body_present

private def reification? (function : Function) (arity : Nat) (body : Stmt) :=
  Lanius.FunctionalView.Core.Stateful.Reification.reifyCommand?
    verifiedFrontendCore function.returnType
    (parameterContext function.parameters) false
    (identityLayout (arity := arity)) arity body

theorem integerScan_reification_exists :
    (reification? integerScanFunction 1 integerScanBody).isSome := by native_decide
theorem floatScan_reification_exists :
    (reification? floatScanFunction 1 floatScanBody).isSome := by native_decide
theorem numberFailure_reification_exists :
    (reification? numberFailureFunction 1 numberFailureBody).isSome := by native_decide
theorem scanExponent_reification_exists :
    (reification? scanExponentFunction 3 scanExponentBody).isSome := by native_decide
theorem finishDecimal_reification_exists :
    (reification? finishDecimalFunction 3 finishDecimalBody).isSome := by native_decide

def integerScanView :=
  (reification? integerScanFunction 1 integerScanBody).get integerScan_reification_exists
def floatScanView :=
  (reification? floatScanFunction 1 floatScanBody).get floatScan_reification_exists
def numberFailureView :=
  (reification? numberFailureFunction 1 numberFailureBody).get
    numberFailure_reification_exists
def scanExponentView :=
  (reification? scanExponentFunction 3 scanExponentBody).get scanExponent_reification_exists
def finishDecimalView :=
  (reification? finishDecimalFunction 3 finishDecimalBody).get finishDecimal_reification_exists

theorem integerScan_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter identityLayout 1
        integerScanView.command = integerScanBody :=
  integerScanView.toCoreExactly

theorem floatScan_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter identityLayout 1
        floatScanView.command = floatScanBody :=
  floatScanView.toCoreExactly

theorem numberFailure_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter identityLayout 1
        numberFailureView.command = numberFailureBody :=
  numberFailureView.toCoreExactly

theorem scanExponent_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter identityLayout 3
        scanExponentView.command = scanExponentBody :=
  scanExponentView.toCoreExactly

theorem finishDecimal_toCore_exactly :
    Lanius.FunctionalView.Core.Stateful.toCoreStmt
        Lanius.FunctionalView.Core.Stateful.actionAdapter identityLayout 3
        finishDecimalView.command = finishDecimalBody :=
  finishDecimalView.toCoreExactly

end Lanius.Extraction.Decimal.Functions
