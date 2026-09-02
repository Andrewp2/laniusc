import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolRawSegment0
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolRawSegment1
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolRawSegment2
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolRawSegment3
import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolRawSplit
namespace Lanius.Extraction
set_option maxRecDepth 100000
theorem verifiedFrontendSymbol_raw_scan_segmented_kernel :
    scanRawTokenSegment verifiedFrontendSymbolDecodedSource 0
      verifiedFrontendSymbolDecodedRawTokens =
      some (verifiedFrontendSymbolDecodedSource.drop 5564, 5564) := by
  have segment0 :
      scanRawTokenSegment verifiedFrontendSymbolDecodedSource 0
        (verifiedFrontendSymbolDecodedRawTokens.take 500) =
        some (verifiedFrontendSymbolDecodedSource.drop 1686, 1686) := by
    simpa using verifiedFrontendSymbol_raw_segment_0_kernel
  rw [verifiedFrontendSymbol_raw_tokens_split_kernel,
    scanRawTokenSegment_append, segment0]
  simp only
  rw [scanRawTokenSegment_append, verifiedFrontendSymbol_raw_segment_1_kernel]
  simp only
  rw [scanRawTokenSegment_append, verifiedFrontendSymbol_raw_segment_2_kernel]
  simp only
  simpa using verifiedFrontendSymbol_raw_segment_3_kernel
end Lanius.Extraction
