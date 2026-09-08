import Lanius.Extraction.SemanticTokens.Collect.InitializeEntry

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

theorem lessEqual_evaluates
    (left : Evaluates program before a (.signed .i32 x) before)
    (right : Evaluates program before b (.signed .i32 y) before) :
    Evaluates program before (binary .lessEqual a b) (.boolean (decide (x ≤ y))) before := by
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary]

theorem greaterEqual_evaluates
    (left : Evaluates program before a (.signed .i32 x) before)
    (right : Evaluates program before b (.signed .i32 y) before) :
    Evaluates program before (binary .greaterEqual a b) (.boolean (decide (y ≤ x))) before := by
  apply evaluatesEagerBinary (by decide) (by decide) left right
  simp [evalBinaryValue, evalSignedBinary]

theorem negate_evaluates (evaluated : Evaluates program before expression (.boolean value) before) :
    Evaluates program before (negate expression) (.boolean (!value)) before :=
  evaluatesUnary evaluated rfl

theorem local_evaluates (program : Program) {id : VarId} (found : before.local? id = some value) :
    Evaluates program before (read id) value before :=
  ⟨1, evalLocal_of_local 0 program before id value found⟩

/-- These are exactly the scalar values read before any array access. The
guard proof also covers negative lengths and overflowing lattice counts. -/
structure InputScalars (before : State) where
  grammarLength : Int
  tokenCount : Int
  nodeCount : Int
  recordsLength : Int
  grammarRead : before.local? 1 = some (.signed .i32 grammarLength)
  tokensRead : before.local? 3 = some (.signed .i32 tokenCount)
  nodesRead : before.local? 7 = some (.signed .i32 nodeCount)
  recordsRead : before.local? 5 = some (.signed .i32 recordsLength)

def InputScalars.bad (input : InputScalars before) : Bool :=
  decide (input.grammarLength ≤ 16) || decide (input.tokenCount ≤ -1) ||
    decide (1073741824 ≤ input.tokenCount) || decide (input.nodeCount ≤ -1) ||
    decide (input.recordsLength ≤ -1)

theorem InputScalars.evaluates (input : InputScalars before) (program : Program) :
    Evaluates program before inputGuard (.boolean input.bad) before := by
  have header := lessEqual_evaluates (local_evaluates program input.grammarRead)
    (show Evaluates program before (number 16) (.signed .i32 16) before from ⟨1, rfl⟩)
  have negativeTokens := lessEqual_evaluates (local_evaluates program input.tokensRead) (negativeOne_evaluates program before)
  have largeTokens := greaterEqual_evaluates (local_evaluates program input.tokensRead)
    (show Evaluates program before (number 1073741824) (.signed .i32 1073741824) before from ⟨1, rfl⟩)
  have negativeNodes := lessEqual_evaluates (local_evaluates program input.nodesRead) (negativeOne_evaluates program before)
  have negativeRecords := lessEqual_evaluates (local_evaluates program input.recordsRead) (negativeOne_evaluates program before)
  exact evaluatesPureLogicalOr
    (evaluatesPureLogicalOr (evaluatesPureLogicalOr (evaluatesPureLogicalOr header negativeTokens) largeTokens) negativeNodes)
    negativeRecords

/-- A bad scalar input returns before touching buffers or allocating locals.
This statement concerns the entire collector body, not a located guard. -/
theorem InputScalars.reject (input : InputScalars before) (program : Program) (symbols : Symbols)
    (bad : input.bad = true) :
    Executes program before (body symbols) (.returned (some (.signed .i32 (-1)))) before := by
  have condition := input.evaluates program
  rw [bad] at condition
  exact executesSequenceReturned (executesIfTrue condition
    (executesSequenceReturned (executesReturnValue (negativeOne_evaluates program before))))

theorem capacityGuard_negative (program : Program)
    (found : before.local? 9 = some (.signed .i32 length)) (negativeLength : length < 0) :
    Evaluates program before capacityGuard (.boolean true) before := by
  have first := lessEqual_evaluates (local_evaluates program found) (negativeOne_evaluates program before)
  have bound : length ≤ -1 := by omega
  simp only [bound, decide_true] at first
  exact evaluatesLogicalOrTrue first

theorem capacityGuard_nonnegative (program : Program) (count capacity : Nat)
    (tokensRead : before.local? 3 = some (.signed .i32 count))
    (capacityRead : before.local? 9 = some (.signed .i32 capacity))
    (capacityBound : capacity ≤ 2147483647) :
    Evaluates program before capacityGuard (.boolean (decide (capacity / 2 < count))) before := by
  have nonnegative := lessEqual_evaluates (local_evaluates program capacityRead) (negativeOne_evaluates program before)
  have positive : ¬ ((capacity : Int) ≤ -1) := by omega
  simp only [positive, decide_false] at nonnegative
  have divided := evaluatesNatI32Divide (leftValue := capacity) (rightValue := 2)
    (local_evaluates program capacityRead)
    (show Evaluates program before (number 2) (.signed .i32 2) before from ⟨1, rfl⟩) (by decide)
    (Nat.le_trans (Nat.div_le_self capacity 2) capacityBound)
  have enough := lessEqual_evaluates (local_evaluates program tokensRead) divided
  have inverted := negate_evaluates enough
  apply evaluatesLogicalOrFalse nonnegative
  simpa only [Int.ofNat_eq_natCast, Int.ofNat_le, ← decide_not, Nat.not_le] using inverted

/-- The second public guard also returns without any array access. Passing
the first guard is a numeric condition on the caller's scalar arguments. -/
private theorem InputScalars.reject_capacity (input : InputScalars before) (program : Program) (symbols : Symbols)
    (validInput : input.bad = false)
    (capacityRejected : Evaluates program before capacityGuard (.boolean true) before) :
    Executes program before (body symbols) (.returned (some (.signed .i32 (-2)))) before := by
  have first := input.evaluates program
  rw [validInput] at first
  have negativeTwo : Evaluates program before (negative 2) (.signed .i32 (-2)) before := by
    apply evaluatesUnary (show Evaluates program before (number 2) (.signed .i32 2) before from ⟨1, rfl⟩)
    simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]
  exact executesSequence (executesIfFalse first (executesSkip _ _))
    (executesSequenceReturned (executesIfTrue capacityRejected
      (executesSequenceReturned (executesReturnValue negativeTwo))))

theorem InputScalars.reject_negative_capacity (input : InputScalars before) (program : Program) (symbols : Symbols)
    (validInput : input.bad = false)
    (capacityRead : before.local? 9 = some (.signed .i32 capacity)) (negativeCapacity : capacity < 0) :
    Executes program before (body symbols) (.returned (some (.signed .i32 (-2)))) before :=
  input.reject_capacity program symbols validInput (capacityGuard_negative program capacityRead negativeCapacity)

theorem InputScalars.reject_short_capacity (input : InputScalars before) (program : Program) (symbols : Symbols)
    (validInput : input.bad = false) (count capacity : Nat)
    (tokensRead : before.local? 3 = some (.signed .i32 count))
    (capacityRead : before.local? 9 = some (.signed .i32 capacity))
    (capacityBound : capacity ≤ 2147483647) (short : capacity / 2 < count) :
    Executes program before (body symbols) (.returned (some (.signed .i32 (-2)))) before := by
  have failed := capacityGuard_nonnegative program count capacity tokensRead capacityRead capacityBound
  simp only [short, decide_true] at failed
  exact input.reject_capacity program symbols validInput failed

end Lanius.Extraction.SemanticTokens.Collect
