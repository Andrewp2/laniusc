import Lanius.Extraction.CompactOutput.Nodes.Source

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser ParserTreeLayout Lanius.Extraction.SemanticTokens

def slotState (before : State) (record : RecordVisit) (index : Nat) : State :=
  before.bindLocal 14 (.signed .i32 (record.offset + 4 + index * 3 : Nat))
def tagState (before : State) (record : RecordVisit) (index : Nat) (child : ChildVisit) : State :=
  (slotState before record index).bindLocal 15 (.signed .i32 (childTag child.reference))
def childState (before : State) (record : RecordVisit) (index : Nat) (child : ChildVisit) : State :=
  (tagState before record index child).bindLocal 16 (.signed .i32 (childPayload child.reference))

theorem initialize_child (program : Program) (record : RecordVisit) (child : ChildVisit) (index : Nat)
    (wellFormed : StateWellFormed before)
    (input : I32PrefixLocal before 0 inputCell words)
    (stored : record.Stored 0 words) (found : record.children[index]? = some child)
    (recordRead : before.local? 10 = some (.signed .i32 record.offset))
    (indexRead : before.local? 13 = some (.signed .i32 index))
    (sizeFit : words.length ≤ 2147483647) :
    Evaluates program before childSlot (.signed .i32 (record.offset + 4 + index * 3 : Nat)) before ∧
    Evaluates program (slotState before record index) tagRead (.signed .i32 (childTag child.reference))
      (slotState before record index) ∧
    Evaluates program (tagState before record index child) payloadRead (.signed .i32 (childPayload child.reference))
      (tagState before record index child) ∧
    StateWellFormed (childState before record index child) ∧
    (childState before record index child).local? 15 = some (.signed .i32 (childTag child.reference)) ∧
    (childState before record index child).local? 16 = some (.signed .i32 (childPayload child.reference)) ∧
    I32PrefixLocal (childState before record index child) 0 inputCell words := by
  have slotWF : StateWellFormed (slotState before record index) := bindLocal_preserves_well_formed _ _ _ wellFormed
  have slotInput := input.bindLocal wellFormed 14 (.signed .i32 (record.offset + 4 + index * 3 : Nat)) (by decide)
  have slotLocal : (slotState before record index).local? 14 = some (.signed .i32 (record.offset + 4 + index * 3 : Nat)) :=
    bindLocal_finds_local before _ _ wellFormed
  have tagWF : StateWellFormed (tagState before record index child) := bindLocal_preserves_well_formed _ _ _ slotWF
  have tagInput := slotInput.bindLocal slotWF 15 (.signed .i32 (childTag child.reference)) (by decide)
  have tagSlot : (tagState before record index child).local? 14 = some (.signed .i32 (record.offset + 4 + index * 3 : Nat)) :=
    (bindLocal_preserves_other_local slotWF (by decide : (15 : VarId) ≠ 14)).trans slotLocal
  exact ⟨(child_slot program record words index stored (List.getElem?_eq_some_iff.mp found).1 sizeFit recordRead indexRead).1,
    (read_child program record child index slotInput stored found slotLocal sizeFit).1,
    (read_child program record child index tagInput stored found tagSlot sizeFit).2,
    bindLocal_preserves_well_formed _ _ _ tagWF,
    (bindLocal_preserves_other_local tagWF (by decide : (16 : VarId) ≠ 15)).trans
      (bindLocal_finds_local (slotState before record index) _ _ slotWF),
    bindLocal_finds_local (tagState before record index child) _ _ tagWF,
    tagInput.bindLocal tagWF 16 (.signed .i32 (childPayload child.reference)) (by decide)⟩

end Lanius.Extraction.CompactOutput.Nodes
