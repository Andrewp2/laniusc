import Lanius.Fuel

namespace Lanius.Semantics

open Lanius
open Lanius.Core
open Lanius.Fuel

/-- Two sequential successful expression evaluations can be replayed at their
    common maximum fuel.  This is the basic state-threaded composition step
    shared by expression operators and structural execution rules. -/
theorem evaluatesAtCommonFuel
    (leftResult : Evaluates program before left leftValue afterLeft)
    (rightResult : Evaluates program afterLeft right rightValue afterRight) :
    ∃ fuel,
      evalExpr fuel program before left = .done leftValue afterLeft ∧
      evalExpr fuel program afterLeft right = .done rightValue afterRight := by
  obtain ⟨leftFuel, leftResult⟩ := leftResult
  obtain ⟨rightFuel, rightResult⟩ := rightResult
  exact ⟨max leftFuel rightFuel,
    evalExpr_done_at_larger_fuel (Nat.le_max_left _ _) leftResult,
    evalExpr_done_at_larger_fuel (Nat.le_max_right _ _) rightResult⟩

theorem evaluatesStringDataPtr
    (stringResult : Evaluates program before string (.string text) middle)
    (mapped : mapStringDataPtr middle text = .done (.pointer address) after) :
    Evaluates program before (.stringDataPtr string) (.pointer address) after := by
  obtain ⟨fuel, stringResult⟩ := stringResult
  refine ⟨fuel + 1, ?_⟩
  rw [evalExpr.eq_def]
  simp only
  rw [stringResult]
  exact mapped

theorem evaluatesAlloc
    (sizeResult : Evaluates program before size (.unsigned .usize bytes) afterSize)
    (alignmentResult : Evaluates program afterSize alignment (.unsigned .usize align) afterAlignment)
    (allocated : afterAlignment.heap.allocate bytes align = .allocated address heap) :
    Evaluates program before (.alloc size alignment) (.pointer address) { afterAlignment with heap } := by
  obtain ⟨fuel, sizeResult, alignmentResult⟩ :=
    evaluatesAtCommonFuel sizeResult alignmentResult
  refine ⟨fuel + 1, ?_⟩
  rw [evalExpr.eq_def]
  simp only
  rw [sizeResult]
  simp only
  rw [alignmentResult]
  simp only [allocated]

theorem evaluatesI32SliceFromRawParts
    (pointerResult : Evaluates program before pointer (.pointer address) afterPointer)
    (lengthResult : Evaluates program afterPointer length (.signed .i32 count) afterLength)
    (mapped : mapRawI32Slice afterLength address count = .done value after) :
    Evaluates program before (.i32SliceFromRawParts pointer length) value after := by
  obtain ⟨fuel, pointerResult, lengthResult⟩ :=
    evaluatesAtCommonFuel pointerResult lengthResult
  refine ⟨fuel + 1, ?_⟩
  rw [evalExpr.eq_def]
  simp only
  rw [pointerResult]
  simp only
  rw [lengthResult]
  exact mapped

theorem evaluatesI32SliceDataPtr
    (sliceResult : Evaluates program before slice
      (.slice (.scalar (.signed .i32)) cell projections start length) middle)
    (mapped : mapI32SliceDataPtr middle cell projections start length = .done value after) :
    Evaluates program before (.i32SliceDataPtr slice) value after := by
  obtain ⟨fuel, evaluated⟩ := sliceResult
  refine ⟨fuel + 1, ?_⟩
  rw [evalExpr.eq_def]
  simp only [evaluated]
  exact mapped

/-! Fuel-independent structural rules for successful statement execution.

These belong to the dynamic-semantics proof interface rather than to any
particular represented program. They hide fuel synchronization when composing
control flow, leaving implementation proofs to reason in terms of `Evaluates`
and `Executes`.
-/

private theorem executesWhileTrueBody
    {bodyCompletion completion : Completion}
    (conditionResult : Evaluates program state condition
      (.boolean true) afterCondition)
    (bodyResult : Executes program afterCondition body bodyCompletion afterBody)
    (bodyFallsThrough : bodyCompletion = .next ∨ bodyCompletion = .continueLoop)
    (restResult : Executes program afterBody
      (.whileLoop condition body) completion finalState) :
    Executes program state (.whileLoop condition body) completion finalState := by
  obtain ⟨conditionFuel, conditionResult⟩ := conditionResult
  obtain ⟨bodyFuel, bodyResult⟩ := bodyResult
  obtain ⟨restFuel, restResult⟩ := restResult
  let fuel := max conditionFuel (max bodyFuel restFuel)
  have conditionAtFuel := evalExpr_done_at_larger_fuel
    (Nat.le_max_left conditionFuel (max bodyFuel restFuel)) conditionResult
  have bodyAtFuel := execStmt_done_at_larger_fuel
    (Nat.le_trans (Nat.le_max_left bodyFuel restFuel)
      (Nat.le_max_right conditionFuel (max bodyFuel restFuel))) bodyResult
  have restAtFuel := execStmt_done_at_larger_fuel
    (Nat.le_trans (Nat.le_max_right bodyFuel restFuel)
      (Nat.le_max_right conditionFuel (max bodyFuel restFuel))) restResult
  rcases bodyFallsThrough with rfl | rfl
  all_goals
    refine ⟨fuel + 1, ?_⟩
    rw [execStmt.eq_def]
    simp only
    rw [conditionAtFuel]
    simp only
    rw [bodyAtFuel]
    simp only
    exact restAtFuel

private theorem executesWhileTrueTerminal
    {bodyCompletion completion : Completion}
    (conditionResult : Evaluates program state condition
      (.boolean true) afterCondition)
    (bodyResult : Executes program afterCondition body bodyCompletion finalState)
    (bodyTerminal :
      bodyCompletion = .breakLoop ∧ completion = .next ∨
      ∃ returnValue, bodyCompletion = .returned returnValue ∧
        completion = .returned returnValue) :
    Executes program state (.whileLoop condition body) completion finalState := by
  obtain ⟨conditionFuel, conditionResult⟩ := conditionResult
  obtain ⟨bodyFuel, bodyResult⟩ := bodyResult
  let fuel := max conditionFuel bodyFuel
  have conditionAtFuel := evalExpr_done_at_larger_fuel
    (Nat.le_max_left conditionFuel bodyFuel) conditionResult
  have bodyAtFuel := execStmt_done_at_larger_fuel
    (Nat.le_max_right conditionFuel bodyFuel) bodyResult
  rcases bodyTerminal with ⟨rfl, rfl⟩ | ⟨returnValue, rfl, rfl⟩ <;>
    refine ⟨fuel + 1, ?_⟩
  all_goals
    rw [execStmt.eq_def]
    simp only
    rw [conditionAtFuel]
    simp only
    rw [bodyAtFuel]

theorem executesWhileFalse
    (conditionResult : Evaluates program state condition (.boolean false) finalState) :
    Executes program state (.whileLoop condition body) .next finalState := by
  obtain ⟨fuel, conditionResult⟩ := conditionResult
  refine ⟨fuel + 1, ?_⟩
  rw [execStmt.eq_def]
  simp only
  rw [conditionResult]

theorem executesWhileTrue
    (conditionResult : Evaluates program state condition (.boolean true) afterCondition)
    (bodyResult : Executes program afterCondition body .next afterBody)
    (restResult : Executes program afterBody
      (.whileLoop condition body) .next finalState) :
    Executes program state (.whileLoop condition body) .next finalState := by
  exact executesWhileTrueBody conditionResult bodyResult (Or.inl rfl) restResult

theorem executesWhileTrueThen
    (conditionResult : Evaluates program state condition (.boolean true) afterCondition)
    (bodyResult : Executes program afterCondition body .next afterBody)
    (restResult : Executes program afterBody
      (.whileLoop condition body) completion finalState) :
    Executes program state (.whileLoop condition body) completion finalState := by
  exact executesWhileTrueBody conditionResult bodyResult (Or.inl rfl) restResult

theorem executesWhileReturned
    (conditionResult :
      Evaluates program state condition (.boolean true) afterCondition)
    (bodyResult : Executes program afterCondition body
      (.returned returnValue) finalState) :
    Executes program state (.whileLoop condition body)
      (.returned returnValue) finalState := by
  exact executesWhileTrueTerminal conditionResult bodyResult
    (Or.inr ⟨returnValue, rfl, rfl⟩)

private theorem executesIfBranch
    {flag : Bool}
    (conditionResult : Evaluates program state condition
      (.boolean flag) afterCondition)
    (branchResult : Executes program afterCondition
      (match flag with | true => thenBranch | false => elseBranch)
      completion finalState) :
    Executes program state (.ifThenElse condition thenBranch elseBranch)
      completion finalState := by
  obtain ⟨conditionFuel, conditionResult⟩ := conditionResult
  obtain ⟨branchFuel, branchResult⟩ := branchResult
  let fuel := max conditionFuel branchFuel
  have conditionAtFuel := evalExpr_done_at_larger_fuel
    (Nat.le_max_left conditionFuel branchFuel) conditionResult
  have branchAtFuel := execStmt_done_at_larger_fuel
    (Nat.le_max_right conditionFuel branchFuel) branchResult
  cases flag <;>
    refine ⟨fuel + 1, ?_⟩
  all_goals
    rw [execStmt.eq_def]
    simp only
    rw [conditionAtFuel]
    simp only
    exact branchAtFuel

theorem executesIfTrue
    (conditionResult :
      Evaluates program state condition (.boolean true) afterCondition)
    (branchResult : Executes program afterCondition thenBranch completion finalState) :
    Executes program state (.ifThenElse condition thenBranch elseBranch)
      completion finalState := by
  exact executesIfBranch conditionResult branchResult

theorem executesIfFalse
    (conditionResult :
      Evaluates program state condition (.boolean false) afterCondition)
    (branchResult : Executes program afterCondition elseBranch completion finalState) :
    Executes program state (.ifThenElse condition thenBranch elseBranch)
      completion finalState := by
  exact executesIfBranch conditionResult branchResult

theorem executesSequence
    (firstResult : Executes program state first .next middle)
    (secondResult : Executes program middle second completion finalState) :
    Executes program state (.sequence first second) completion finalState := by
  obtain ⟨firstFuel, firstResult⟩ := firstResult
  obtain ⟨secondFuel, secondResult⟩ := secondResult
  let fuel := max firstFuel secondFuel
  have firstAtFuel := execStmt_done_at_larger_fuel
    (Nat.le_max_left firstFuel secondFuel) firstResult
  have secondAtFuel := execStmt_done_at_larger_fuel
    (Nat.le_max_right firstFuel secondFuel) secondResult
  refine ⟨fuel + 1, ?_⟩
  rw [execStmt.eq_def]
  simp only
  rw [firstAtFuel]
  simp only
  exact secondAtFuel

/-- Sequencing propagates every non-fallthrough completion without executing
    its right-hand statement. -/
theorem executesSequenceNonNext
    (firstResult : Executes program state first completion finalState)
    (notNext : completion ≠ .next) :
    Executes program state (.sequence first second) completion finalState := by
  obtain ⟨fuel, firstResult⟩ := firstResult
  refine ⟨fuel + 1, ?_⟩
  rw [execStmt.eq_def]
  simp only
  rw [firstResult]
  cases completion <;> simp_all

theorem executesSequenceReturned
    (firstResult : Executes program state first
      (.returned returnValue) finalState) :
    Executes program state (.sequence first second)
      (.returned returnValue) finalState := by
  exact executesSequenceNonNext firstResult (by simp)

theorem executesReturnValue
    (valueResult : Evaluates program state expression value finalState) :
    Executes program state (.returnValue (some expression))
      (.returned (some value)) finalState := by
  obtain ⟨fuel, valueResult⟩ := valueResult
  refine ⟨fuel + 1, ?_⟩
  rw [execStmt.eq_def]
  simp only
  rw [valueResult]

theorem executesExpression
    (expressionResult : Evaluates program state expression value finalState) :
    Executes program state (.expression expression) .next finalState := by
  obtain ⟨fuel, expressionResult⟩ := expressionResult
  refine ⟨fuel + 1, ?_⟩
  rw [execStmt.eq_def]
  simp only
  rw [expressionResult]

theorem executesReturnNone (program : Program) (state : State) :
    Executes program state (.returnValue none) (.returned none) state := by
  exact ⟨1, rfl⟩

theorem executesBreak (program : Program) (state : State) :
    Executes program state .breakLoop .breakLoop state := by
  exact ⟨1, rfl⟩

theorem executesContinue (program : Program) (state : State) :
    Executes program state .continueLoop .continueLoop state := by
  exact ⟨1, rfl⟩

theorem executesLetLocal
    {id : VarId} {type : Ty}
    (initializerResult : Evaluates program state initializer value afterInitializer)
    (bodyResult : Executes program (afterInitializer.bindLocal id value)
      body completion completed) :
    Executes program state (.letLocal id type initializer body) completion
      (restoreLocals afterInitializer completed) := by
  obtain ⟨initializerFuel, initializerResult⟩ := initializerResult
  obtain ⟨bodyFuel, bodyResult⟩ := bodyResult
  let fuel := max initializerFuel bodyFuel
  have initializerAtFuel := evalExpr_done_at_larger_fuel
    (Nat.le_max_left initializerFuel bodyFuel) initializerResult
  have bodyAtFuel := execStmt_done_at_larger_fuel
    (Nat.le_max_right initializerFuel bodyFuel) bodyResult
  refine ⟨fuel + 1, ?_⟩
  rw [execStmt.eq_def]
  simp only
  rw [initializerAtFuel]
  simp only
  rw [bodyAtFuel]
  rfl

theorem executesLetUninitialized
    {id : VarId} {type : Ty}
    (bodyResult : Executes program (state.bindUninitialized id)
      body completion completed) :
    Executes program state (.letUninitialized id type body) completion
      (restoreLocals state completed) := by
  obtain ⟨fuel, bodyResult⟩ := bodyResult
  refine ⟨fuel + 1, ?_⟩
  rw [execStmt.eq_def]
  simp only
  rw [bodyResult]
  rfl

theorem executesWhileContinueThen
    (conditionResult :
      Evaluates program state condition (.boolean true) afterCondition)
    (bodyResult : Executes program afterCondition body .continueLoop afterBody)
    (restResult : Executes program afterBody
      (.whileLoop condition body) completion finalState) :
    Executes program state (.whileLoop condition body) completion finalState := by
  exact executesWhileTrueBody conditionResult bodyResult (Or.inr rfl) restResult

theorem executesWhileBreak
    (conditionResult :
      Evaluates program state condition (.boolean true) afterCondition)
    (bodyResult : Executes program afterCondition body .breakLoop finalState) :
    Executes program state (.whileLoop condition body) .next finalState := by
  exact executesWhileTrueTerminal conditionResult bodyResult
    (Or.inl ⟨rfl, rfl⟩)

theorem executesSkip (program : Program) (state : State) :
    Executes program state .skip .next state := by
  exact ⟨1, rfl⟩

/-- Reading an initialized local is pure. This generic rule belongs to the
    execution interface rather than to any particular represented program. -/
theorem evalLocal_of_local
    (fuel : Nat) (program : Program) (state : State)
    (id : VarId) (value : Value)
    (found : state.local? id = some value) :
    evalExpr (fuel + 1) program state (.local id) = .done value state := by
  rw [State.local?, Option.bind_eq_some_iff] at found
  obtain ⟨cell, cellId, cellValue⟩ := found
  rw [State.cell?, Option.bind_eq_some_iff] at cellValue
  obtain ⟨entry, cellEntry, initialized⟩ := cellValue
  cases entry with
  | mk entryId contents =>
      cases contents with
      | none => simp at initialized
      | some stored =>
          simp at initialized
          subst stored
          simp [evalExpr, cellId, cellEntry]

/-- Reading an initialized local as an expression is pure. -/
theorem evaluatesLocal
    {program : Program} {state : State} {id : VarId} {value : Value}
    (found : state.local? id = some value) :
    Evaluates program state (.local id) value state := by
  exact ⟨1, evalLocal_of_local 0 program state id value found⟩

/-- A literal value expression evaluates without consuming state. -/
theorem evaluatesValue {program : Program} {state : State} {value : Value} :
    Evaluates program state (.value value) value state := by
  exact ⟨1, rfl⟩

/-- Reading a checked program constant is pure. Keeping this rule beside the
    local-read rule avoids re-unfolding the evaluator in every extracted
    implementation proof. -/
theorem evaluatesConstant
    {id : ConstantId} {declaration : Constant}
    (found : program.constant? id = some declaration) :
    Evaluates program state (.constant id) declaration.value state := by
  refine ⟨1, ?_⟩
  simp [evalExpr, found]

/-- Compose two effectful operands of a non-short-circuiting binary operator.
    This is the fuel-independent execution counterpart of the eager binary
    branch in `evalExpr`. -/
theorem evaluatesEagerBinary
    (notAnd : op ≠ .logicalAnd) (notOr : op ≠ .logicalOr)
    (leftResult : Evaluates program before left leftValue afterLeft)
    (rightResult : Evaluates program afterLeft right rightValue afterRight)
    (operationResult :
      evalBinaryValue program.target op leftValue rightValue = .ok result) :
    Evaluates program before (.binary op left right) result afterRight := by
  obtain ⟨fuel, leftAtFuel, rightAtFuel⟩ :=
    evaluatesAtCommonFuel leftResult rightResult
  refine ⟨fuel + 1, ?_⟩
  rw [evalExpr.eq_def]
  simp only [notAnd, notOr, leftAtFuel, rightAtFuel, operationResult]

/-- Short-circuit a logical conjunction after a false left operand. -/
theorem evaluatesLogicalAndFalse
    (leftResult :
      Evaluates program before left (.boolean false) afterLeft) :
    Evaluates program before (.binary .logicalAnd left right)
      (.boolean false) afterLeft := by
  obtain ⟨fuel, leftResult⟩ := leftResult
  refine ⟨fuel + 1, ?_⟩
  rw [evalExpr.eq_def]
  simp only
  rw [leftResult]

/-- Continue a logical conjunction with its right operand after a true left
    operand, preserving the state threaded through both evaluations. -/
theorem evaluatesLogicalAndTrue
    (leftResult :
      Evaluates program before left (.boolean true) afterLeft)
    (rightResult : Evaluates program afterLeft right result afterRight) :
    Evaluates program before (.binary .logicalAnd left right)
      result afterRight := by
  obtain ⟨fuel, leftAtFuel, rightAtFuel⟩ :=
    evaluatesAtCommonFuel leftResult rightResult
  refine ⟨fuel + 1, ?_⟩
  rw [evalExpr.eq_def]
  simp only [leftAtFuel]
  exact rightAtFuel

/-- Evaluate a conjunction whose operands are both pure. This packages the
    short-circuit split while retaining the useful fact that the surrounding
    runtime state is unchanged. Extracted validation predicates use this
    shape pervasively. -/
theorem evaluatesPureLogicalAnd
    (leftResult :
      Evaluates program state left (.boolean leftValue) state)
    (rightResult :
      Evaluates program state right (.boolean rightValue) state) :
    Evaluates program state (.binary .logicalAnd left right)
      (.boolean (leftValue && rightValue)) state := by
  cases leftValue <;> simp only [Bool.false_and, Bool.true_and]
  · exact evaluatesLogicalAndFalse leftResult
  · exact evaluatesLogicalAndTrue leftResult rightResult

/-- Short-circuit a logical disjunction after a true left operand. -/
theorem evaluatesLogicalOrTrue
    (leftResult :
      Evaluates program before left (.boolean true) afterLeft) :
    Evaluates program before (.binary .logicalOr left right)
      (.boolean true) afterLeft := by
  obtain ⟨fuel, leftResult⟩ := leftResult
  refine ⟨fuel + 1, ?_⟩
  rw [evalExpr.eq_def]
  simp only
  rw [leftResult]

/-- Continue a logical disjunction with its right operand after a false left
    operand, preserving the state threaded through both evaluations. -/
theorem evaluatesLogicalOrFalse
    (leftResult :
      Evaluates program before left (.boolean false) afterLeft)
    (rightResult : Evaluates program afterLeft right result afterRight) :
    Evaluates program before (.binary .logicalOr left right)
      result afterRight := by
  obtain ⟨fuel, leftAtFuel, rightAtFuel⟩ :=
    evaluatesAtCommonFuel leftResult rightResult
  refine ⟨fuel + 1, ?_⟩
  rw [evalExpr.eq_def]
  simp only [leftAtFuel]
  exact rightAtFuel

/-- Evaluate a disjunction whose operands are both pure. -/
theorem evaluatesPureLogicalOr
    (leftResult :
      Evaluates program state left (.boolean leftValue) state)
    (rightResult :
      Evaluates program state right (.boolean rightValue) state) :
    Evaluates program state (.binary .logicalOr left right)
      (.boolean (leftValue || rightValue)) state := by
  cases leftValue <;> simp only [Bool.false_or, Bool.true_or]
  · exact evaluatesLogicalOrFalse leftResult rightResult
  · exact evaluatesLogicalOrTrue leftResult

/-- Read a known field from an evaluated structure value. -/
theorem evaluatesStructureField
    (baseResult : Evaluates program before base
      (.structure structureId fields) afterBase)
    (found : fields[field]? = some value) :
    Evaluates program before (.field base field) value afterBase := by
  obtain ⟨fuel, baseResult⟩ := baseResult
  refine ⟨fuel + 1, ?_⟩
  rw [evalExpr.eq_def]
  simp only
  rw [baseResult]
  simp only
  rw [found]

/-- Structure construction is left-to-right field evaluation followed by
    packaging the resulting values. -/
theorem evaluatesStructValue
    (fieldsResult : ∃ fuel,
      evalExprs fuel program before fields = .done values after) :
    Evaluates program before (.structValue typeId fields)
      (.structure typeId values) after := by
  obtain ⟨fuel, fieldsAtFuel⟩ := fieldsResult
  refine ⟨fuel + 1, ?_⟩
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [fieldsAtFuel]

/-- Compose an effectful operand with a successful unary operation. -/
theorem evaluatesUnary
    (operandResult : Evaluates program before operand operandValue afterOperand)
    (operationResult :
      evalUnaryValue program.target op operandValue = .ok result) :
    Evaluates program before (.unary op operand) result afterOperand := by
  obtain ⟨fuel, operandResult⟩ := operandResult
  refine ⟨fuel + 1, ?_⟩
  rw [evalExpr.eq_def]
  simp only
  rw [operandResult]
  simp only
  rw [operationResult]

/-- Compose an effectful operand with a successful scalar cast. -/
theorem evaluatesCast
    (operandResult : Evaluates program before operand operandValue afterOperand)
    (operationResult :
      evalScalarCast program.target target operandValue = .ok result) :
    Evaluates program before (.cast target operand) result afterOperand := by
  obtain ⟨fuel, operandResult⟩ := operandResult
  refine ⟨fuel + 1, ?_⟩
  rw [evalExpr.eq_def]
  simp only
  rw [operandResult]
  simp only
  rw [operationResult]

/-- Nonnegative mathematical indices in the signed i32 domain are unchanged
    by the dynamic semantics' machine-integer normalization.  This is shared
    by extracted lexer, parser, and later compiler-phase proofs. -/
theorem wrapSigned_i32_ofNat
    (target : Target) (value : Nat) (bounded : value ≤ 2147483647) :
    wrapSigned target .i32 (Int.ofNat value) = Int.ofNat value := by
  have modulus : signedModulus target .i32 = 4294967296 := by
    cases target <;> rfl
  have signBit : signedSignBit target .i32 = 2147483648 := by
    cases target <;> rfl
  have modulo :
      Int.ofNat value % signedModulus target .i32 = Int.ofNat value := by
    rw [modulus]
    apply Int.emod_eq_of_lt (Int.natCast_nonneg value)
    exact Int.ofNat_lt.mpr
      (Nat.lt_of_le_of_lt bounded (by decide))
  have belowSign : ¬ Int.ofNat value ≥ signedSignBit target .i32 := by
    rw [signBit, Int.not_le]
    exact Int.ofNat_lt.mpr (Nat.lt_succ_of_le bounded)
  simp only [wrapSigned, modulo, belowSign, if_false]

/-- Any nonnegative mathematical integer in the signed-i32 domain is already
    in canonical machine representation. This is the Int-facing companion to
    `wrapSigned_i32_ofNat`. -/
theorem wrapSigned_i32_of_nonnegative
    (target : Target) (value : Int)
    (nonnegative : 0 ≤ value) (bounded : value ≤ 2147483647) :
    wrapSigned target .i32 value = value := by
  have valueOfNat : Int.ofNat value.toNat = value :=
    Int.toNat_of_nonneg nonnegative
  have naturalBound : value.toNat ≤ 2147483647 := by
    exact Int.toNat_le.mpr bounded
  rw [← valueOfNat]
  exact wrapSigned_i32_ofNat target value.toNat naturalBound

/-- Addition of two nonnegative i32 values agrees with natural-number
    addition whenever the mathematical result remains in range. -/
theorem evaluatesNatI32Add
    (leftResult : Evaluates program before left
      (.signed .i32 (Int.ofNat leftValue)) middle)
    (rightResult : Evaluates program middle right
      (.signed .i32 (Int.ofNat rightValue)) after)
    (bounded : leftValue + rightValue ≤ 2147483647) :
    Evaluates program before (.binary .add left right)
      (.signed .i32 (Int.ofNat (leftValue + rightValue))) after := by
  have cast : Int.ofNat leftValue + Int.ofNat rightValue =
      Int.ofNat (leftValue + rightValue) := (Int.natCast_add _ _).symm
  have wrapped := wrapSigned_i32_ofNat program.target
    (leftValue + rightValue) bounded
  apply evaluatesEagerBinary (by decide) (by decide) leftResult rightResult
  simp only [evalBinaryValue, evalSignedBinary, BEq.rfl, if_true]
  rw [cast, wrapped]

/-- Multiplication of two nonnegative i32 values agrees with natural-number
    multiplication whenever the mathematical result remains in range. -/
theorem evaluatesNatI32Multiply
    (leftResult : Evaluates program before left
      (.signed .i32 (Int.ofNat leftValue)) middle)
    (rightResult : Evaluates program middle right
      (.signed .i32 (Int.ofNat rightValue)) after)
    (bounded : leftValue * rightValue ≤ 2147483647) :
    Evaluates program before (.binary .multiply left right)
      (.signed .i32 (Int.ofNat (leftValue * rightValue))) after := by
  have cast : Int.ofNat leftValue * Int.ofNat rightValue =
      Int.ofNat (leftValue * rightValue) := (Int.natCast_mul _ _).symm
  have wrapped := wrapSigned_i32_ofNat program.target
    (leftValue * rightValue) bounded
  apply evaluatesEagerBinary (by decide) (by decide) leftResult rightResult
  simp only [evalBinaryValue, evalSignedBinary, BEq.rfl, if_true]
  rw [cast, wrapped]

/-- Subtraction of ordered nonnegative i32 values agrees with truncated
    natural-number subtraction. -/
theorem evaluatesNatI32Subtract
    (leftResult : Evaluates program before left
      (.signed .i32 (Int.ofNat leftValue)) middle)
    (rightResult : Evaluates program middle right
      (.signed .i32 (Int.ofNat rightValue)) after)
    (ordered : rightValue ≤ leftValue)
    (bounded : leftValue - rightValue ≤ 2147483647) :
    Evaluates program before (.binary .subtract left right)
      (.signed .i32 (Int.ofNat (leftValue - rightValue))) after := by
  have cast : Int.ofNat leftValue - Int.ofNat rightValue =
      Int.ofNat (leftValue - rightValue) := (Int.ofNat_sub ordered).symm
  have wrapped := wrapSigned_i32_ofNat program.target
    (leftValue - rightValue) bounded
  apply evaluatesEagerBinary (by decide) (by decide) leftResult rightResult
  simp only [evalBinaryValue, evalSignedBinary, BEq.rfl, if_true]
  rw [cast, wrapped]

/-- Division of nonnegative i32 values by a positive natural divisor agrees
    with Euclidean natural-number division. -/
theorem evaluatesNatI32Divide
    (leftResult : Evaluates program before left
      (.signed .i32 (Int.ofNat leftValue)) middle)
    (rightResult : Evaluates program middle right
      (.signed .i32 (Int.ofNat rightValue)) after)
    (positive : 0 < rightValue)
    (bounded : leftValue / rightValue ≤ 2147483647) :
    Evaluates program before (.binary .divide left right)
      (.signed .i32 (Int.ofNat (leftValue / rightValue))) after := by
  have quotient : truncDiv (Int.ofNat leftValue) (Int.ofNat rightValue) =
      Int.ofNat (leftValue / rightValue) := by
    unfold truncDiv
    have signs : (Int.ofNat leftValue < 0) =
        (Int.ofNat rightValue < 0) := by
      apply propext
      constructor
      · intro impossible
        exact False.elim ((Int.not_lt.mpr (Int.natCast_nonneg _)) impossible)
      · intro impossible
        exact False.elim ((Int.not_lt.mpr (Int.natCast_nonneg _)) impossible)
    rw [if_pos signs]
    simp
  have wrapped := wrapSigned_i32_ofNat program.target (leftValue / rightValue) bounded
  apply evaluatesEagerBinary (by decide) (by decide) leftResult rightResult
  simp only [evalBinaryValue, evalSignedBinary]
  simp only [show (SignedIntTy.i32 == SignedIntTy.i32) = true by decide,
    if_true]
  rw [quotient, wrapped]
  simp [Nat.ne_of_gt positive]

/-- Remainder on nonnegative i32 operands agrees with natural remainder. -/
theorem evaluatesNatI32Remainder
    (leftResult : Evaluates program before left
      (.signed .i32 (Int.ofNat leftValue)) middle)
    (rightResult : Evaluates program middle right
      (.signed .i32 (Int.ofNat rightValue)) after)
    (positive : 0 < rightValue)
    (bounded : leftValue % rightValue ≤ 2147483647) :
    Evaluates program before (.binary .remainder left right)
      (.signed .i32 (Int.ofNat (leftValue % rightValue))) after := by
  have quotient : truncDiv (Int.ofNat leftValue) (Int.ofNat rightValue) =
      Int.ofNat (leftValue / rightValue) := by
    unfold truncDiv
    rw [if_pos (show (Int.ofNat leftValue < 0) = (Int.ofNat rightValue < 0) from
      propext ⟨fun h => False.elim ((Int.not_lt.mpr (Int.natCast_nonneg _)) h),
        fun h => False.elim ((Int.not_lt.mpr (Int.natCast_nonneg _)) h)⟩)]
    simp
  have remainder : Int.ofNat leftValue - Int.ofNat (leftValue / rightValue) *
      Int.ofNat rightValue = Int.ofNat (leftValue % rightValue) := by
    change (leftValue : Int) - (leftValue / rightValue : Nat) *
      (rightValue : Int) = (leftValue % rightValue : Nat)
    rw [Int.natCast_ediv, Int.natCast_emod]
    have decomposition := Int.emod_add_ediv_mul (leftValue : Int) (rightValue : Int)
    omega
  apply evaluatesEagerBinary (by decide) (by decide) leftResult rightResult
  simp only [evalBinaryValue, BEq.rfl, if_true, evalSignedBinary]
  have nonzero : (Int.ofNat rightValue == 0) = false := by simp [Nat.ne_of_gt positive]
  have notNegative : (Int.ofNat rightValue == -1) = false := by simp
  simp only [nonzero, notNegative, Bool.and_false, Bool.false_eq_true, if_false]
  rw [quotient, remainder, wrapSigned_i32_ofNat program.target _ bounded]

/-- The all-ones representation of `-1` is stable for signed i32 on every
    supported target. This is the common result of source-level `-1`
    literals, which elaborate as unary negation of positive one. -/
theorem wrapSigned_i32_neg_one (target : Target) :
    wrapSigned target .i32 (-1) = -1 := by
  simp [wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]

def signedI32Values (values : List Int) : List Value :=
  values.map fun value => .signed .i32 value

theorem encodeSignedI32Values (values : List Int) :
    encodeI32Array (signedI32Values values) = .ok (values.flatMap i32Bytes) := by
  induction values with
  | nil => rfl
  | cons first rest induction =>
      change (match encodeI32Array (signedI32Values rest) with
        | .ok bytes => Except.ok (i32Bytes first ++ bytes)
        | .error reason => Except.error reason) =
          Except.ok (i32Bytes first ++ rest.flatMap i32Bytes)
      rw [induction]

theorem signedI32Values_injective : Function.Injective signedI32Values := by
  intro left right same
  induction left generalizing right with
  | nil =>
      cases right with
      | nil => rfl
      | cons head tail => simp [signedI32Values] at same
  | cons head tail induction =>
      cases right with
      | nil => simp [signedI32Values] at same
      | cons rightHead rightTail =>
          have pair : head = rightHead ∧
              signedI32Values tail = signedI32Values rightTail := by
            simpa [signedI32Values] using same
          have headEq : head = rightHead := pair.1
          have tailEq : tail = rightTail := induction pair.2
          subst rightHead
          subst rightTail
          rfl

def setI32Value (values : List Int) (index : Nat) (value : Int) : List Int :=
  values.set index value

@[simp] theorem setI32Value_length
    (values : List Int) (index : Nat) (value : Int) :
    (setI32Value values index value).length = values.length := by
  simp [setI32Value]

theorem setValue_signedI32Values
    (values : List Int) (index : Nat) (value : Int) :
    setValue (signedI32Values values) index (.signed .i32 value) =
      signedI32Values (setI32Value values index value) := by
  induction values generalizing index with
  | nil => simp [setI32Value, signedI32Values, setValue]
  | cons head tail inductionHypothesis =>
      cases index with
      | zero => simp [setI32Value, signedI32Values, setValue]
      | succ index =>
          change (.signed .i32 head) ::
              setValue (signedI32Values tail) index (.signed .i32 value) =
            (.signed .i32 head) ::
              signedI32Values (setI32Value tail index value)
          exact congrArg ((.signed .i32 head) :: ·)
            (inductionHypothesis index)

private theorem i32SliceReadFacts
    (after : State) (values : List Int) (cell : CellId) (index : Nat)
    (inBounds : index < values.length)
    (backing : after.cellEntry? cell = some {
      id := cell
      value := some (.array (signedI32Values values))
    }) :
    integerIndex (.signed .i32 (Int.ofNat index)) = .ok index ∧
      sliceValues after cell [] 0 values.length =
        .ok (signedI32Values values) ∧
      (signedI32Values values)[index]? =
        some (.signed .i32 (values.get ⟨index, inBounds⟩)) := by
  constructor
  · simp [integerIndex]
  constructor
  · simp [sliceValues, readCellProjection, projectedValue, backing,
      signedI32Values]
    rw [show values.length = (signedI32Values values).length by
      simp [signedI32Values]]
    exact List.take_length
  · simp [signedI32Values, inBounds]

/-- Expression-parametric `i32` slice indexing. Base and index evaluation may
    perform calls and thread state; the backing-array premise is deliberately
    stated at the state where the actual memory read occurs. -/
theorem evaluatesSignedI32SliceIndex
    (program : Program) (before afterBase afterIndex : State)
    (values : List Int) (base indexExpression : Expr)
    (cell : CellId) (index : Nat)
    (inBounds : index < values.length)
    (baseResult : Evaluates program before base
      (.slice (.scalar (.signed .i32)) cell [] 0 values.length) afterBase)
    (indexResult : Evaluates program afterBase indexExpression
      (.signed .i32 (Int.ofNat index)) afterIndex)
    (backing : afterIndex.cellEntry? cell = some {
      id := cell
      value := some (.array (signedI32Values values))
    }) :
    Evaluates program before (.index base indexExpression)
      (.signed .i32 (values.get ⟨index, inBounds⟩)) afterIndex := by
  obtain ⟨fuel, baseAtFuel, indexAtFuel⟩ :=
    evaluatesAtCommonFuel baseResult indexResult
  refine ⟨fuel + 1, ?_⟩
  rw [evalExpr.eq_def]
  simp only
  rw [baseAtFuel]
  simp only
  rw [indexAtFuel]
  simp only
  have readFacts := i32SliceReadFacts afterIndex values cell index inBounds backing
  rw [readFacts.1]
  simp only
  rw [if_pos inBounds]
  rw [readFacts.2.1]
  simp only
  rw [readFacts.2.2]

/-- Resolving a readable local as a place exposes the physical cell that owns
    the binding.  Most aggregate-place rules do not care which lexical cell
    contains a slice descriptor, so the cell is existential here. -/
theorem evalPlaceLocal_of_local
    (program : Program) (state : State) (id : VarId) (value : Value)
    (found : state.local? id = some value) :
    ∃ cell,
      evalPlace 1 program state (.local id) =
        .done { root := cell, projections := [], value := some value } state := by
  rw [State.local?, Option.bind_eq_some_iff] at found
  obtain ⟨cell, cellId, cellValue⟩ := found
  rw [State.cell?, Option.bind_eq_some_iff] at cellValue
  obtain ⟨entry, entryFound, initialized⟩ := cellValue
  have entryId : entry.id = cell := by
    simpa using List.find?_some entryFound
  refine ⟨cell, ?_⟩
  rw [evalPlace, cellId]
  simp only
  rw [entryFound]
  simp [initialized]

/-- Resolving an index into a zero-based `i32` slice. The index expression may
    itself execute read-only helper calls, and its resulting state is threaded
    to the resolved place. -/
theorem evaluatesSignedI32SlicePlace
    (program : Program) (before afterIndex : State)
    (values : List Int) (sliceId : VarId) (indexExpression : Expr)
    (cell : CellId) (index : Nat)
    (inBounds : index < values.length)
    (sliceLocal : before.local? sliceId = some
      (.slice (.scalar (.signed .i32)) cell [] 0 values.length))
    (indexResult : Evaluates program before indexExpression
      (.signed .i32 (Int.ofNat index)) afterIndex)
    (backing : afterIndex.cellEntry? cell = some {
      id := cell
      value := some (.array (signedI32Values values))
    }) :
    ∃ fuel,
      evalPlace fuel program before (.index (.local sliceId) indexExpression) =
        .done {
          root := cell
          projections := [.index index]
          value := some (.signed .i32 (values.get ⟨index, inBounds⟩))
        } afterIndex := by
  obtain ⟨localCell, localResult⟩ :=
    evalPlaceLocal_of_local program before sliceId
      (.slice (.scalar (.signed .i32)) cell [] 0 values.length) sliceLocal
  obtain ⟨indexFuel, indexAtFuel⟩ := indexResult
  let fuel := max 1 indexFuel
  have localAtFuel := evalPlace_done_at_larger_fuel
    (Nat.le_max_left 1 indexFuel) localResult
  have indexAtCommonFuel := evalExpr_done_at_larger_fuel
    (Nat.le_max_right 1 indexFuel) indexAtFuel
  refine ⟨fuel + 1, ?_⟩
  rw [Lanius.Semantics.evalPlace.eq_def]
  simp only
  rw [localAtFuel]
  simp only
  rw [indexAtCommonFuel]
  simp only
  have readFacts := i32SliceReadFacts afterIndex values cell index inBounds backing
  rw [readFacts.1]
  simp only
  rw [if_pos inBounds]
  rw [readFacts.2.1]
  simp only
  rw [readFacts.2.2]
  simp

/-- Generic execution rule for indexing a zero-based `i32` slice.  The lexer
    and parser use different logical element models but the same Core storage
    representation, so this rule belongs at the execution boundary. -/
theorem evalSignedI32SliceIndex
    (program : Program) (state : State) (values : List Int)
    (sliceId indexId : VarId) (cell : CellId) (index : Nat)
    (inBounds : index < values.length)
    (sliceLocal : state.local? sliceId = some
      (.slice (.scalar (.signed .i32)) cell [] 0 values.length))
    (indexLocal : state.local? indexId =
      some (.signed .i32 (Int.ofNat index)))
    (backing : state.cellEntry? cell = some {
      id := cell
      value := some (.array (signedI32Values values))
    }) :
    evalExpr 10 program state (.index (.local sliceId) (.local indexId)) =
      .done (.signed .i32 (values.get ⟨index, inBounds⟩)) state := by
  have sliceResult := evalLocal_of_local 8 program state sliceId
    (.slice (.scalar (.signed .i32)) cell [] 0 values.length) sliceLocal
  have indexResult := evalLocal_of_local 8 program state indexId
    (.signed .i32 (Int.ofNat index)) indexLocal
  have sliceResult9 : evalExpr 9 program state (.local sliceId) =
      .done (.slice (.scalar (.signed .i32)) cell [] 0 values.length) state := by
    simpa using sliceResult
  have indexResult9 : evalExpr 9 program state (.local indexId) =
      .done (.signed .i32 (Int.ofNat index)) state := by
    simpa using indexResult
  rw [evalExpr, sliceResult9]
  simp only
  rw [indexResult9]
  simp only
  have integerResult :
      integerIndex (.signed .i32 (Int.ofNat index)) = .ok index := by
    simp [integerIndex]
  rw [integerResult]
  simp only
  rw [if_pos inBounds]
  have sliceResult :
      sliceValues state cell [] 0 values.length =
        .ok (signedI32Values values) := by
    simp [sliceValues, readCellProjection, projectedValue, backing,
      signedI32Values]
    rw [show values.length = (signedI32Values values).length by
      simp [signedI32Values]]
    exact List.take_length
  rw [sliceResult]
  simp only
  have valueAt : (signedI32Values values)[index]? =
      some (.signed .i32 (values.get ⟨index, inBounds⟩)) := by
    simp [signedI32Values, inBounds]
  rw [valueAt]

end Lanius.Semantics
