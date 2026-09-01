import Lanius.Extraction.VerifiedFrontendPack
import Lanius.Extraction.CompleteChecker

namespace Lanius.Extraction

/-! The fast native whole-pack certificate is deliberately kept out of the
generated artifact-data module.  Kernel certificate modules can now depend on
the immutable data without being invalidated by changes to later checkers. -/

theorem verifiedFrontendPack_completely_checked :
    (CompleteChecker.checkPack? verifiedFrontendPack).isSome = true := by
  native_decide

/-- The complete multi-unit frontend certificate.  All later pack views are
    projections of this one accepted value. -/
def verifiedFrontendPackChecked :
    CompleteChecker.CheckedPack verifiedFrontendPack :=
  (CompleteChecker.checkPack? verifiedFrontendPack).get
    verifiedFrontendPack_completely_checked

end Lanius.Extraction
