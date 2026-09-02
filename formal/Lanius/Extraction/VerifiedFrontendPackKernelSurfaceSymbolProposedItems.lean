import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceSymbolReconstructBase
namespace Lanius.Extraction
def verifiedFrontendSymbolProposedItemsKernel : List SurfaceItem := verifiedFrontendSymbolProposedKernel.value.items
private instance : Inhabited SurfaceItem := ⟨{
  id := 0, parse_node := 0,
  value := .import_path { id := 0, parse_node := 0, value := { segments := [] } }
}⟩
def verifiedFrontendSymbolProposedItemKernel (index : Nat) : SurfaceItem :=
  verifiedFrontendSymbolProposedItemsKernel[index]!
theorem verifiedFrontendSymbolProposedItemsKernel_length : verifiedFrontendSymbolProposedItemsKernel.length = 7 := by
  with_unfolding_all rfl
end Lanius.Extraction
