import Lanius.Relational.Reification
import Lanius.Extraction.Lexer.Relational.Functions

namespace Lanius.Extraction.Lexer.Relational.IdentifierEnd

open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.Relational

/-- The pilot command is the command mechanically recovered from the checked
frontend artifact, not a handwritten scanner AST. -/
def reification : Reifies Functions.scanIdentifierEnd
    Scanners.scanIdentifierEndView.command where
  layout := identityLayout
  nextLocal := 3
  adapter := actionAdapter
  argumentCount := by rfl
  below := LayoutBelow.identity
  exact := Scanners.scanIdentifierEndView_toCore_exactly

end Lanius.Extraction.Lexer.Relational.IdentifierEnd
