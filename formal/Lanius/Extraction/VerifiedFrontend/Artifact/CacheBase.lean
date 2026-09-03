import Lanius.Extraction.ArtifactCacheQuote
import Lanius.Extraction.ArtifactView

namespace Lanius.Extraction

def artifactCacheOfTrees
    (trees : Lanius.Data.SeqTree ParseNode × Lanius.Data.SeqTree Token ×
      Lanius.Data.SeqTree (Fin 256)) : ArtifactCache := {
  leafCapacity := 64
  parseNodes := trees.1
  tokens := trees.2.1
  primarySourceBytes := trees.2.2
}

end Lanius.Extraction
