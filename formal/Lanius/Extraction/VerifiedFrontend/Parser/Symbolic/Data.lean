import Lanius.Extraction.SymbolicLocalChecker
import Lanius.Extraction.VerifiedFrontend.Parser.Certificate
import Lanius.Extraction.Reduction

namespace Lanius.Extraction

set_option maxRecDepth 100000
set_option maxHeartbeats 1000000
set_option compiler.extract_closed false

open Lanius.Extraction.SymbolicLocalChecker

/-- Compute the legacy proof metadata once. The retained equality authenticates
the materialized value against the same source-scoping/Core derivation; later
frame lookups do not repeat that derivation inside each closed proof. Retain
the optional result itself so proving success does not run the derivation first.
The scoped source's use-resolution rows stay as their original expression:
frame consumers inspect its graph, bindings, and statements, not this separate
resolution table. The equality below still covers every field. -/
private def parserSymbolicData :
    { result : Option (List DerivedFunction) // result =
      deriveArtifact? verifiedParserArtifact verifiedParserScopedArtifact } :=
  reduce_data% retaining [ScopedSurface.CheckedUse]
    (deriveArtifact? verifiedParserArtifact verifiedParserScopedArtifact)

/-- The symbolic-local stage succeeds for the exact scoped parser value. -/
theorem verifiedParser_symbolic_derivation_accepted :
    (deriveArtifact? verifiedParserArtifact verifiedParserScopedArtifact).isSome =
      true := by
  rw [← parserSymbolicData.property]
  decide

def verifiedParserSymbolicFunctions : List DerivedFunction :=
  parserSymbolicData.val.get (by decide)

theorem verifiedParser_symbolic_functions_derived :
    deriveArtifact? verifiedParserArtifact verifiedParserScopedArtifact =
      some verifiedParserSymbolicFunctions := by
  rw [← parserSymbolicData.property]
  exact (Option.some_get (by decide)).symm

end Lanius.Extraction
