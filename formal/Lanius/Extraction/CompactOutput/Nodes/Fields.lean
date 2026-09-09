import Lanius.Extraction.CompactOutput.Nodes.Validate
import Lanius.Extraction.CompactOutput.Nodes.Write

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Compiler.Parser ParserTreeLayout Lanius.Extraction.SemanticTokens

def encodeChild (child : ChildVisit) : List Nat :=
  childEncoding (childTag child.reference).toNat (childPayload child.reference).toNat

/-- Existing child variants have nonnegative wire values. Reference bounds
imply the signed-word writer's range requirements, without another premise
for each stored field. -/
theorem child_fields (child : ChildVisit) (count node : Nat)
    (countFit : count ≤ 2147483647) (nodeFit : node ≤ 2147483647)
    (linked : child.Linked 0 records node)
    (tokenBound : ∀ use, child = .token use → use.token < count) :
    Int.ofNat (childTag child.reference).toNat = childTag child.reference ∧
    Int.ofNat (childPayload child.reference).toNat = childPayload child.reference ∧
    (childTag child.reference).toNat ≤ 2147483647 ∧
    (childPayload child.reference).toNat ≤ 2147483647 := by
  cases child with
  | token use =>
    have bound := tokenBound use rfl
    simp only [ChildVisit.reference, childTag, childPayload, Int.toNat_natCast, Int.ofNat_eq_natCast]
    exact ⟨rfl, trivial, by decide, by omega⟩
  | node id start finish =>
    have bound := linked.2.1
    simp only [ChildVisit.reference, childTag, childPayload, Int.toNat_natCast, Int.ofNat_eq_natCast]
    exact ⟨rfl, trivial, by decide, by omega⟩

theorem encodeChild_length (child : ChildVisit) : (encodeChild child).length = 16 := by
  simp [encodeChild, childEncoding, hexDigits_length]

end Lanius.Extraction.CompactOutput.Nodes
