import Lanius.Extraction.VerifiedLexerProgram
import Lanius.Extraction.ArtifactQuote
import Lanius.FunctionalViewCoreReification

namespace Lanius.Extraction.RawLexer.Results.Functions

open Lanius.Core
open Lanius.Typing
open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Reification

/-! # Checked FunctionalView forms for `raw_lexer.lani` results

These six functions are selected by source path and name from the checked
frontend pack.  The views below are recovered from those selected Core bodies;
none of the proof-facing bodies is maintained independently.
-/

private def lexStatusWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", "lex_status"
private def lexTokenCountWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", "lex_token_count"
private def lexErrorOffsetWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", "lex_error_offset"
private def completedWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", "completed"
private def lexicalFailureWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", "lexical_failure"
private def outputFullWire : CoreFunction :=
  artifact_pack_function%
    (include_str ".." / ".." / "Artifacts" / "frontend_pack.json"),
    "verified_compiler/src/verified/raw_lexer.lani", "output_full"

def lexStatusFunction : Function := CoreDecode.function lexStatusWire
def lexTokenCountFunction : Function :=
  CoreDecode.function lexTokenCountWire
def lexErrorOffsetFunction : Function :=
  CoreDecode.function lexErrorOffsetWire
def completedFunction : Function := CoreDecode.function completedWire
def lexicalFailureFunction : Function :=
  CoreDecode.function lexicalFailureWire
def outputFullFunction : Function := CoreDecode.function outputFullWire

theorem lexStatus_body_present : lexStatusFunction.body.isSome := by
  native_decide
theorem lexTokenCount_body_present : lexTokenCountFunction.body.isSome := by
  native_decide
theorem lexErrorOffset_body_present : lexErrorOffsetFunction.body.isSome := by
  native_decide
theorem completed_body_present : completedFunction.body.isSome := by
  native_decide
theorem lexicalFailure_body_present : lexicalFailureFunction.body.isSome := by
  native_decide
theorem outputFull_body_present : outputFullFunction.body.isSome := by
  native_decide

def lexStatusBody : Stmt :=
  lexStatusFunction.body.get lexStatus_body_present
def lexTokenCountBody : Stmt :=
  lexTokenCountFunction.body.get lexTokenCount_body_present
def lexErrorOffsetBody : Stmt :=
  lexErrorOffsetFunction.body.get lexErrorOffset_body_present
def completedBody : Stmt :=
  completedFunction.body.get completed_body_present
def lexicalFailureBody : Stmt :=
  lexicalFailureFunction.body.get lexicalFailure_body_present
def outputFullBody : Stmt :=
  outputFullFunction.body.get outputFull_body_present

def i32Type : Ty := .scalar (.signed .i32)
def lexResultType : Ty := .structure 4

def accessorBody (field : FieldId) : Stmt :=
  .sequence (.returnValue (some (.field (.local 0) field))) .skip

def completedCoreBody : Stmt :=
  .sequence (.returnValue (some (.structValue 4 [
    .constant 89, .local 0, .value (.signed .i32 0)]))) .skip

def lexicalFailureCoreBody : Stmt :=
  .sequence (.returnValue (some (.structValue 4 [
    .constant 90, .local 0, .local 1]))) .skip

def outputFullCoreBody : Stmt :=
  .sequence (.returnValue (some (.structValue 4 [
    .constant 91, .local 0, .local 1]))) .skip

theorem lexStatus_shape :
    lexStatusFunction.id = 46 ∧
      lexStatusFunction.parameters = [(0, lexResultType)] ∧
      lexStatusFunction.returnType = i32Type ∧
      lexStatusFunction.body = some (accessorBody 0) := by
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem lexTokenCount_shape :
    lexTokenCountFunction.id = 47 ∧
      lexTokenCountFunction.parameters = [(0, lexResultType)] ∧
      lexTokenCountFunction.returnType = i32Type ∧
      lexTokenCountFunction.body = some (accessorBody 1) := by
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem lexErrorOffset_shape :
    lexErrorOffsetFunction.id = 48 ∧
      lexErrorOffsetFunction.parameters = [(0, lexResultType)] ∧
      lexErrorOffsetFunction.returnType = i32Type ∧
      lexErrorOffsetFunction.body = some (accessorBody 2) := by
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem completed_shape :
    completedFunction.id = 49 ∧
      completedFunction.parameters = [(0, i32Type)] ∧
      completedFunction.returnType = lexResultType ∧
      completedFunction.body = some completedCoreBody := by
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem lexicalFailure_shape :
    lexicalFailureFunction.id = 50 ∧
      lexicalFailureFunction.parameters = [(0, i32Type), (1, i32Type)] ∧
      lexicalFailureFunction.returnType = lexResultType ∧
      lexicalFailureFunction.body = some lexicalFailureCoreBody := by
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem outputFull_shape :
    outputFullFunction.id = 51 ∧
      outputFullFunction.parameters = [(0, i32Type), (1, i32Type)] ∧
      outputFullFunction.returnType = lexResultType ∧
      outputFullFunction.body = some outputFullCoreBody := by
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem lexStatus_has_body : lexStatusFunction.body = some lexStatusBody := by
  simp [lexStatusBody]
theorem lexTokenCount_has_body :
    lexTokenCountFunction.body = some lexTokenCountBody := by
  simp [lexTokenCountBody]
theorem lexErrorOffset_has_body :
    lexErrorOffsetFunction.body = some lexErrorOffsetBody := by
  simp [lexErrorOffsetBody]
theorem completed_has_body : completedFunction.body = some completedBody := by
  simp [completedBody]
theorem lexicalFailure_has_body :
    lexicalFailureFunction.body = some lexicalFailureBody := by
  simp [lexicalFailureBody]
theorem outputFull_has_body : outputFullFunction.body = some outputFullBody := by
  simp [outputFullBody]

theorem core_finds_lexStatus :
    verifiedFrontendCore.function? lexStatusFunction.id =
      some lexStatusFunction := by rfl
theorem core_finds_lexTokenCount :
    verifiedFrontendCore.function? lexTokenCountFunction.id =
      some lexTokenCountFunction := by rfl
theorem core_finds_lexErrorOffset :
    verifiedFrontendCore.function? lexErrorOffsetFunction.id =
      some lexErrorOffsetFunction := by rfl
theorem core_finds_completed :
    verifiedFrontendCore.function? completedFunction.id =
      some completedFunction := by rfl
theorem core_finds_lexicalFailure :
    verifiedFrontendCore.function? lexicalFailureFunction.id =
      some lexicalFailureFunction := by rfl
theorem core_finds_outputFull :
    verifiedFrontendCore.function? outputFullFunction.id =
      some outputFullFunction := by rfl

private def reification? (function : Function) (body : Stmt) :=
  reifyBlock? verifiedFrontendCore function.returnType
    (parameterContext function.parameters) false
    (identityLayout (arity := function.parameters.length))
    function.parameters.length body

theorem lexStatus_reification_exists :
    (reification? lexStatusFunction lexStatusBody).isSome := by native_decide
theorem lexTokenCount_reification_exists :
    (reification? lexTokenCountFunction lexTokenCountBody).isSome := by
  native_decide
theorem lexErrorOffset_reification_exists :
    (reification? lexErrorOffsetFunction lexErrorOffsetBody).isSome := by
  native_decide
theorem completed_reification_exists :
    (reification? completedFunction completedBody).isSome := by native_decide
theorem lexicalFailure_reification_exists :
    (reification? lexicalFailureFunction lexicalFailureBody).isSome := by
  native_decide
theorem outputFull_reification_exists :
    (reification? outputFullFunction outputFullBody).isSome := by native_decide

def lexStatusView :=
  (reification? lexStatusFunction lexStatusBody).get
    lexStatus_reification_exists
def lexTokenCountView :=
  (reification? lexTokenCountFunction lexTokenCountBody).get
    lexTokenCount_reification_exists
def lexErrorOffsetView :=
  (reification? lexErrorOffsetFunction lexErrorOffsetBody).get
    lexErrorOffset_reification_exists
def completedView :=
  (reification? completedFunction completedBody).get
    completed_reification_exists
def lexicalFailureView :=
  (reification? lexicalFailureFunction lexicalFailureBody).get
    lexicalFailure_reification_exists
def outputFullView :=
  (reification? outputFullFunction outputFullBody).get
    outputFull_reification_exists

theorem lexStatus_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 lexStatusView.block =
      lexStatusBody := lexStatusView.toCoreExactly
theorem lexTokenCount_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 lexTokenCountView.block =
      lexTokenCountBody := lexTokenCountView.toCoreExactly
theorem lexErrorOffset_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 lexErrorOffsetView.block =
      lexErrorOffsetBody := lexErrorOffsetView.toCoreExactly
theorem completed_toCore_exactly :
    toCoreStmt (identityLayout (arity := 1)) 1 completedView.block =
      completedBody := completedView.toCoreExactly
theorem lexicalFailure_toCore_exactly :
    toCoreStmt (identityLayout (arity := 2)) 2 lexicalFailureView.block =
      lexicalFailureBody := lexicalFailureView.toCoreExactly
theorem outputFull_toCore_exactly :
    toCoreStmt (identityLayout (arity := 2)) 2 outputFullView.block =
      outputFullBody := outputFullView.toCoreExactly

end Lanius.Extraction.RawLexer.Results.Functions
