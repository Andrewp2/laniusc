import Lanius.Extraction.SemanticTokens.Collect.NodeMemory

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.Compiler.Parser ParserTreeLayout

def recordCountGuard : Expr :=
  binary .logicalOr (binary .logicalOr (binary .logicalOr
    (binary .lessEqual (read 15) (negative 1))
    (negate (binary .lessEqual (read 15)
      (binary .divide (binary .subtract (binary .subtract (read 5) (read 14)) (number 4)) (number 3)))))
    (binary .lessEqual (read 16) (negative 1)))
    (negate (binary .lessEqual (read 16) (binary .multiply (read 3) (number 2))))

theorem record_count_guard_pass {record : RecordVisit} (program : Program)
    (stored : record.Stored 0 words) (wordsFit : words.length ≤ 2147483647)
    (tokensFit : tokenCount * 2 ≤ 2147483647) (startBound : record.start ≤ tokenCount * 2)
    (lengthRead : before.local? 5 = some (.signed .i32 words.length))
    (offsetRead : before.local? 14 = some (.signed .i32 record.offset))
    (childrenRead : before.local? 15 = some (.signed .i32 record.children.length))
    (startRead : before.local? 16 = some (.signed .i32 record.start))
    (tokensRead : before.local? 3 = some (.signed .i32 tokenCount)) :
    Evaluates program before recordCountGuard (.boolean false) before := by
  have room := stored.bounds
  have leftover := evaluatesNatI32Subtract (leftValue := words.length) (rightValue := record.offset)
    (local_evaluates program lengthRead) (local_evaluates program offsetRead) (by omega) (by omega)
  have payload := evaluatesNatI32Subtract (leftValue := words.length - record.offset) (rightValue := 4)
    leftover (show Evaluates program before (number 4) (.signed .i32 4) before from ⟨1, rfl⟩) (by omega) (by omega)
  have slots := evaluatesNatI32Divide (leftValue := words.length - record.offset - 4) (rightValue := 3)
    payload (show Evaluates program before (number 3) (.signed .i32 3) before from ⟨1, rfl⟩)
    (by decide) (by have := Nat.div_le_self (words.length - record.offset - 4) 3; omega)
  have count := local_evaluates program childrenRead
  have position := local_evaluates program startRead
  have negativeCount := lessEqual_evaluates count (negativeOne_evaluates program before)
  have enough := negate_evaluates (lessEqual_evaluates count slots)
  have negativeStart := lessEqual_evaluates position (negativeOne_evaluates program before)
  have limit := evaluatesNatI32Multiply (leftValue := tokenCount) (rightValue := 2)
    (local_evaluates program tokensRead) (show Evaluates program before (number 2) (.signed .i32 2) before from ⟨1, rfl⟩) tokensFit
  have inRange := negate_evaluates (lessEqual_evaluates position limit)
  have all := evaluatesPureLogicalOr (evaluatesPureLogicalOr (evaluatesPureLogicalOr negativeCount enough) negativeStart) inRange
  have countNonnegative : ¬ ((record.children.length : Int) ≤ -1) := by omega
  have countFits : (record.children.length : Int) ≤ ((words.length - record.offset - 4) / 3 : Nat) := by omega
  have startNonnegative : ¬ ((record.start : Int) ≤ -1) := by omega
  have startFits : (record.start : Int) ≤ (tokenCount * 2 : Nat) := by omega
  simpa only [recordCountGuard, Int.ofNat_eq_natCast, countNonnegative, countFits, startNonnegative, startFits,
    decide_false, decide_true, Bool.not_true, Bool.false_or] using all

def recordEntered (before : State) (record : RecordVisit) : State :=
  (((before.bindLocal 14 (.signed .i32 record.offset)).bindLocal 15 (.signed .i32 record.children.length)).bindLocal 16
    (.signed .i32 record.start)).bindLocal 17 (.signed .i32 0)

def NodeOwned.childMemory {memory : NodeMemory} (held : NodeOwned memory index before) : ChildMemory := {
  data := memory.data
  positionCell := before.nextCell + 2
  childCell := before.nextCell + 3
  distinct := by
    have outputOld := StateWellFormed.cell_lt_next_of_entry held.wellFormed held.backing
    dsimp only [CellId] at outputOld ⊢
    exact ⟨by omega, by omega, by omega⟩
  inputs := by
    intro cell member changed
    have old := held.input_old member
    rcases changed with (output | position) | child
    · exact (memory.inputs cell member).1 output
    · dsimp only [CellSet.singleton, CellId] at position old; omega
    · dsimp only [CellSet.singleton, CellId] at child old; omega
}

/-- Construct the child-loop invariant from ordinary outer-loop storage and
the four actual fresh declarations. No fresh-cell or stable-local premise is
delegated to the caller. -/
theorem NodeOwned.children {memory : NodeMemory} (held : NodeOwned memory index before) (record : RecordVisit) :
    ChildOwned held.childMemory record index 0 record.start
      (priorUses memory.data.collection.records index) (recordEntered before record) := by
  let first := before.bindLocal 14 (.signed .i32 record.offset)
  let second := first.bindLocal 15 (.signed .i32 record.children.length)
  let third := second.bindLocal 16 (.signed .i32 record.start)
  have firstHeld : NodeOwned memory index first := held.bindLocal 14 _ (by decide)
  have secondHeld : NodeOwned memory index second := firstHeld.bindLocal 15 _ (by decide)
  have thirdHeld : NodeOwned memory index third := secondHeld.bindLocal 16 _ (by decide)
  have final : NodeOwned memory index (recordEntered before record) := thirdHeld.bindLocal 17 _ (by decide)
  have offsetFirst := bindLocal_owns_fresh before 14 (.signed .i32 record.offset) held.wellFormed
  have offsetSecond := bindLocal_preserves_localPointsTo_of_ne first 15 14 (.signed .i32 record.children.length)
    before.nextCell _ firstHeld.wellFormed (by decide) offsetFirst
  have offsetThird := bindLocal_preserves_localPointsTo_of_ne second 16 14 (.signed .i32 record.start)
    before.nextCell _ secondHeld.wellFormed (by decide) offsetSecond
  have offsetFinal := bindLocal_preserves_localPointsTo_of_ne third 17 14 (.signed .i32 0)
    before.nextCell _ thirdHeld.wellFormed (by decide) offsetThird
  have countSecond := bindLocal_owns_fresh first 15 (.signed .i32 record.children.length) firstHeld.wellFormed
  have countThird := bindLocal_preserves_localPointsTo_of_ne second 16 15 (.signed .i32 record.start)
    first.nextCell _ secondHeld.wellFormed (by decide) countSecond
  have countFinal := bindLocal_preserves_localPointsTo_of_ne third 17 15 (.signed .i32 0)
    first.nextCell _ thirdHeld.wellFormed (by decide) countThird
  have cursorThird := bindLocal_owns_fresh second 16 (.signed .i32 record.start) secondHeld.wellFormed
  have cursorFinal := bindLocal_preserves_localPointsTo_of_ne third 17 16 (.signed .i32 0)
    second.nextCell _ thirdHeld.wellFormed (by decide) cursorThird
  have childFinal := bindLocal_owns_fresh third 17 (.signed .i32 0) thirdHeld.wellFormed
  refine ⟨final.wellFormed, final.grammar, final.kinds, final.records, final.offsets,
    final.output, final.backing, ?_, ?_, final.count, final.wordLength, final.nodeCount,
    final.kindCount, final.canonicalOffset, Assertion.localPointsTo_local _ _ _ _ final.node,
    Assertion.localPointsTo_local _ _ _ _ offsetFinal, Assertion.localPointsTo_local _ _ _ _ countFinal, ?_⟩
  · exact cursorFinal
  · exact childFinal
  · intro id member cell binding changed
    have small : ∀ {id : VarId}, id ∈ nodeStableIds → id < 14 := by
      intro id member
      simp only [nodeStableIds, List.mem_cons, List.not_mem_nil, or_false] at member
      dsimp only [VarId] at member ⊢
      omega
    have unchanged (id : VarId) (low : id < 14) : (recordEntered before record).cellId? id = before.cellId? id := by
      have neq (n : VarId) (high : 14 ≤ n) : n ≠ id := by
        dsimp only [VarId] at low high ⊢
        omega
      simp only [recordEntered, bindLocal_preserves_other_cellId _ 17 id _ (neq _ (by decide)),
        bindLocal_preserves_other_cellId _ 16 id _ (neq _ (by decide)),
        bindLocal_preserves_other_cellId _ 15 id _ (neq _ (by decide)),
        bindLocal_preserves_other_cellId _ 14 id _ (neq _ (by decide))]
    have outputOld := StateWellFormed.cell_lt_next_of_entry held.wellFormed held.backing
    by_cases isOffset : id = 14
    · subst id
      have same := Option.some.inj (binding.symm.trans offsetFinal.1)
      rcases changed with (output | position) | child <;> dsimp only [childMemory, CellSet.singleton, CellId] at * <;> omega
    by_cases isCount : id = 15
    · subst id
      have same := Option.some.inj (binding.symm.trans countFinal.1)
      have firstNext : first.nextCell = before.nextCell + 1 := rfl
      rcases changed with (output | position) | child <;> dsimp only [childMemory, CellSet.singleton, CellId] at * <;> omega
    by_cases isNode : id = 13
    · subst id
      have same := Option.some.inj (binding.symm.trans final.node.1)
      have nodeOld := StateWellFormed.cell_lt_next_of_entry held.wellFormed held.node.2
      rcases changed with (output | position) | child
      · exact memory.distinct (output.symm.trans same)
      · dsimp only [childMemory, CellSet.singleton, CellId] at position same nodeOld; omega
      · dsimp only [childMemory, CellSet.singleton, CellId] at child same nodeOld; omega
    have stableMember : id ∈ nodeStableIds := by
      simp only [childStableIds, List.mem_cons, List.not_mem_nil, or_false] at member
      simp only [nodeStableIds, List.mem_cons, List.not_mem_nil, or_false]
      dsimp only [VarId] at member isOffset isCount isNode ⊢
      omega
    have original : before.cellId? id = some cell := (unchanged id (small stableMember)).symm.trans binding
    have old := StateWellFormed.cell_lt_next_of_local_binding id cell held.wellFormed original
    rcases changed with (output | position) | child
    · exact held.stable id stableMember cell original (Or.inl output)
    · dsimp only [childMemory, CellSet.singleton, CellId] at position old; omega
    · dsimp only [childMemory, CellSet.singleton, CellId] at child old; omega

end Lanius.Extraction.SemanticTokens.Collect
