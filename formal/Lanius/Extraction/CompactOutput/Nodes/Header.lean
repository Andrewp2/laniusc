import Lanius.Extraction.CompactOutput.Nodes.Source

namespace Lanius.Extraction.CompactOutput.Nodes

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Compiler.Parser ParserTreeLayout Lanius.Extraction.SemanticTokens

/-- All four header values come from the parser's existing record layout. -/
theorem read_header (program : Program) (record : RecordVisit)
    (input : I32PrefixLocal before 0 inputCell words)
    (stored : record.Stored 0 words)
    (base : before.local? 10 = some (.signed .i32 record.offset))
    (sizeFit : words.length ≤ 2147483647) :
    Evaluates program before (.index (read 0) (read 10)) (.signed .i32 record.production) before ∧
    Evaluates program before (recordRead 1) (.signed .i32 record.start) before ∧
    Evaluates program before (recordRead 2) (.signed .i32 record.finish) before ∧
    Evaluates program before (recordRead 3) (.signed .i32 record.children.length) before := by
  have production : words[record.offset]? = some (Int.ofNat record.production) := by
    simpa only [Nat.add_zero] using stored.get (index := 0)
      (by simp [RecordVisit.words, recordHeader])
  obtain ⟨start, finish, count⟩ := stored.header
  have baseRun := local_evaluates program base
  have selected (field value : Nat)
      (found : words[record.offset + field]? = some (Int.ofNat value)) :
      Evaluates program before (recordRead field) (.signed .i32 value) before := by
    have bound := (List.getElem?_eq_some_iff.mp found).1
    have address := evaluatesNatI32Add (leftValue := record.offset) (rightValue := field)
      baseRun (show Evaluates program before (number field) (.signed .i32 field) before from ⟨1, rfl⟩) (by omega)
    exact Collect.read_word program input _ _ found address
  exact ⟨Collect.read_word program input _ _ production baseRun,
    selected 1 _ start, selected 2 _ finish, selected 3 _ count⟩

/-- Storage supplies the range premise for the real header guard. -/
theorem record_guard_pass (program : Program) (record : RecordVisit)
    (stored : record.Stored 0 words) (inputRoom : words.length ≤ inputLength)
    (inputFit : inputLength ≤ 2147483647)
    (base : before.local? 10 = some (.signed .i32 record.offset))
    (lengthRead : before.local? 1 = some (.signed .i32 inputLength)) :
    Evaluates program before recordGuard (.boolean false) before := by
  have bounds := stored.bounds
  have offsetResult := local_evaluates program base
  have lengthResult := local_evaluates program lengthRead
  have nonnegative := Collect.lessEqual_evaluates offsetResult (negativeOne_evaluates program before)
  have inside := Collect.negate_evaluates (Collect.lessEqual_evaluates offsetResult lengthResult)
  have remaining := evaluatesNatI32Subtract (leftValue := inputLength) (rightValue := record.offset)
    lengthResult offsetResult (by omega) (by omega)
  have header := Collect.lessEqual_evaluates remaining
    (show Evaluates program before (number 3) (.signed .i32 3) before from ⟨1, rfl⟩)
  have all := evaluatesPureLogicalOr (evaluatesPureLogicalOr nonnegative inside) header
  have notNegative : ¬ ((record.offset : Int) ≤ -1) := by omega
  have inRange : (record.offset : Int) ≤ inputLength := by omega
  have notShort : ¬ (((inputLength - record.offset : Nat) : Int) ≤ 3) := by omega
  simpa only [recordGuard, Int.ofNat_eq_natCast, notNegative, inRange, notShort,
    decide_true, decide_false, Bool.false_or, Bool.not_true] using all

/-- The child-count guard follows from the full stored record, including its
three-word child entries, even when the input slice has spare words. -/
theorem children_guard_pass (program : Program) (record : RecordVisit)
    (stored : record.Stored 0 words) (inputRoom : words.length ≤ inputLength)
    (inputFit : inputLength ≤ 2147483647)
    (base : before.local? 10 = some (.signed .i32 record.offset))
    (lengthRead : before.local? 1 = some (.signed .i32 inputLength))
    (productionRead : before.local? 11 = some (.signed .i32 record.production))
    (childrenRead : before.local? 12 = some (.signed .i32 record.children.length)) :
    Evaluates program before childrenGuard (.boolean false) before := by
  have room := stored.bounds
  have leftover := evaluatesNatI32Subtract (leftValue := inputLength) (rightValue := record.offset)
    (local_evaluates program lengthRead) (local_evaluates program base) (by omega) (by omega)
  have payload := evaluatesNatI32Subtract (leftValue := inputLength - record.offset) (rightValue := 4)
    leftover (show Evaluates program before (number 4) (.signed .i32 4) before from ⟨1, rfl⟩) (by omega) (by omega)
  have slots := evaluatesNatI32Divide (leftValue := inputLength - record.offset - 4) (rightValue := 3)
    payload (show Evaluates program before (number 3) (.signed .i32 3) before from ⟨1, rfl⟩)
    (by decide) (by have := Nat.div_le_self (inputLength - record.offset - 4) 3; omega)
  have count := local_evaluates program childrenRead
  have negativeProduction := Collect.lessEqual_evaluates (local_evaluates program productionRead)
    (negativeOne_evaluates program before)
  have negativeCount := Collect.lessEqual_evaluates count (negativeOne_evaluates program before)
  have enough := Collect.negate_evaluates (Collect.lessEqual_evaluates count slots)
  have all := evaluatesPureLogicalOr (evaluatesPureLogicalOr negativeProduction negativeCount) enough
  have productionNonnegative : ¬ ((record.production : Int) ≤ -1) := by omega
  have countNonnegative : ¬ ((record.children.length : Int) ≤ -1) := by omega
  have countFits : (record.children.length : Int) ≤ ((inputLength - record.offset - 4) / 3 : Nat) := by omega
  simpa only [childrenGuard, Int.ofNat_eq_natCast, productionNonnegative, countNonnegative,
    countFits, decide_false, decide_true, Bool.not_true, Bool.false_or] using all

end Lanius.Extraction.CompactOutput.Nodes
