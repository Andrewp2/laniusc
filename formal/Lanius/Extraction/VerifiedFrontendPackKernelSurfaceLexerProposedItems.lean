import Lanius.Extraction.VerifiedFrontendPackKernelSurfaceLexerReconstructBase

namespace Lanius.Extraction

def verifiedFrontendLexerProposedItemsKernel : List SurfaceItem :=
  verifiedFrontendLexerProposedKernel.value.items

private instance : Inhabited SurfaceItem := ⟨{
  id := 0
  parse_node := 0
  value := .import_path { id := 0, parse_node := 0, value := { segments := [] } }
}⟩

def verifiedFrontendLexerProposedItemKernel (index : Nat) : SurfaceItem :=
  verifiedFrontendLexerProposedItemsKernel[index]!

theorem verifiedFrontendLexerProposedItemsKernel_length :
    verifiedFrontendLexerProposedItemsKernel.length = 28 := by
  with_unfolding_all rfl

end Lanius.Extraction
