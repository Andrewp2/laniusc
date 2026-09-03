import Lanius.Relational.CheckedProgram
import Lanius.Extraction.VerifiedLexerProgram
import Lanius.Extraction.VerifiedFrontend.Native

namespace Lanius.Extraction

open Lanius.Relational

/-- Relational-proof facade for the already accepted frontend artifact pack. -/
def checkedFrontend : CheckedProgram where
  pack := verifiedFrontendPack
  checked := verifiedFrontendPackChecked
  core := verifiedFrontendCore
  core_eq := rfl

end Lanius.Extraction
