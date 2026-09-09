import Lanius.Extraction.CompactOutput.Word.Assign
import Lanius.Extraction.SemanticTokens.Storage

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties
open Lanius.Extraction.SemanticTokens

def childSlot : Expr := binary .add (binary .add (read 10) (number 4))
  (binary .multiply (read 13) (number 3))

/-- Derive every child-triple address bound from the materializer's existing
record-storage contract. No packed copy or alternate record model is needed. -/
theorem child_slot (program : Program) (record : RecordVisit) (words : List Int) (child : Nat)
    (stored : record.Stored 0 words) (bound : child < record.children.length)
    (sizeFit : words.length ≤ 2147483647)
    (recordRead : before.local? 10 = some (.signed .i32 record.offset))
    (childRead : before.local? 13 = some (.signed .i32 child)) :
    Evaluates program before childSlot (.signed .i32 (record.offset + 4 + child * 3 : Nat)) before ∧
    record.offset + 4 + child * 3 + 2 < words.length := by
  have storage := stored.bounds
  simp only [Nat.zero_add] at storage
  have header := evaluatesNatI32Add (leftValue := record.offset) (rightValue := 4)
    (local_evaluates program recordRead)
    (show Evaluates program before (number 4) (.signed .i32 4) before from ⟨1, rfl⟩) (by omega)
  have stride := evaluatesNatI32Multiply (leftValue := child) (rightValue := 3)
    (local_evaluates program childRead)
    (show Evaluates program before (number 3) (.signed .i32 3) before from ⟨1, rfl⟩) (by omega)
  exact ⟨evaluatesNatI32Add header stride (by omega), by omega⟩

end Lanius.Extraction.CompactOutput.Nodes
