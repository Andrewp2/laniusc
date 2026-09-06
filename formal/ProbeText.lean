import SelfClosure.Unit0.View
import Lanius.Extraction.Reconstruction.Chunks
open Lanius.Extraction
open Lanius.Data
set_option maxRecDepth 100000
namespace ExtractedUnit0
noncomputable section
local instance : ArtifactAccess := ArtifactAccess.ofView extractedView

example : artifactTokenText? extracted 755 =
    artifactTokenText? extractedSyntax 755 := by
  rfl

end ExtractedUnit0
