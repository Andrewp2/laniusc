import Lanius.Extraction.VerifiedFrontend.Surface.Symbol.Raw.Scan.Assembly
namespace Lanius.Extraction
set_option maxRecDepth 100000
set_option maxHeartbeats 0
theorem verifiedFrontendSymbol_token_raw_trace_checked_kernel :
    checkTokenArtifactRawTrace verifiedFrontendSymbolArtifact = true := by
  unfold checkTokenArtifactRawTrace
  rw [verifiedFrontendSymbol_source_decoded_found_kernel,
    verifiedFrontendSymbol_raw_rows_found_kernel]
  simp only
  rw [verifiedFrontendSymbol_raw_tokens_decoded_found_kernel]
  simp only
  unfold checkRawTokenTrace
  rw [checkRawTokenTraceFrom_eq_segment,
    verifiedFrontendSymbol_raw_scan_segmented_kernel]
  with_unfolding_all rfl
end Lanius.Extraction
