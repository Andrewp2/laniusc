import Lanius.Extraction.Symbol.CompilerAgreement

namespace Lanius.Extraction.Symbol.FunctionalViewCoverage

open Lanius.Core
open Lanius.Extraction
open Lanius.FunctionalView.Core
open Lanius.Extraction.Symbol
open Lanius.Extraction.Symbol.Functions

def sourceText : String :=
  include_str ".." / ".." / ".." / ".." / "verified_compiler" / "src" /
    "verified" / "symbol.lani"

def functionNames : Option (List String) :=
  (decodeReconstructedSurface verifiedFrontendSymbolArtifact).map fun surface =>
    (ArtifactContextChecker.collectFunctions surface.items).map (·.name)

/-- The inventory is reconstructed from the checked artifact.  Any source
function addition, removal, or rename invalidates this four-function gate. -/
theorem source_function_names :
    functionNames = some ["token_match_kind", "token_match_length",
      "token_match", "match_symbol_head"] := by
  native_decide

theorem artifact_tracks_source :
    verifiedFrontendSymbolArtifact.sources.map (·.path) =
        ["verified_compiler/src/verified/symbol.lani"] ∧
      verifiedFrontendSymbolArtifact.sources.map (·.bytes) =
        [sourceTextBytes sourceText] := by
  native_decide

structure TheoremReference {proposition : Prop} (proof : proposition) where
  checked : proposition

private theorem reference {proposition : Prop} (proof : proposition) :
    TheoremReference proof :=
  ⟨proof⟩

structure ExactCoverage where
  sourceFunctions : TheoremReference source_function_names
  sourceBytes : TheoremReference artifact_tracks_source
  tokenMatchKind : TheoremReference tokenMatchKind_toCore_exactly
  tokenMatchLength : TheoremReference tokenMatchLength_toCore_exactly
  tokenMatch : TheoremReference tokenMatch_toCore_exactly
  matchSymbolHead : TheoremReference matchSymbolHead_toCore_exactly

theorem exact_complete : Nonempty ExactCoverage := by
  exact ⟨{
    sourceFunctions := reference source_function_names
    sourceBytes := reference artifact_tracks_source
    tokenMatchKind := reference tokenMatchKind_toCore_exactly
    tokenMatchLength := reference tokenMatchLength_toCore_exactly
    tokenMatch := reference tokenMatch_toCore_exactly
    matchSymbolHead := reference matchSymbolHead_toCore_exactly
  }⟩

structure SemanticCoverage where
  exact : ExactCoverage
  tokenMatchKind :
    TheoremReference Calls.tokenMatchKindFramePreservingCallSoundness
  tokenMatchLength :
    TheoremReference Calls.tokenMatchLengthFramePreservingCallSoundness
  tokenMatch :
    TheoremReference Calls.tokenMatchFramePreservingCallSoundness
  matchSymbolHead :
    TheoremReference (@MainCalls.mainFramePreservingCallSoundness)
  combinedFramePreserving :
    TheoremReference (@MainCalls.framePreservingCallSoundness)
  combinedCheckedCalls : TheoremReference (@MainCalls.callSoundness)
  selectedRule : TheoremReference (@CompilerAgreement.encoded_eq_selected)
  tokenMatchKindEquation :
    TheoremReference (@MainCalls.callModel_tokenMatchKind)
  tokenMatchLengthEquation :
    TheoremReference (@MainCalls.callModel_tokenMatchLength)
  tokenMatchEquation : TheoremReference (@MainCalls.callModel_tokenMatch)
  matchSymbolHeadEquation :
    TheoremReference (@MainCalls.callModel_matchSymbolHead)

/-- Enforceable 4/4 source inventory, exact reification, and checked-program
semantic coverage for `symbol.lani`. -/
theorem complete : Nonempty SemanticCoverage := by
  exact ⟨{
    exact := Classical.choice exact_complete
    tokenMatchKind :=
      reference Calls.tokenMatchKindFramePreservingCallSoundness
    tokenMatchLength :=
      reference Calls.tokenMatchLengthFramePreservingCallSoundness
    tokenMatch := reference Calls.tokenMatchFramePreservingCallSoundness
    matchSymbolHead :=
      reference (@MainCalls.mainFramePreservingCallSoundness)
    combinedFramePreserving :=
      reference (@MainCalls.framePreservingCallSoundness)
    combinedCheckedCalls := reference (@MainCalls.callSoundness)
    selectedRule := reference (@CompilerAgreement.encoded_eq_selected)
    tokenMatchKindEquation := reference (@MainCalls.callModel_tokenMatchKind)
    tokenMatchLengthEquation :=
      reference (@MainCalls.callModel_tokenMatchLength)
    tokenMatchEquation := reference (@MainCalls.callModel_tokenMatch)
    matchSymbolHeadEquation :=
      reference (@MainCalls.callModel_matchSymbolHead)
  }⟩

end Lanius.Extraction.Symbol.FunctionalViewCoverage
