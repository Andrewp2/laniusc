import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensRawSegment0
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensRawSegment1
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensRawSegment2
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensRawSegment3
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensRawSegment4
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensRawSegment5
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceCanonicalTokensRawSplit

namespace Lanius.Extraction
set_option maxRecDepth 100000

theorem verifiedFrontendCanonicalTokens_raw_scan_segmented_kernel :
    scanRawTokenSegment verifiedFrontendCanonicalTokensDecodedSource 0
      verifiedFrontendCanonicalTokensDecodedRawTokens =
      some (verifiedFrontendCanonicalTokensDecodedSource.drop 6268, 6268) := by
  have segment0 :
      scanRawTokenSegment verifiedFrontendCanonicalTokensDecodedSource 0
        (verifiedFrontendCanonicalTokensDecodedRawTokens.take 500) =
        some (verifiedFrontendCanonicalTokensDecodedSource.drop 1271, 1271) := by
    simpa using verifiedFrontendCanonicalTokens_raw_segment_0_kernel
  rw [verifiedFrontendCanonicalTokens_raw_tokens_split_kernel,
    scanRawTokenSegment_append, segment0]
  simp only
  rw [scanRawTokenSegment_append,
    verifiedFrontendCanonicalTokens_raw_segment_1_kernel]
  simp only
  rw [scanRawTokenSegment_append,
    verifiedFrontendCanonicalTokens_raw_segment_2_kernel]
  simp only
  rw [scanRawTokenSegment_append,
    verifiedFrontendCanonicalTokens_raw_segment_3_kernel]
  simp only
  rw [scanRawTokenSegment_append,
    verifiedFrontendCanonicalTokens_raw_segment_4_kernel]
  simp only
  simpa using
    verifiedFrontendCanonicalTokens_raw_segment_5_kernel

end Lanius.Extraction
