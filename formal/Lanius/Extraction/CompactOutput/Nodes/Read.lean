import Lanius.Extraction.CompactOutput.Nodes.Address
import Lanius.Extraction.SemanticTokens.Collect.Record

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser ParserTreeLayout Lanius.Extraction.SemanticTokens

def tagRead : Expr := .index (read 0) (read 14)
def payloadRead : Expr := .index (read 0) (binary .add (read 14) (number 1))

/-- Read the serializer's two wire fields from the original three-word child
record. The semantic-kind word remains in storage but is not emitted here. -/
theorem read_child (program : Program) (record : RecordVisit) (child : ChildVisit) (index : Nat)
    (input : I32PrefixLocal before 0 inputCell words)
    (stored : record.Stored 0 words) (found : record.children[index]? = some child)
    (slot : before.local? 14 = some (.signed .i32 (record.offset + 4 + index * 3 : Nat)))
    (sizeFit : words.length ≤ 2147483647) :
    Evaluates program before tagRead (.signed .i32 (childTag child.reference)) before ∧
    Evaluates program before payloadRead (.signed .i32 (childPayload child.reference)) before := by
  obtain ⟨tag, payload, _⟩ := stored.child found
  have slotRun := local_evaluates program slot
  have payloadBound := (List.getElem?_eq_some_iff.mp payload).1
  have address := evaluatesNatI32Add (leftValue := record.offset + 4 + index * 3) (rightValue := 1)
    slotRun (show Evaluates program before (number 1) (.signed .i32 1) before from ⟨1, rfl⟩) (by omega)
  exact ⟨Collect.read_word program input _ _ tag slotRun,
    Collect.read_word program input _ _ payload address⟩

end Lanius.Extraction.CompactOutput.Nodes
