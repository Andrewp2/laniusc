import Lanius.Core

namespace Lanius.Extraction.Symbol.Semantics

open Lanius.Core

/-- Checked Core encoding of the `TokenMatch` structure. -/
def value (kind length : Int) : Value :=
  .structure 3 [.signed .i32 kind, .signed .i32 length]

end Lanius.Extraction.Symbol.Semantics
