import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Parse.Chunk0
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Parse.Chunk1
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Parse.Chunk2
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Parse.Chunk3
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Parse.Chunk4
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Parse.Chunk5
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Parse.Chunk6
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Parse.Chunk7

namespace Lanius.Extraction
open Lanius.Data

def verifiedFrontendCanonicalTokensParseNodeTree : SeqTree ParseNode :=
  .branch 10311 9
    (.branch 5155 8
      (.branch 2577 7 verifiedFrontendCanonicalTokensParseNodeTree0
        verifiedFrontendCanonicalTokensParseNodeTree1)
      (.branch 2578 7 verifiedFrontendCanonicalTokensParseNodeTree2
        verifiedFrontendCanonicalTokensParseNodeTree3))
    (.branch 5156 8
      (.branch 2578 7 verifiedFrontendCanonicalTokensParseNodeTree4
        verifiedFrontendCanonicalTokensParseNodeTree5)
      (.branch 2578 7 verifiedFrontendCanonicalTokensParseNodeTree6
        verifiedFrontendCanonicalTokensParseNodeTree7))

end Lanius.Extraction
