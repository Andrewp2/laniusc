import Lanius.Extraction.SymbolicLocalChecker
import Lanius.Extraction.VerifiedFrontend.Parser.Program

namespace Lanius.Extraction

open Lanius.SymbolicCore
open Lanius.Extraction.SymbolicLocalChecker
open Lanius.ScopeGraph

/-- The symbolic-local stage succeeds for the exact scoped parser value. -/
theorem verifiedParser_symbolic_derivation_accepted :
    (deriveArtifact? verifiedParserArtifact verifiedParserScopedArtifact).isSome =
      true := by
  native_decide

def verifiedParserSymbolicFunctions : List DerivedFunction :=
  (deriveArtifact? verifiedParserArtifact verifiedParserScopedArtifact).get
    verifiedParser_symbolic_derivation_accepted

theorem verifiedParser_symbolic_functions_derived :
    deriveArtifact? verifiedParserArtifact verifiedParserScopedArtifact =
      some verifiedParserSymbolicFunctions := by
  have accepted := verifiedParser_symbolic_derivation_accepted
  cases found : deriveArtifact? verifiedParserArtifact
      verifiedParserScopedArtifact with
  | none =>
      simp [found] at accepted
  | some functions =>
      simp [verifiedParserSymbolicFunctions, found]

/-- The composed certificate retains both the earlier complete checker result
    and the exact symbolic functions above, without executing either checker a
    second time to recover a projection. -/
def verifiedParserSymbolicChecked :
    SymbolicLocalChecker.CheckedArtifact verifiedParserArtifact
      verifiedParserScopedArtifact := {
  complete := verifiedParserChecked
  functions := verifiedParserSymbolicFunctions
  derived := verifiedParser_symbolic_functions_derived
}

def verifiedParserSymbolicFunctionNames : List String :=
  verifiedParserSymbolicFunctions.map (·.sourceName)

def verifiedParserSymbolicFunction? (name : String) : Option DerivedFunction :=
  verifiedParserSymbolicFunctions.find? (fun function =>
    function.sourceName == name)

def verifiedParserRecognizerSymbolic? : Option DerivedFunction :=
  verifiedParserSymbolicFunction? "recognize"

def verifiedParserRecognizerLocals :
    List (String × DeclarationId × List ScopeId × Nat) :=
  match verifiedParserRecognizerSymbolic? with
  | none => []
  | some function => function.view.locals.bindings.map fun binding =>
      (binding.identity.name, binding.identity.declaration,
        binding.identity.scope, binding.coreId)

theorem verifiedParser_symbolic_function_names :
    verifiedParserSymbolicFunctionNames = [
      "parse_status", "parse_state_count", "parse_root_state",
      "parse_error_position", "parse_result", "state_seed",
      "append_result", "range_valid", "grammar_is_valid", "chart_word",
      "state_word", "state_value", "find_state", "append_state",
      "production_rhs_length", "production_rhs_symbol", "production_lhs",
      "scan_terminal", "append_or_full", "recognize"] := by
  native_decide

def verifiedParserRecognizerSymbolic : DerivedFunction :=
  verifiedParserRecognizerSymbolic?.get (by native_decide)

/-- The recognizer's source-parameter frame, obtained from checked declaration
    identities rather than reconstructed from a numeric Core-ID interval. -/
def verifiedParserRecognizerParameterFrame : LocalBindingFrame :=
  verifiedParserRecognizerSymbolic.parameterBindings

/-- Numeric evaluator projection of the checked source-parameter frame. -/
def verifiedParserRecognizerParameterIds : List VarId :=
  verifiedParserRecognizerParameterFrame.coreIds

def verifiedParserRecognizerStateBase :
    LocalRef verifiedParserRecognizerSymbolic.view.locals :=
  (verifiedParserRecognizerSymbolic.view.locals.uniqueReferenceNamed?
    "state_base").get (by native_decide)

@[simp] theorem verifiedParserRecognizerStateBase_coreId :
    verifiedParserRecognizerStateBase.coreId = 8 := by
  native_decide

theorem verifiedParserRecognizer_parameter_frame :
    verifiedParserRecognizerParameterFrame.map (fun binding =>
      (binding.identity.name, binding.coreId)) = [
      ("grammar", 0),
      ("grammar_length", 1),
      ("tokens", 2),
      ("token_count", 3),
      ("workspace", 4),
      ("workspace_length", 5)] := by
  native_decide

theorem verifiedParserRecognizer_parameter_core_ids :
    verifiedParserRecognizerParameterIds = [0, 1, 2, 3, 4, 5] := by
  native_decide

@[simp] theorem mem_verifiedParserRecognizerParameterIds_iff
    (id : Nat) :
    id ∈ verifiedParserRecognizerParameterIds ↔ id ≤ 5 := by
  rw [verifiedParserRecognizer_parameter_core_ids]
  simp only [List.mem_cons, List.not_mem_nil, or_false]
  constructor
  · intro member
    omega
  · intro bound
    omega

def verifiedParserRangeValidSymbolic : DerivedFunction :=
  (verifiedParserSymbolicFunction? "range_valid").get (by native_decide)

def verifiedParserRangeValidOffset :
    LocalRef verifiedParserRangeValidSymbolic.view.locals :=
  (verifiedParserRangeValidSymbolic.parameterReferenceNamed? "offset").get
    (by native_decide)

def verifiedParserRangeValidCount :
    LocalRef verifiedParserRangeValidSymbolic.view.locals :=
  (verifiedParserRangeValidSymbolic.parameterReferenceNamed? "count").get
    (by native_decide)

def verifiedParserRangeValidLength :
    LocalRef verifiedParserRangeValidSymbolic.view.locals :=
  (verifiedParserRangeValidSymbolic.parameterReferenceNamed? "length").get
    (by native_decide)

theorem verifiedParserRangeValid_parameter_core_ids :
    verifiedParserRangeValidOffset.coreId = 0 ∧
      verifiedParserRangeValidCount.coreId = 1 ∧
      verifiedParserRangeValidLength.coreId = 2 := by
  native_decide

@[simp] theorem verifiedParserRangeValidOffset_coreId :
    verifiedParserRangeValidOffset.coreId = 0 :=
  verifiedParserRangeValid_parameter_core_ids.1

@[simp] theorem verifiedParserRangeValidCount_coreId :
    verifiedParserRangeValidCount.coreId = 1 :=
  verifiedParserRangeValid_parameter_core_ids.2.1

@[simp] theorem verifiedParserRangeValidLength_coreId :
    verifiedParserRangeValidLength.coreId = 2 :=
  verifiedParserRangeValid_parameter_core_ids.2.2

/-- The caller frame for `range_valid` is derived from the checked Core body,
    not from a manually maintained numeric interval. -/
def verifiedParserRangeValidRootFrame :
    LocalAccessFrame :=
  let body := verifiedParserRangeValidSymbolic.view.core.body.get
    (by native_decide)
  verifiedParserRangeValidSymbolic.checkedRootLiveFrame body
    (by native_decide)

theorem verifiedParserRangeValid_root_frame :
    verifiedParserRangeValidRootFrame.map (fun access =>
      (access.1.identity.name, access.1.identity.declaration,
        access.1.coreId, access.2)) = [
      ("offset", verifiedParserRangeValidOffset.identity.declaration, 0,
        .read),
      ("count", verifiedParserRangeValidCount.identity.declaration, 1,
        .read),
      ("length", verifiedParserRangeValidLength.identity.declaration, 2,
        .read)] := by
  native_decide

def verifiedParserFindStateSymbolic : DerivedFunction :=
  (verifiedParserSymbolicFunction? "find_state").get (by native_decide)

/-- The live caller locals at the outer `find_state` binder.  The temporary
    `current` is absent because `Stmt.freeAccesses` removes locals introduced
    by the statement itself. -/
def verifiedParserFindStateCallerFrame :
    LocalAccessFrame :=
  let body := verifiedParserFindStateSymbolic.view.core.body.get
    (by native_decide)
  verifiedParserFindStateSymbolic.checkedRootLiveFrame body
    (by native_decide)

/-- Declaration-preserving projection of the checked access frame.  Proofs
    consume this frame directly, retaining source identity instead of reducing
    the caller contract to a list of numeric Core local IDs. -/
def verifiedParserFindStateCallerBindings : LocalBindingFrame :=
  verifiedParserFindStateCallerFrame.bindings

def verifiedParserFindStateCallerFrameIds : List VarId :=
  verifiedParserFindStateCallerBindings.coreIds

theorem verifiedParserFindState_caller_frame :
    verifiedParserFindStateCallerFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("workspace", 0, .read),
      ("position", 2, .read),
      ("state_base", 1, .read),
      ("seed", 3, .read)] := by
  native_decide

theorem verifiedParserFindState_caller_frame_ids :
    verifiedParserFindStateCallerFrameIds = [0, 2, 1, 3] := by
  native_decide

def verifiedParserScanTerminalSymbolic : DerivedFunction :=
  (verifiedParserSymbolicFunction? "scan_terminal").get (by native_decide)

def verifiedParserScanTerminalCallerFrame :
    LocalAccessFrame :=
  let body := verifiedParserScanTerminalSymbolic.view.core.body.get
    (by native_decide)
  verifiedParserScanTerminalSymbolic.checkedRootLiveFrame body
    (by native_decide)

def verifiedParserScanTerminalCallerFrameIds : List VarId :=
  verifiedParserScanTerminalCallerFrame.ids

theorem verifiedParserScanTerminal_caller_frame :
    verifiedParserScanTerminalCallerFrame.map (fun access =>
      (access.1.identity.name, access.1.coreId, access.2)) = [
      ("position", 3, .read),
      ("token_count", 2, .read),
      ("tokens", 1, .read),
      ("grammar", 0, .read),
      ("semantic_kind", 4, .read)] := by
  native_decide

theorem verifiedParserScanTerminal_caller_frame_ids :
    verifiedParserScanTerminalCallerFrameIds = [3, 2, 1, 0, 4] := by
  native_decide

theorem verifiedParserRecognizerSymbolic_matches_extracted :
    (verifiedParserRecognizerSymbolic.view.erase ==
      extractedParserRecognizeFunction) = true := by
  native_decide


end Lanius.Extraction
