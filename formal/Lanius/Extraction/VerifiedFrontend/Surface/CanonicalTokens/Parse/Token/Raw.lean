import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Raw.Scan.Assembly

namespace Lanius.Extraction
set_option maxRecDepth 100000

theorem verifiedFrontendCanonicalTokens_token_raw_trace_checked_kernel :
    checkTokenArtifactRawTrace verifiedFrontendCanonicalTokensArtifact = true := by
  unfold checkTokenArtifactRawTrace
  rw [verifiedFrontendCanonicalTokens_source_decoded_found_kernel,
    verifiedFrontendCanonicalTokens_raw_rows_found_kernel]
  simp only
  rw [verifiedFrontendCanonicalTokens_raw_tokens_decoded_found_kernel]
  simp only
  unfold checkRawTokenTrace
  rw [checkRawTokenTraceFrom_eq_segment,
    verifiedFrontendCanonicalTokens_raw_scan_segmented_kernel]
  with_unfolding_all rfl

end Lanius.Extraction
