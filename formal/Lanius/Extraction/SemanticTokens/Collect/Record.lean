import Lanius.Extraction.SemanticTokens.Collect.Grammar
import Lanius.Extraction.SemanticTokens.Records

namespace Lanius.Extraction.SemanticTokens

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Compiler.Parser ParserTreeLayout

theorem RecordVisit.Stored.get {record : RecordVisit} {words : List Int} {index : Nat}
    (stored : record.Stored 0 words) (found : record.words[index]? = some value) :
    words[record.offset + index]? = some value := by
  obtain ⟨before, after, rfl, offset⟩ := stored
  simp only [Nat.zero_add] at offset
  rw [offset, List.append_assoc, List.getElem?_append_right (by omega : before.length ≤ before.length + index)]
  simp only [Nat.add_sub_cancel_left]
  rw [List.getElem?_append_left (List.getElem?_eq_some_iff.mp found).1]
  exact found

theorem RecordVisit.Stored.header {record : RecordVisit} {words : List Int}
    (stored : record.Stored 0 words) :
    words[record.offset + 1]? = some (Int.ofNat record.start) ∧
    words[record.offset + 2]? = some (Int.ofNat record.finish) ∧
    words[record.offset + 3]? = some (Int.ofNat record.children.length) := by
  refine ⟨stored.get ?_, stored.get ?_, stored.get ?_⟩ <;>
    simp [RecordVisit.words, recordHeader]

private theorem child_fields (children : List ChildVisit) (found : children[index]? = some child) :
    (children.flatMap (fun c => derivationChildWords c.reference))[index * 3]? = some (childTag child.reference) ∧
    (children.flatMap (fun c => derivationChildWords c.reference))[index * 3 + 1]? = some (childPayload child.reference) ∧
    (children.flatMap (fun c => derivationChildWords c.reference))[index * 3 + 2]? = some (childKind child.reference) := by
  induction children generalizing index with
  | nil => simp at found
  | cons first rest ih =>
    cases index with
    | zero =>
      have same : first = child := by simpa using found
      subst first
      simp [derivationChildWords]
    | succ index =>
      have tail := ih found
      simpa [derivationChildWords, Nat.add_mul, Nat.add_assoc] using tail

theorem RecordVisit.Stored.child {record : RecordVisit} {words : List Int} {index : Nat} {child : ChildVisit}
    (stored : record.Stored 0 words) (found : record.children[index]? = some child) :
    words[record.offset + 4 + index * 3]? = some (childTag child.reference) ∧
    words[record.offset + 4 + index * 3 + 1]? = some (childPayload child.reference) ∧
    words[record.offset + 4 + index * 3 + 2]? = some (childKind child.reference) := by
  obtain ⟨tag, payload, kind⟩ := child_fields record.children found
  have lift (field : Nat) (value : Int)
      (selected : (record.children.flatMap (fun c => derivationChildWords c.reference))[index * 3 + field]? = some value) :
      words[record.offset + 4 + index * 3 + field]? = some value := by
    have inner : record.words[4 + (index * 3 + field)]? = some value := by
      rw [Nat.add_comm 4]
      simpa [RecordVisit.words, recordHeader] using selected
    simpa only [Nat.add_assoc] using stored.get inner
  exact ⟨by simpa using lift 0 _ (by simpa using tag), lift 1 _ payload, lift 2 _ kind⟩

namespace Collect

/-- Read a word whose value follows from the logical storage contract. Spare
physical capacity is retained by I32PrefixLocal and is not decoded as input. -/
theorem read_word {id : VarId} (program : Program) (owned : I32PrefixLocal state id cell words)
    (indexExpression : Expr) (index : Nat) (found : words[index]? = some value)
    (evaluated : Evaluates program state indexExpression (.signed .i32 index) state) :
    Evaluates program state (atIndex id indexExpression) (.signed .i32 value) state := by
  have bound := (List.getElem?_eq_some_iff.mp found).1
  have selected : words.get ⟨index, bound⟩ = value := by
    simpa only [List.getElem?_eq_getElem bound, Option.some.injEq, List.get_eq_getElem] using found
  simpa only [selected] using owned.read program indexExpression index bound evaluated

/-- The real header-range guard passes because the stored record includes
four header words. It is not a separate accepted-record hypothesis. -/
theorem recordGuard_pass (program : Program) (id : VarId) (offset capacity : Nat)
    (offsetRead : state.local? id = some (.signed .i32 offset))
    (capacityRead : state.local? 5 = some (.signed .i32 capacity))
    (room : offset + 4 ≤ capacity) (capacityFit : capacity ≤ 2147483647) :
    Evaluates program state (recordGuard id) (.boolean false) state := by
  have offsetResult := local_evaluates program offsetRead
  have capacityResult := local_evaluates program capacityRead
  have nonnegative := lessEqual_evaluates offsetResult (negativeOne_evaluates program state)
  have inside := negate_evaluates (lessEqual_evaluates offsetResult capacityResult)
  have remaining := evaluatesNatI32Subtract (leftValue := capacity) (rightValue := offset)
    capacityResult offsetResult (by omega) (by omega)
  have header := lessEqual_evaluates remaining
    (show Evaluates program state (number 3) (.signed .i32 3) state from ⟨1, rfl⟩)
  have all := evaluatesPureLogicalOr (evaluatesPureLogicalOr nonnegative inside) header
  have notNegative : ¬ ((offset : Int) ≤ -1) := by omega
  have inRange : (offset : Int) ≤ capacity := by omega
  have notShort : ¬ (((capacity - offset : Nat) : Int) ≤ 3) := by omega
  simpa only [recordGuard, Int.ofNat_eq_natCast, notNegative, inRange, notShort,
    decide_true, decide_false, Bool.false_or, Bool.not_true] using all

theorem record_header_read {record : RecordVisit} (program : Program) (owned : I32PrefixLocal state 4 cell words)
    (stored : record.Stored 0 words) (base : Expr)
    (baseRead : Evaluates program state base (.signed .i32 record.offset) state)
    (wordsFit : words.length ≤ 2147483647) :
    Evaluates program state (atIndex 4 (binary .add base (number 1))) (.signed .i32 record.start) state ∧
    Evaluates program state (atIndex 4 (binary .add base (number 2))) (.signed .i32 record.finish) state ∧
    Evaluates program state (atIndex 4 (binary .add base (number 3))) (.signed .i32 record.children.length) state := by
  have bound := stored.bounds
  obtain ⟨start, finish, count⟩ := stored.header
  have selected (field value : Nat) (fieldBound : field ≤ 3)
      (found : words[record.offset + field]? = some (Int.ofNat value)) :
      Evaluates program state (atIndex 4 (binary .add base (number field))) (.signed .i32 value) state := by
    have address := evaluatesNatI32Add (leftValue := record.offset) (rightValue := field) baseRead
      (show Evaluates program state (number field) (.signed .i32 field) state from ⟨1, rfl⟩) (by omega)
    simpa only [Int.ofNat_eq_natCast] using read_word program owned _ _ found address
  exact ⟨selected 1 _ (by decide) start, selected 2 _ (by decide) finish, selected 3 _ (by decide) count⟩

theorem record_child_read {record : RecordVisit} {child : ChildVisit} {index : Nat}
    (program : Program) (owned : I32PrefixLocal state 4 cell words)
    (stored : record.Stored 0 words) (found : record.children[index]? = some child)
    (slot : Expr)
    (slotRead : Evaluates program state slot (.signed .i32 (record.offset + 4 + index * 3)) state)
    (wordsFit : words.length ≤ 2147483647) :
    Evaluates program state (atIndex 4 slot) (.signed .i32 (childTag child.reference)) state ∧
    Evaluates program state (atIndex 4 (binary .add slot (number 1))) (.signed .i32 (childPayload child.reference)) state ∧
    Evaluates program state (atIndex 4 (binary .add slot (number 2))) (.signed .i32 (childKind child.reference)) state := by
  obtain ⟨tag, payload, kind⟩ := stored.child found
  have selected (field : Nat) (value : Int)
      (found : words[record.offset + 4 + index * 3 + field]? = some value) :
      Evaluates program state (atIndex 4 (binary .add slot (number field))) (.signed .i32 value) state := by
    have bound := (List.getElem?_eq_some_iff.mp found).1
    exact read_word program owned _ _ found
      (evaluatesNatI32Add (leftValue := record.offset + 4 + index * 3) (rightValue := field)
        slotRead ⟨1, rfl⟩ (by omega))
  exact ⟨read_word program owned _ _ tag slotRead, selected 1 _ payload, selected 2 _ kind⟩

end Collect
end Lanius.Extraction.SemanticTokens
