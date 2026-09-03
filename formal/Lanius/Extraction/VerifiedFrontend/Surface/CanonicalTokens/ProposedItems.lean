import Lanius.Extraction.VerifiedFrontend.Surface.CanonicalTokens.Reconstruction.Base
namespace Lanius.Extraction
def verifiedFrontendCanonicalTokensProposedItemsKernel : List SurfaceItem := verifiedFrontendCanonicalTokensProposedKernel.value.items
private instance : Inhabited SurfaceItem := ⟨{
  id := 0, parse_node := 0,
  value := .import_path { id := 0, parse_node := 0, value := { segments := [] } }
}⟩
def verifiedFrontendCanonicalTokensProposedItemKernel (index : Nat) : SurfaceItem :=
  verifiedFrontendCanonicalTokensProposedItemsKernel[index]!
theorem verifiedFrontendCanonicalTokensProposedItemsKernel_length : verifiedFrontendCanonicalTokensProposedItemsKernel.length = 6 := by
  with_unfolding_all rfl
end Lanius.Extraction
