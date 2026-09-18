import Lanius.Extraction.Entry.Files.Request

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics

/-- Every pending file succeeds within its independently checked output
budget. The final cursor leaves any separately reserved suffix space intact. -/
def Progress (sources : List SourceFile) (cursor : VarId) (position : Int)
    (completion : Completion) (after : State) : Prop :=
  ∀ bounds, SourceDomains sources bounds → 0 ≤ position →
    position.toNat + bounds.sum ≤ 16777216 →
      completion = .next ∧ ∃ finalPosition : Nat,
        after.local? cursor = some (.signed .i32 finalPosition) ∧
        finalPosition ≤ position.toNat + bounds.sum

end Lanius.Extraction.Entry.Files
