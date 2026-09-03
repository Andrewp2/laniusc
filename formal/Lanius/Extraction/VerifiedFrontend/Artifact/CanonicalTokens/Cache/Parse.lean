import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Parse0
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Parse1
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Parse2
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Parse3
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Parse4
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Parse5
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Parse6
import Lanius.Extraction.VerifiedFrontend.Artifact.CanonicalTokens.Cache.Parse7

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
