import Lanius.Extraction.VerifiedLexerProgram
import Lanius.Extraction.ArtifactQuote
import Lanius.FunctionalViewCoreReification

namespace Lanius.Extraction.TokenScan.Functions

open Lanius.Core
open Lanius.Typing
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Reification

/-! # Checked FunctionalView forms for `token_scan.lani`

Every function is selected by source path and name from the checked frontend
pack.  Each FunctionalView is then reified from that selected Core body, so the
proof-facing representation cannot drift from the compiler artifact.
-/

private def succeededWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani", "succeeded"
private def kindWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani", "kind"
private def endOffsetWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani", "end_offset"
private def errorOffsetWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani", "error_offset"
private def successfulWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani", "successful"
private def failedWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/token_scan.lani", "failed"

def succeededFunction : Function := CoreDecode.function succeededWire
def kindFunction : Function := CoreDecode.function kindWire
def endOffsetFunction : Function := CoreDecode.function endOffsetWire
def errorOffsetFunction : Function := CoreDecode.function errorOffsetWire
def successfulFunction : Function := CoreDecode.function successfulWire
def failedFunction : Function := CoreDecode.function failedWire

theorem succeeded_body_present : succeededFunction.body.isSome := by native_decide
theorem kind_body_present : kindFunction.body.isSome := by native_decide
theorem endOffset_body_present : endOffsetFunction.body.isSome := by native_decide
theorem errorOffset_body_present : errorOffsetFunction.body.isSome := by native_decide
theorem successful_body_present : successfulFunction.body.isSome := by native_decide
theorem failed_body_present : failedFunction.body.isSome := by native_decide

def succeededBody : Stmt := succeededFunction.body.get succeeded_body_present
def kindBody : Stmt := kindFunction.body.get kind_body_present
def endOffsetBody : Stmt := endOffsetFunction.body.get endOffset_body_present
def errorOffsetBody : Stmt := errorOffsetFunction.body.get errorOffset_body_present
def successfulBody : Stmt := successfulFunction.body.get successful_body_present
def failedBody : Stmt := failedFunction.body.get failed_body_present

def boolType : Ty := .scalar .bool
def i32Type : Ty := .scalar (.signed .i32)
def tokenScanType : Ty := .structure 1

def accessorBody (field : FieldId) : Stmt :=
  .sequence (.returnValue (some (.field (.local 0) field))) .skip

def successfulCoreBody : Stmt :=
  .sequence (.returnValue (some (.structValue 1 [
    .value (.boolean true), .local 0, .local 1,
    .value (.signed .i32 0)]))) .skip

def failedCoreBody : Stmt :=
  .sequence (.returnValue (some (.structValue 1 [
    .value (.boolean false), .value (.signed .i32 0),
    .value (.signed .i32 0), .local 0]))) .skip

theorem succeeded_shape :
    succeededFunction.id = 18 ∧
      succeededFunction.parameters = [(0, tokenScanType)] ∧
      succeededFunction.returnType = boolType ∧
      succeededFunction.body = some (accessorBody 0) := by
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem kind_shape :
    kindFunction.id = 19 ∧
      kindFunction.parameters = [(0, tokenScanType)] ∧
      kindFunction.returnType = i32Type ∧
      kindFunction.body = some (accessorBody 1) := by
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem endOffset_shape :
    endOffsetFunction.id = 20 ∧
      endOffsetFunction.parameters = [(0, tokenScanType)] ∧
      endOffsetFunction.returnType = i32Type ∧
      endOffsetFunction.body = some (accessorBody 2) := by
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem errorOffset_shape :
    errorOffsetFunction.id = 21 ∧
      errorOffsetFunction.parameters = [(0, tokenScanType)] ∧
      errorOffsetFunction.returnType = i32Type ∧
      errorOffsetFunction.body = some (accessorBody 3) := by
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem successful_shape :
    successfulFunction.id = 22 ∧
      successfulFunction.parameters = [(0, i32Type), (1, i32Type)] ∧
      successfulFunction.returnType = tokenScanType ∧
      successfulFunction.body = some successfulCoreBody := by
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem failed_shape :
    failedFunction.id = 23 ∧
      failedFunction.parameters = [(0, i32Type)] ∧
      failedFunction.returnType = tokenScanType ∧
      failedFunction.body = some failedCoreBody := by
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem succeeded_has_body : succeededFunction.body = some succeededBody := by
  simp [succeededBody]
theorem kind_has_body : kindFunction.body = some kindBody := by
  simp [kindBody]
theorem endOffset_has_body : endOffsetFunction.body = some endOffsetBody := by
  simp [endOffsetBody]
theorem errorOffset_has_body : errorOffsetFunction.body = some errorOffsetBody := by
  simp [errorOffsetBody]
theorem successful_has_body : successfulFunction.body = some successfulBody := by
  simp [successfulBody]
theorem failed_has_body : failedFunction.body = some failedBody := by
  simp [failedBody]

theorem core_finds_succeeded :
    verifiedFrontendCore.function? succeededFunction.id =
      some succeededFunction := by rfl
theorem core_finds_kind :
    verifiedFrontendCore.function? kindFunction.id = some kindFunction := by rfl
theorem core_finds_endOffset :
    verifiedFrontendCore.function? endOffsetFunction.id =
      some endOffsetFunction := by rfl
theorem core_finds_errorOffset :
    verifiedFrontendCore.function? errorOffsetFunction.id =
      some errorOffsetFunction := by rfl
theorem core_finds_successful :
    verifiedFrontendCore.function? successfulFunction.id =
      some successfulFunction := by rfl
theorem core_finds_failed :
    verifiedFrontendCore.function? failedFunction.id = some failedFunction := by rfl

private def reification? (function : Function) (body : Stmt) :=
  reifyBlock? verifiedFrontendCore function.returnType
    (parameterContext function.parameters) false
    (identityLayout (arity := function.parameters.length))
    function.parameters.length body

theorem succeeded_reification_exists :
    (reification? succeededFunction succeededBody).isSome := by native_decide
theorem kind_reification_exists :
    (reification? kindFunction kindBody).isSome := by native_decide
theorem endOffset_reification_exists :
    (reification? endOffsetFunction endOffsetBody).isSome := by native_decide
theorem errorOffset_reification_exists :
    (reification? errorOffsetFunction errorOffsetBody).isSome := by native_decide
theorem successful_reification_exists :
    (reification? successfulFunction successfulBody).isSome := by native_decide
theorem failed_reification_exists :
    (reification? failedFunction failedBody).isSome := by native_decide

def succeededView :=
  (reification? succeededFunction succeededBody).get succeeded_reification_exists
def kindView :=
  (reification? kindFunction kindBody).get kind_reification_exists
def endOffsetView :=
  (reification? endOffsetFunction endOffsetBody).get endOffset_reification_exists
def errorOffsetView :=
  (reification? errorOffsetFunction errorOffsetBody).get errorOffset_reification_exists
def successfulView :=
  (reification? successfulFunction successfulBody).get successful_reification_exists
def failedView :=
  (reification? failedFunction failedBody).get failed_reification_exists

theorem succeeded_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 succeededView.block =
      succeededBody := succeededView.toCoreExactly
theorem kind_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 kindView.block =
      kindBody := kindView.toCoreExactly
theorem endOffset_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 endOffsetView.block =
      endOffsetBody := endOffsetView.toCoreExactly
theorem errorOffset_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 errorOffsetView.block =
      errorOffsetBody := errorOffsetView.toCoreExactly
theorem successful_toCore_exactly :
    toCoreStmt (identityLayout (arity := 2)) 2 successfulView.block =
      successfulBody := successfulView.toCoreExactly
theorem failed_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 failedView.block =
      failedBody := failedView.toCoreExactly

end Lanius.Extraction.TokenScan.Functions
