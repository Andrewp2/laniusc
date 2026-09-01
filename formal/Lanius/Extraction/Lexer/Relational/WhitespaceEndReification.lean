import Lanius.Relational.Reification
import Lanius.Extraction.Lexer.Relational.Functions

namespace Lanius.Extraction.Lexer.Relational.WhitespaceEnd

open Lanius.FunctionalView.Core
open Lanius.FunctionalView.Core.Stateful
open Lanius.Relational

def reification : Reifies Functions.scanWhitespaceEnd
    Scanners.scanWhitespaceEndView.command where
  layout := identityLayout
  nextLocal := 3
  adapter := actionAdapter
  argumentCount := by rfl
  below := LayoutBelow.identity
  exact := Scanners.scanWhitespaceEndView_toCore_exactly

end Lanius.Extraction.Lexer.Relational.WhitespaceEnd
