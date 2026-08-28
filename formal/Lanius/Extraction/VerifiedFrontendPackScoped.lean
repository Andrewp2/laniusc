import Lanius.Extraction.GlobalResolutionEvidenceChecker
import Lanius.Extraction.VerifiedFrontendPack

namespace Lanius.Extraction

/-- Every local and cross-module source use retains the exact declaration
    selected by the checked namespace resolver.  This is projected from the
    complete certificate rather than produced by a second pack checker. -/
def verifiedFrontendPackResolution :
    GlobalResolutionEvidenceChecker.CheckedPackResolution verifiedFrontendPack
      verifiedFrontendPackChecked.semantics.context :=
  verifiedFrontendPackChecked.scopedResolution

end Lanius.Extraction
