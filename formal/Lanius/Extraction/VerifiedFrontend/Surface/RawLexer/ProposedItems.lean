import Lanius.Extraction.VerifiedFrontend.Surface.RawLexer.Reconstruction.Base
namespace Lanius.Extraction
def verifiedFrontendRawLexerProposedItemsKernel : List SurfaceItem := verifiedFrontendRawLexerProposedKernel.value.items
private instance : Inhabited SurfaceItem := ⟨{
  id := 0, parse_node := 0,
  value := .import_path { id := 0, parse_node := 0, value := { segments := [] } }
}⟩
def verifiedFrontendRawLexerProposedItemKernel (index : Nat) : SurfaceItem :=
  verifiedFrontendRawLexerProposedItemsKernel[index]!
theorem verifiedFrontendRawLexerProposedItemsKernel_length : verifiedFrontendRawLexerProposedItemsKernel.length = 18 := by
  with_unfolding_all rfl
end Lanius.Extraction
