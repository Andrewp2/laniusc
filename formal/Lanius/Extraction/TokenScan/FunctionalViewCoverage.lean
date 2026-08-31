import Lanius.Extraction.TokenScan.Semantics
import Lanius.Extraction.ArtifactContextChecker

namespace Lanius.Extraction.TokenScan.FunctionalViewCoverage

open Lanius.Core
open Lanius.Extraction
open Lanius.FunctionalView.Core

/-! # Enforceable `token_scan.lani` coverage

The inventory is reconstructed from the checked Surface artifact.  This gate
therefore stops compiling if the source gains, loses, or renames a function
without a corresponding exact reification and checked-program call contract.
-/

def functionNames : Option (List String) :=
  (decodeReconstructedSurface verifiedFrontendTokenScanArtifact).map fun surface =>
    (ArtifactContextChecker.collectFunctions surface.items).map (·.name)

theorem source_function_names :
    functionNames = some [
      "succeeded", "kind", "end_offset", "error_offset", "successful",
      "failed"] := by
  native_decide

structure TheoremReference {proposition : Prop} (proof : proposition) where
  checked : proposition

private theorem reference {proposition : Prop} (proof : proposition) :
    TheoremReference proof := ⟨proof⟩

structure ExactCoverage where
  sourceFunctionNames : TheoremReference source_function_names
  succeeded :
    toCoreStmt (identityLayout (arity := 1)) 1
        Functions.succeededView.block = Functions.succeededBody
  kind :
    toCoreStmt (identityLayout (arity := 1)) 1
        Functions.kindView.block = Functions.kindBody
  endOffset :
    toCoreStmt (identityLayout (arity := 1)) 1
        Functions.endOffsetView.block = Functions.endOffsetBody
  errorOffset :
    toCoreStmt (identityLayout (arity := 1)) 1
        Functions.errorOffsetView.block = Functions.errorOffsetBody
  successful :
    toCoreStmt (identityLayout (arity := 2)) 2
        Functions.successfulView.block = Functions.successfulBody
  failed :
    toCoreStmt (identityLayout (arity := 1)) 1
        Functions.failedView.block = Functions.failedBody

theorem exact : Nonempty ExactCoverage := by
  exact ⟨{
    sourceFunctionNames := reference source_function_names
    succeeded := Functions.succeeded_toCore_exactly
    kind := Functions.kind_toCore_exactly
    endOffset := Functions.endOffset_toCore_exactly
    errorOffset := Functions.errorOffset_toCore_exactly
    successful := Functions.successful_toCore_exactly
    failed := Functions.failed_toCore_exactly
  }⟩

structure SemanticCoverage where
  exact : ExactCoverage
  succeeded : TheoremReference Semantics.succeededCall_soundness
  kind : TheoremReference Semantics.kindCall_soundness
  endOffset : TheoremReference Semantics.endOffsetCall_soundness
  errorOffset : TheoremReference Semantics.errorOffsetCall_soundness
  successful : TheoremReference Semantics.successfulCall_soundness
  failed : TheoremReference Semantics.failedCall_soundness
  combined : TheoremReference Semantics.callSoundness
  constructorsFramePreserving :
    TheoremReference Semantics.constructorFramePreservingCallSoundness
  succeededValue : TheoremReference (@Semantics.callModel_succeeded)
  kindValue : TheoremReference (@Semantics.callModel_kind)
  endOffsetValue : TheoremReference (@Semantics.callModel_end_offset)
  errorOffsetValue : TheoremReference (@Semantics.callModel_error_offset)
  successfulValue : TheoremReference (@Semantics.callModel_successful)
  failedValue : TheoremReference (@Semantics.callModel_failed)

theorem complete : Nonempty SemanticCoverage := by
  obtain ⟨exactCoverage⟩ := exact
  exact ⟨{
    exact := exactCoverage
    succeeded := reference Semantics.succeededCall_soundness
    kind := reference Semantics.kindCall_soundness
    endOffset := reference Semantics.endOffsetCall_soundness
    errorOffset := reference Semantics.errorOffsetCall_soundness
    successful := reference Semantics.successfulCall_soundness
    failed := reference Semantics.failedCall_soundness
    combined := reference Semantics.callSoundness
    constructorsFramePreserving :=
      reference Semantics.constructorFramePreservingCallSoundness
    succeededValue := reference (@Semantics.callModel_succeeded)
    kindValue := reference (@Semantics.callModel_kind)
    endOffsetValue := reference (@Semantics.callModel_end_offset)
    errorOffsetValue := reference (@Semantics.callModel_error_offset)
    successfulValue := reference (@Semantics.callModel_successful)
    failedValue := reference (@Semantics.callModel_failed)
  }⟩

end Lanius.Extraction.TokenScan.FunctionalViewCoverage
