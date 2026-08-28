import Lanius.Compiler.LexerNumbers
import Lanius.Compiler.LexerProgramScanners
import Lanius.Separation

namespace Lanius.Compiler.Lexer.Program

open Lanius
open Lanius.Core
open Lanius.Semantics
open Lanius.Fuel
open Lanius.Properties
open Lanius.Separation

def digitScanValue : DigitScanResult → Value
  | .success endOffset =>
      .structure digitScanDeclaration.id
        [.boolean true, .signed .i32 endOffset, .signed .i32 0]
  | .failure errorOffset =>
      .structure digitScanDeclaration.id
        [.boolean false, .signed .i32 0, .signed .i32 errorOffset]

def twoI32CalleeState (state : State) (left right : Int) : State :=
  (clearLocals state).bindLocals
    [(0, .signed .i32 left), (1, .signed .i32 right)]

def twoI32CallState (state : State) (left right : Int) : State :=
  restoreLocals state (twoI32CalleeState state left right)

theorem twoI32CalleeState_store_extends
    (state : State) (left right : Int) :
    StoreExtension state (twoI32CalleeState state left right) := by
  let bindings : List (VarId × Value) :=
    [(0, .signed .i32 left), (1, .signed .i32 right)]
  constructor
  · intro cell old
    have preserved := bindLocals_preserves_old_cell
      (clearLocals state) bindings cell (by simpa [clearLocals] using old)
    have clearedEntry :
        (clearLocals state).cellEntry? cell = state.cellEntry? cell := rfl
    change (twoI32CalleeState state left right).cellEntry? cell =
      state.cellEntry? cell
    simpa [twoI32CalleeState, bindings] using preserved.trans clearedEntry
  · simp [twoI32CalleeState, clearLocals, bindLocals_nextCell]
  · rfl
  · rfl
  · rfl

theorem twoI32CallState_extends
    (state : State) (left right : Int) :
    FrameExtension state (twoI32CallState state left right) :=
  (twoI32CalleeState_store_extends state left right).restoreLocals

theorem twoI32CalleeState_well_formed
    (state : State) (wellFormed : StateWellFormed state)
    (left right : Int) :
    StateWellFormed (twoI32CalleeState state left right) := by
  exact bindLocals_preserves_well_formed (clearLocals state)
    [(0, .signed .i32 left), (1, .signed .i32 right)]
    (clearLocals_well_formed state wellFormed)

theorem twoI32CallState_well_formed
    (state : State) (wellFormed : StateWellFormed state)
    (left right : Int) :
    StateWellFormed (twoI32CallState state left right) :=
  (twoI32CalleeState_store_extends state left right)
    |>.restoreLocals_well_formed wellFormed
      (twoI32CalleeState_well_formed state wellFormed left right)

theorem twoI32CalleeState_left
    (state : State) (wellFormed : StateWellFormed state)
    (left right : Int) :
    (twoI32CalleeState state left right).local? 0 =
      some (.signed .i32 left) := by
  let cleared := clearLocals state
  have clearedWellFormed := clearLocals_well_formed state wellFormed
  have found := bindLocals_finds_cell_after_prefix cleared []
    [(1, .signed .i32 right)] 0 (.signed .i32 left) clearedWellFormed
  have cellId :
      (twoI32CalleeState state left right).cellId? 0 =
        some state.nextCell := by rfl
  rw [State.local?, cellId]
  simp only [Option.bind_some, State.cell?]
  have found' :
      (twoI32CalleeState state left right).cellEntry? state.nextCell =
        some { id := state.nextCell, value := some (.signed .i32 left) } := by
    simpa [twoI32CalleeState, cleared, clearLocals] using found
  rw [found']
  rfl

theorem twoI32CalleeState_right
    (state : State) (wellFormed : StateWellFormed state)
    (left right : Int) :
    (twoI32CalleeState state left right).local? 1 =
      some (.signed .i32 right) := by
  let cleared := clearLocals state
  have clearedWellFormed := clearLocals_well_formed state wellFormed
  have found := bindLocals_finds_cell_after_prefix cleared
    [(0, .signed .i32 left)] [] 1 (.signed .i32 right) clearedWellFormed
  have cellId :
      (twoI32CalleeState state left right).cellId? 1 =
        some (state.nextCell + 1) := by rfl
  rw [State.local?, cellId]
  simp only [Option.bind_some, State.cell?]
  have found' :
      (twoI32CalleeState state left right).cellEntry? (state.nextCell + 1) =
        some { id := state.nextCell + 1, value := some (.signed .i32 right) } := by
    simpa [twoI32CalleeState, cleared, clearLocals] using found
  rw [found']
  rfl

theorem evalI32LocalGreaterEqualLiteral
    (state : State) (id : VarId) (value literal : Int)
    (found : state.local? id = some (.signed .i32 value)) :
    evalExpr 3 lexerProgram state
      (.binary .greaterEqual (.local id) (i32Literal literal)) =
      .done (.boolean (decide (value ≥ literal))) state := by
  have leftResult := evalLocal_of_local 1 lexerProgram state id
    (.signed .i32 value) found
  have rightResult :
      evalExpr 2 lexerProgram state (i32Literal literal) =
        .done (.signed .i32 literal) state := by rfl
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [leftResult]
  simp only
  rw [rightResult]
  rfl

theorem evalI32LocalLessEqualLiteral
    (state : State) (id : VarId) (value literal : Int)
    (found : state.local? id = some (.signed .i32 value)) :
    evalExpr 3 lexerProgram state
      (.binary .lessEqual (.local id) (i32Literal literal)) =
      .done (.boolean (decide (value ≤ literal))) state := by
  have leftResult := evalLocal_of_local 1 lexerProgram state id
    (.signed .i32 value) found
  have rightResult :
      evalExpr 2 lexerProgram state (i32Literal literal) =
        .done (.signed .i32 literal) state := by rfl
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [leftResult]
  simp only
  rw [rightResult]
  rfl

theorem evalI32LocalSubtractNat
    (state : State) (id value amount : Nat)
    (found : state.local? id = some (.signed .i32 value))
    (amountLe : amount ≤ value)
    (bounded : value - amount ≤ 2147483647) :
    evalExpr 4 lexerProgram state
      (.binary .subtract (.local id) (i32Literal amount)) =
      .done (.signed .i32 (Int.ofNat (value - amount))) state := by
  have leftResult := evalLocal_of_local 2 lexerProgram state id
    (.signed .i32 value) found
  have rightResult :
      evalExpr 3 lexerProgram state (i32Literal amount) =
        .done (.signed .i32 amount) state := by rfl
  have wrapped := wrapSigned_i32_ofNat (value - amount) bounded
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [leftResult]
  simp only
  rw [rightResult]
  simp only [evalBinaryValue, beq_self_eq_true, if_true, evalSignedBinary]
  rw [← Int.ofNat_sub amountLe]
  exact congrArg
    (fun result =>
      (Outcome.done (Value.signed SignedIntTy.i32 result) state : Outcome Value))
    wrapped

theorem digitByteInRange_executes
    (state : State) (wellFormed : StateWellFormed state)
    (byte : Byte) (base : Nat) (lower upper : Nat) :
    evalExpr 4 lexerProgram (twoI32CalleeState state byte.val base)
      (digitByteInRange lower upper) =
      .done (.boolean (decide (lower ≤ byte.val) &&
        decide (byte.val ≤ upper)))
        (twoI32CalleeState state byte.val base) := by
  let callee := twoI32CalleeState state byte.val base
  have byteLocal := twoI32CalleeState_left state wellFormed byte.val base
  have lowerResult := evalI32LocalGreaterEqualLiteral callee 0 byte.val lower
    byteLocal
  have upperResult := evalI32LocalLessEqualLiteral callee 0 byte.val upper
    byteLocal
  have combined := andExpr_executes (state := callee) lowerResult upperResult
  have lowerEq : decide ((byte.val : Int) ≥ (lower : Int)) =
      decide (lower ≤ byte.val) := by
    simpa using intOfNat_le_decide lower byte.val
  have upperEq : decide ((byte.val : Int) ≤ (upper : Int)) =
      decide (byte.val ≤ upper) := by
    simpa using intOfNat_le_decide byte.val upper
  rw [lowerEq, upperEq] at combined
  simpa [digitByteInRange, callee] using combined

theorem digitValueLessBase_executes
    (state : State) (wellFormed : StateWellFormed state)
    (byte : Byte) (base lower adjustment : Nat)
    (lowerLe : lower ≤ byte.val)
    (bounded : byte.val - lower + adjustment ≤ 2147483647) :
    evalExpr 6 lexerProgram (twoI32CalleeState state byte.val base)
      (digitValueLessBase lower adjustment) =
      .done (.boolean (decide (byte.val - lower + adjustment < base)))
        (twoI32CalleeState state byte.val base) := by
  let callee := twoI32CalleeState state byte.val base
  have byteLocal := twoI32CalleeState_left state wellFormed byte.val base
  have baseLocal := twoI32CalleeState_right state wellFormed byte.val base
  have subBase := evalI32LocalSubtractNat callee 0 byte.val lower byteLocal
    lowerLe (by omega)
  have adjustmentResult :
      evalExpr 4 lexerProgram callee (i32Literal adjustment) =
        .done (.signed .i32 adjustment) callee := by rfl
  have wrapped := wrapSigned_i32_ofNat
    (byte.val - lower + adjustment) bounded
  have addResult :
      evalExpr 5 lexerProgram callee
        (.binary .add
          (.binary .subtract (.local 0) (i32Literal lower))
          (i32Literal adjustment)) =
        .done (.signed .i32
          (Int.ofNat (byte.val - lower + adjustment))) callee := by
    rw [Lanius.Semantics.evalExpr.eq_def]
    simp only
    rw [subBase]
    simp only
    rw [adjustmentResult]
    simp only [evalBinaryValue, beq_self_eq_true, if_true, evalSignedBinary]
    simpa using wrapped
  have baseResult := evalLocal_of_local 4 lexerProgram callee 1
    (.signed .i32 base) baseLocal
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only [digitValueLessBase]
  rw [addResult]
  simp only
  rw [baseResult]
  simp only [evalBinaryValue, beq_self_eq_true, if_true, evalSignedBinary]
  exact congrArg
    (fun result => (Outcome.done (Value.boolean result) callee : Outcome Value))
    (intOfNat_lt_decide (byte.val - lower + adjustment) base)

private theorem decideAnd_eq_false_of_not
    {left right : Prop} [Decidable left] [Decidable right]
    (notBoth : ¬ (left ∧ right)) :
    (decide left && decide right) = false := by
  apply Bool.eq_false_iff.mpr
  intro bothTrue
  have decided := Bool.and_eq_true_iff.mp bothTrue
  exact notBoth
    ⟨of_decide_eq_true decided.1, of_decide_eq_true decided.2⟩

theorem isDigitForBaseBody_executes
    (state : State) (wellFormed : StateWellFormed state)
    (byte : Byte) (base : Nat) :
    Executes lexerProgram (twoI32CalleeState state byte.val base)
      isDigitForBaseBody
      (.returned (some (.boolean (isDigitForBase byte base))))
      (twoI32CalleeState state byte.val base) := by
  let callee := twoI32CalleeState state byte.val base
  have decimalCondition := digitByteInRange_executes
    state wellFormed byte base 48 57
  have lowercaseCondition := digitByteInRange_executes
    state wellFormed byte base 97 102
  have uppercaseCondition := digitByteInRange_executes
    state wellFormed byte base 65 70
  by_cases decimal : 48 ≤ byte.val ∧ byte.val ≤ 57
  · have condition :
        Evaluates lexerProgram callee (digitByteInRange 48 57)
          (.boolean true) callee := by
      exact ⟨4, by simpa [callee, decimal.1, decimal.2] using decimalCondition⟩
    have valueResult := digitValueLessBase_executes
      state wellFormed byte base 48 0 decimal.1 (by omega)
    have returned := executesReturnValue (⟨6, valueResult⟩)
    have branch := executesIfTrue
      (elseBranch :=
        .ifThenElse (digitByteInRange 97 102)
          (.returnValue (some (digitValueLessBase 97 10)))
          (.ifThenElse (digitByteInRange 65 70)
            (.returnValue (some (digitValueLessBase 65 10)))
            (.returnValue (some (.value (.boolean false))))))
      condition returned
    simpa [isDigitForBaseBody, isDigitForBase, decimal.1, decimal.2,
      callee] using branch
  · have condition :
        Evaluates lexerProgram callee (digitByteInRange 48 57)
          (.boolean false) callee := by
      have falseValue := decideAnd_eq_false_of_not decimal
      rw [falseValue] at decimalCondition
      exact ⟨4, by simpa [callee] using decimalCondition⟩
    by_cases lowercase : 97 ≤ byte.val ∧ byte.val ≤ 102
    · have lowerCondition :
          Evaluates lexerProgram callee (digitByteInRange 97 102)
            (.boolean true) callee := by
        exact ⟨4, by simpa [callee, lowercase.1, lowercase.2] using
          lowercaseCondition⟩
      have valueResult := digitValueLessBase_executes
        state wellFormed byte base 97 10 lowercase.1 (by omega)
      have returned := executesReturnValue (⟨6, valueResult⟩)
      have inner := executesIfTrue
        (elseBranch :=
          .ifThenElse (digitByteInRange 65 70)
            (.returnValue (some (digitValueLessBase 65 10)))
            (.returnValue (some (.value (.boolean false)))))
        lowerCondition returned
      have branch := executesIfFalse
        (thenBranch := .returnValue (some (digitValueLessBase 48 0)))
        condition inner
      simpa [isDigitForBaseBody, isDigitForBase, decimal, lowercase.1,
        lowercase.2, callee] using branch
    · have lowerCondition :
          Evaluates lexerProgram callee (digitByteInRange 97 102)
            (.boolean false) callee := by
        have falseValue := decideAnd_eq_false_of_not lowercase
        rw [falseValue] at lowercaseCondition
        exact ⟨4, by simpa [callee] using lowercaseCondition⟩
      by_cases uppercase : 65 ≤ byte.val ∧ byte.val ≤ 70
      · have upperCondition :
            Evaluates lexerProgram callee (digitByteInRange 65 70)
              (.boolean true) callee := by
          exact ⟨4, by simpa [callee, uppercase.1, uppercase.2] using
            uppercaseCondition⟩
        have valueResult := digitValueLessBase_executes
          state wellFormed byte base 65 10 uppercase.1 (by omega)
        have returned := executesReturnValue (⟨6, valueResult⟩)
        have upperBranch := executesIfTrue
          (elseBranch := .returnValue (some (.value (.boolean false))))
          upperCondition returned
        have lowerBranch := executesIfFalse
          (thenBranch := .returnValue (some (digitValueLessBase 97 10)))
          lowerCondition upperBranch
        have branch := executesIfFalse
          (thenBranch := .returnValue (some (digitValueLessBase 48 0)))
          condition lowerBranch
        simpa [isDigitForBaseBody, isDigitForBase, decimal, lowercase,
          uppercase.1, uppercase.2, callee] using branch
      · have upperCondition :
            Evaluates lexerProgram callee (digitByteInRange 65 70)
              (.boolean false) callee := by
          have falseValue := decideAnd_eq_false_of_not uppercase
          rw [falseValue] at uppercaseCondition
          exact ⟨4, by simpa [callee] using uppercaseCondition⟩
        have falseValue :
            Evaluates lexerProgram callee (.value (.boolean false))
              (.boolean false) callee := ⟨1, rfl⟩
        have returned := executesReturnValue falseValue
        have upperBranch := executesIfFalse
          (thenBranch := .returnValue (some (digitValueLessBase 65 10)))
          upperCondition returned
        have lowerBranch := executesIfFalse
          (thenBranch := .returnValue (some (digitValueLessBase 97 10)))
          lowerCondition upperBranch
        have branch := executesIfFalse
          (thenBranch := .returnValue (some (digitValueLessBase 48 0)))
          condition lowerBranch
        simpa [isDigitForBaseBody, isDigitForBase, decimal, lowercase,
          uppercase, callee] using branch

theorem isDigitForBaseCall_executes
    (state : State) (wellFormed : StateWellFormed state)
    (byteExpr baseExpr : Expr) (byte : Byte) (base : Nat)
    (byteResult : Evaluates lexerProgram state byteExpr
      (.signed .i32 byte.val) state)
    (baseResult : Evaluates lexerProgram state baseExpr
      (.signed .i32 base) state) :
    Evaluates lexerProgram state
      (callIsDigitForBase byteExpr baseExpr)
      (.boolean (isDigitForBase byte base))
      (twoI32CallState state byte.val base) := by
  obtain ⟨byteFuel, byteExecution⟩ := byteResult
  obtain ⟨baseFuel, baseExecution⟩ := baseResult
  obtain ⟨bodyFuel, bodyExecution⟩ :=
    isDigitForBaseBody_executes state wellFormed byte base
  let fuel := max byteFuel (max baseFuel bodyFuel) + 1
  have byteEnough : byteFuel ≤ fuel + 1 := by
    dsimp [fuel]
    omega
  have baseEnough : baseFuel ≤ fuel := by
    dsimp [fuel]
    omega
  have bodyEnough : bodyFuel ≤ fuel + 2 := by
    dsimp [fuel]
    omega
  have byteAtFuel := evalExpr_done_at_larger_fuel
    (program := lexerProgram) byteEnough byteExecution
  have baseAtFuel := evalExpr_done_at_larger_fuel
    (program := lexerProgram) baseEnough baseExecution
  have bodyAtFuel := execStmt_done_at_larger_fuel
    (program := lexerProgram) bodyEnough bodyExecution
  have arguments :
      evalExprs (fuel + 2) lexerProgram state [byteExpr, baseExpr] =
        .done [.signed .i32 byte.val, .signed .i32 base] state := by
    rw [Lanius.Semantics.evalExprs.eq_def]
    simp only
    rw [byteAtFuel]
    simp only
    rw [Lanius.Semantics.evalExprs.eq_def]
    simp only
    rw [baseAtFuel]
    rfl
  have boundParameters :
      bindParameters isDigitForBaseFunction.parameters
        [.signed .i32 byte.val, .signed .i32 base] =
        some [(0, .signed .i32 byte.val), (1, .signed .i32 base)] := by
    rfl
  have callee :
      ({ state with locals := [] }).bindLocals
        [(0, .signed .i32 byte.val), (1, .signed .i32 base)] =
        twoI32CalleeState state byte.val base := by
    rfl
  refine ⟨fuel + 3, ?_⟩
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only [callIsDigitForBase]
  rw [arguments]
  simp only
  rw [show lexerProgram.function? isDigitForBaseFunction.id =
    some isDigitForBaseFunction by rfl]
  simp only
  rw [boundParameters]
  rw [show isDigitForBaseFunction.body = some isDigitForBaseBody by rfl]
  simp only
  rw [callee, bodyAtFuel]
  rfl

theorem successfulDigitsBody_executes
    (state : State) (wellFormed : StateWellFormed state) (offset : Nat) :
    execStmt 7 lexerProgram
      (singleArgumentCalleeState state (.signed .i32 offset))
      (.returnValue (some (.structValue digitScanDeclaration.id
        [.value (.boolean true), .local 0, i32Literal 0]))) =
      .done (.returned (some (digitScanValue (.success offset))))
        (singleArgumentCalleeState state (.signed .i32 offset)) := by
  let callee := singleArgumentCalleeState state (.signed .i32 offset)
  have localFound := singleArgumentCalleeState_local state wellFormed
    (.signed .i32 offset)
  have localResult := evalLocal_of_local 2 lexerProgram callee 0
    (.signed .i32 offset) localFound
  have firstResult : evalExpr 4 lexerProgram callee
      (.value (.boolean true)) = .done (.boolean true) callee := by rfl
  have fieldsResult :
      evalExprs 5 lexerProgram callee
        [.value (.boolean true), .local 0, i32Literal 0] =
      .done [.boolean true, .signed .i32 offset, .signed .i32 0] callee := by
    rw [Lanius.Semantics.evalExprs.eq_3, firstResult]
    simp only
    rw [Lanius.Semantics.evalExprs.eq_3, localResult]
    rfl
  rw [Lanius.Semantics.execStmt.eq_def]
  simp only
  rw [Lanius.Semantics.evalExpr]
  rw [fieldsResult]
  rfl

theorem failedDigitsBody_executes
    (state : State) (wellFormed : StateWellFormed state) (offset : Nat) :
    execStmt 7 lexerProgram
      (singleArgumentCalleeState state (.signed .i32 offset))
      (.returnValue (some (.structValue digitScanDeclaration.id
        [.value (.boolean false), i32Literal 0, .local 0]))) =
      .done (.returned (some (digitScanValue (.failure offset))))
        (singleArgumentCalleeState state (.signed .i32 offset)) := by
  let callee := singleArgumentCalleeState state (.signed .i32 offset)
  have localFound := singleArgumentCalleeState_local state wellFormed
    (.signed .i32 offset)
  have localResult := evalLocal_of_local 1 lexerProgram callee 0
    (.signed .i32 offset) localFound
  have firstResult : evalExpr 4 lexerProgram callee
      (.value (.boolean false)) = .done (.boolean false) callee := by rfl
  have secondResult : evalExpr 3 lexerProgram callee (i32Literal 0) =
      .done (.signed .i32 0) callee := by rfl
  have fieldsResult :
      evalExprs 5 lexerProgram callee
        [.value (.boolean false), i32Literal 0, .local 0] =
      .done [.boolean false, .signed .i32 0, .signed .i32 offset] callee := by
    rw [Lanius.Semantics.evalExprs.eq_3, firstResult]
    simp only
    rw [Lanius.Semantics.evalExprs.eq_3, secondResult]
    simp only
    rw [Lanius.Semantics.evalExprs.eq_3, localResult]
    simp only
    rw [Lanius.Semantics.evalExprs.eq_2]
  rw [Lanius.Semantics.execStmt.eq_def]
  simp only
  rw [Lanius.Semantics.evalExpr]
  rw [fieldsResult]
  rfl

theorem successfulDigitsCall_executes
    (state : State) (wellFormed : StateWellFormed state)
    (argument : Expr) (offset : Nat)
    (argumentResult : Evaluates lexerProgram state argument
      (.signed .i32 offset) state) :
    Evaluates lexerProgram state (callSuccessfulDigits argument)
      (digitScanValue (.success offset))
      (singleArgumentCallState state (.signed .i32 offset)) := by
  obtain ⟨argumentFuel, argumentExecution⟩ := argumentResult
  let fuel := max argumentFuel 6
  have argumentAtFuel := evalExpr_done_at_larger_fuel
    (program := lexerProgram) (Nat.le_max_left argumentFuel 6)
    argumentExecution
  have bodyBase := successfulDigitsBody_executes state wellFormed offset
  have bodyAtFuel := execStmt_done_at_larger_fuel
    (program := lexerProgram) (by dsimp [fuel]; omega : 7 ≤ fuel + 1) bodyBase
  refine ⟨fuel + 2, ?_⟩
  simpa [callSuccessfulDigits, fuel, singleArgumentCallState] using
    singleArgumentFunctionCall_executes fuel (by dsimp [fuel]; omega)
      successfulDigitsFunction i32Type
      (.returnValue (some (.structValue digitScanDeclaration.id
        [.value (.boolean true), .local 0, i32Literal 0])))
      state argument (.signed .i32 offset) (digitScanValue (.success offset))
      (singleArgumentCalleeState state (.signed .i32 offset))
      (by rfl) rfl rfl argumentAtFuel bodyAtFuel

theorem failedDigitsCall_executes
    (state : State) (wellFormed : StateWellFormed state)
    (argument : Expr) (offset : Nat)
    (argumentResult : Evaluates lexerProgram state argument
      (.signed .i32 offset) state) :
    Evaluates lexerProgram state (callFailedDigits argument)
      (digitScanValue (.failure offset))
      (singleArgumentCallState state (.signed .i32 offset)) := by
  obtain ⟨argumentFuel, argumentExecution⟩ := argumentResult
  let fuel := max argumentFuel 6
  have argumentAtFuel := evalExpr_done_at_larger_fuel
    (program := lexerProgram) (Nat.le_max_left argumentFuel 6)
    argumentExecution
  have bodyBase := failedDigitsBody_executes state wellFormed offset
  have bodyAtFuel := execStmt_done_at_larger_fuel
    (program := lexerProgram) (by dsimp [fuel]; omega : 7 ≤ fuel + 1) bodyBase
  refine ⟨fuel + 2, ?_⟩
  simpa [callFailedDigits, fuel, singleArgumentCallState] using
    singleArgumentFunctionCall_executes fuel (by dsimp [fuel]; omega)
      failedDigitsFunction i32Type
      (.returnValue (some (.structValue digitScanDeclaration.id
        [.value (.boolean false), i32Literal 0, .local 0])))
      state argument (.signed .i32 offset) (digitScanValue (.failure offset))
      (singleArgumentCalleeState state (.signed .i32 offset))
      (by rfl) rfl rfl argumentAtFuel bodyAtFuel

def digitParameterState (source : List Byte) (start base : Nat) : State :=
  (sourceState source).bindLocals
    [(0, .slice i32Type 0 [] 0 source.length),
      (1, .signed .i32 source.length),
      (2, .signed .i32 start),
      (3, .signed .i32 base)]

def digitInitialState (source : List Byte) (start base : Nat) : State :=
  (digitParameterState source start base).bindLocal 4
    (.signed .i32 (start + 1))

/-- Concrete state owned by the represented numeric loop. The explicit cell
layout is the low-level obligation that the separation-logic layer will
replace with points-to assertions and a frame rule. -/
structure DigitRunState (offsetCell : Nat)
    (state : State) (source : List Byte) (start base offset : Nat) : Prop where
  wellFormed : StateWellFormed state
  nextCell : 6 ≤ state.nextCell
  offsetBound : offset ≤ source.length
  offsetCellFresh : 5 ≤ offsetCell
  offsetCellBound : offsetCell < state.nextCell
  sourceCell : state.cellEntry? 0 =
    some { id := 0, value := some (.array (sourceValues source)) }
  sourceLocalId : state.cellId? 0 = some 1
  sourceLocalCell : state.cellEntry? 1 =
    some { id := 1, value := some (.slice i32Type 0 [] 0 source.length) }
  limitLocalId : state.cellId? 1 = some 2
  limitLocalCell : state.cellEntry? 2 =
    some { id := 2, value := some (.signed .i32 source.length) }
  startLocalId : state.cellId? 2 = some 3
  startLocalCell : state.cellEntry? 3 =
    some { id := 3, value := some (.signed .i32 start) }
  baseLocalId : state.cellId? 3 = some 4
  baseLocalCell : state.cellEntry? 4 =
    some { id := 4, value := some (.signed .i32 base) }
  offsetLocalId : state.cellId? 4 = some offsetCell
  offsetLocalCell : state.cellEntry? offsetCell =
    some { id := offsetCell, value := some (.signed .i32 offset) }

/-- The part of the numeric-loop state framed across offset mutation. The
offset cell is deliberately absent: it is the resource owned by the loop
step, while cells 0 through 4 are the disjoint caller frame. -/
def digitRunFrameAssertion
    (source : List Byte) (start base : Nat) : Assertion :=
  Assertion.pointsTo 0 (some (.array (sourceValues source))) ⋆
  Assertion.localPointsTo 0 1
    (some (.slice i32Type 0 [] 0 source.length)) ⋆
  Assertion.localPointsTo 1 2
    (some (.signed .i32 source.length)) ⋆
  Assertion.localPointsTo 2 3 (some (.signed .i32 start)) ⋆
  Assertion.localPointsTo 3 4 (some (.signed .i32 base))

theorem digitRunFrameAssertion_holds_iff :
    (digitRunFrameAssertion source start base).holds state ↔
      state.cellEntry? 0 =
          some { id := 0, value := some (.array (sourceValues source)) } ∧
      state.cellId? 0 = some 1 ∧
      state.cellEntry? 1 = some {
        id := 1
        value := some (.slice i32Type 0 [] 0 source.length)
      } ∧
      state.cellId? 1 = some 2 ∧
      state.cellEntry? 2 = some {
        id := 2
        value := some (.signed .i32 source.length)
      } ∧
      state.cellId? 2 = some 3 ∧
      state.cellEntry? 3 =
        some { id := 3, value := some (.signed .i32 start) } ∧
      state.cellId? 3 = some 4 ∧
      state.cellEntry? 4 =
        some { id := 4, value := some (.signed .i32 base) } := by
  simp [digitRunFrameAssertion, Assertion.sep, Assertion.pointsTo,
    Assertion.localPointsTo, CellSet.Disjoint, CellSet.singleton,
    CellSet.union, and_assoc]

theorem DigitRunState.frameHolds
    (invariant : DigitRunState offsetCell state source start base offset) :
    (digitRunFrameAssertion source start base).holds state := by
  rw [digitRunFrameAssertion_holds_iff]
  exact ⟨invariant.sourceCell, invariant.sourceLocalId,
    invariant.sourceLocalCell, invariant.limitLocalId,
    invariant.limitLocalCell, invariant.startLocalId,
    invariant.startLocalCell, invariant.baseLocalId,
    invariant.baseLocalCell⟩

theorem digitRunFrameAssertion_disjoint_offset
    (fresh : 5 ≤ offsetCell) :
    CellSet.Disjoint (digitRunFrameAssertion source start base).footprint
      (CellSet.singleton offsetCell) := by
  intro cell member written
  subst cell
  have cases : offsetCell = 0 ∨ offsetCell = 1 ∨ offsetCell = 2 ∨
      offsetCell = 3 ∨ offsetCell = 4 := by
    simpa [digitRunFrameAssertion, Assertion.sep, Assertion.pointsTo,
      Assertion.localPointsTo, CellSet.singleton, CellSet.union] using member
  rcases cases with same | same | same | same | same <;>
    subst offsetCell <;> simp at fresh

theorem DigitRunState.sourceLocal
    (invariant : DigitRunState offsetCell state source start base offset) :
    state.local? 0 = some (.slice i32Type 0 [] 0 source.length) := by
  simp [State.local?, State.cell?, invariant.sourceLocalId,
    invariant.sourceLocalCell]

theorem DigitRunState.limitLocal
    (invariant : DigitRunState offsetCell state source start base offset) :
    state.local? 1 = some (.signed .i32 source.length) := by
  simp [State.local?, State.cell?, invariant.limitLocalId,
    invariant.limitLocalCell]

theorem DigitRunState.startLocal
    (invariant : DigitRunState offsetCell state source start base offset) :
    state.local? 2 = some (.signed .i32 start) := by
  simp [State.local?, State.cell?, invariant.startLocalId,
    invariant.startLocalCell]

theorem DigitRunState.baseLocal
    (invariant : DigitRunState offsetCell state source start base offset) :
    state.local? 3 = some (.signed .i32 base) := by
  simp [State.local?, State.cell?, invariant.baseLocalId,
    invariant.baseLocalCell]

theorem DigitRunState.offsetLocal
    (invariant : DigitRunState offsetCell state source start base offset) :
    state.local? 4 = some (.signed .i32 offset) := by
  simp [State.local?, State.cell?, invariant.offsetLocalId,
    invariant.offsetLocalCell]

theorem digitParameterState_well_formed
    (source : List Byte) (start base : Nat) :
    StateWellFormed (digitParameterState source start base) := by
  exact bindLocals_preserves_well_formed (sourceState source)
    [(0, .slice i32Type 0 [] 0 source.length),
      (1, .signed .i32 source.length), (2, .signed .i32 start),
      (3, .signed .i32 base)]
    (sourceState_well_formed source)

theorem digitParameterState_sourceCell (source : List Byte) (start base : Nat) :
    (digitParameterState source start base).cellEntry? 0 =
      some { id := 0, value := some (.array (sourceValues source)) } := by rfl

theorem digitParameterState_sourceLocal (source : List Byte) (start base : Nat) :
    (digitParameterState source start base).local? 0 =
      some (.slice i32Type 0 [] 0 source.length) := by rfl

theorem digitParameterState_limitLocal (source : List Byte) (start base : Nat) :
    (digitParameterState source start base).local? 1 =
      some (.signed .i32 source.length) := by rfl

theorem digitParameterState_startLocal (source : List Byte) (start base : Nat) :
    (digitParameterState source start base).local? 2 =
      some (.signed .i32 start) := by rfl

theorem digitParameterState_baseLocal (source : List Byte) (start base : Nat) :
    (digitParameterState source start base).local? 3 =
      some (.signed .i32 base) := by rfl

theorem digitInitialState_invariant
    (source : List Byte) (start base : Nat)
    (startInBounds : start < source.length) :
    DigitRunState 5 (digitInitialState source start base)
      source start base (start + 1) := by
  constructor
  · exact bindLocal_preserves_well_formed _ 4 (.signed .i32 (start + 1))
      (digitParameterState_well_formed source start base)
  · change 6 ≤ 6
    decide
  · omega
  · exact Nat.le_refl 5
  · change 5 < 6
    decide
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl
  · rfl

theorem digitInitialState_after_frame_invariant
    (source : List Byte) (start base : Nat)
    (afterParameters : State)
    (extension : FrameExtension
      (digitParameterState source start base) afterParameters)
    (afterWellFormed : StateWellFormed afterParameters)
    (startInBounds : start < source.length) :
    DigitRunState afterParameters.nextCell
      (afterParameters.bindLocal 4 (.signed .i32 (start + 1)))
      source start base (start + 1) := by
  let initial := afterParameters.bindLocal 4 (.signed .i32 (start + 1))
  have parameterNext : (digitParameterState source start base).nextCell = 5 := rfl
  have afterNext : 5 ≤ afterParameters.nextCell := by
    simpa [parameterNext] using extension.nextCell
  have oldAfter (cell : Nat) (bound : cell < 5) :
      cell < afterParameters.nextCell :=
    Nat.lt_of_lt_of_le bound afterNext
  have oldParameter (cell : Nat) (bound : cell < 5) :
      (digitParameterState source start base).cellEntry? cell =
        afterParameters.cellEntry? cell := by
    exact (extension.oldCells cell (by simpa [parameterNext] using bound)).symm
  have sourceIdAfter : afterParameters.cellId? 0 = some 1 := by
    unfold State.cellId?
    rw [extension.locals]
    rfl
  have limitIdAfter : afterParameters.cellId? 1 = some 2 := by
    unfold State.cellId?
    rw [extension.locals]
    rfl
  have startIdAfter : afterParameters.cellId? 2 = some 3 := by
    unfold State.cellId?
    rw [extension.locals]
    rfl
  have baseIdAfter : afterParameters.cellId? 3 = some 4 := by
    unfold State.cellId?
    rw [extension.locals]
    rfl
  have offsetEntry := bindCell_finds_fresh_cell afterParameters 4
    (some (.signed .i32 (start + 1))) afterWellFormed
  constructor
  · exact bindLocal_preserves_well_formed afterParameters 4
      (.signed .i32 (start + 1)) afterWellFormed
  · change 6 ≤ afterParameters.nextCell + 1
    exact Nat.succ_le_succ afterNext
  · exact Nat.succ_le_of_lt startInBounds
  · exact afterNext
  · change afterParameters.nextCell < afterParameters.nextCell + 1
    exact Nat.lt_succ_self _
  · exact (bindCell_preserves_old_cell afterParameters 4
      (some (.signed .i32 (start + 1))) 0 (oldAfter 0 (by decide))).trans
      ((oldParameter 0 (by decide)).symm.trans
        (digitParameterState_sourceCell source start base))
  · simpa [initial, State.bindLocal, State.bindCell, State.cellId?] using
      sourceIdAfter
  · exact (bindCell_preserves_old_cell afterParameters 4
      (some (.signed .i32 (start + 1))) 1 (oldAfter 1 (by decide))).trans
      ((oldParameter 1 (by decide)).symm.trans (by rfl))
  · simpa [initial, State.bindLocal, State.bindCell, State.cellId?] using
      limitIdAfter
  · exact (bindCell_preserves_old_cell afterParameters 4
      (some (.signed .i32 (start + 1))) 2 (oldAfter 2 (by decide))).trans
      ((oldParameter 2 (by decide)).symm.trans (by rfl))
  · simpa [initial, State.bindLocal, State.bindCell, State.cellId?] using
      startIdAfter
  · exact (bindCell_preserves_old_cell afterParameters 4
      (some (.signed .i32 (start + 1))) 3 (oldAfter 3 (by decide))).trans
      ((oldParameter 3 (by decide)).symm.trans (by rfl))
  · simpa [initial, State.bindLocal, State.bindCell, State.cellId?] using
      baseIdAfter
  · exact (bindCell_preserves_old_cell afterParameters 4
      (some (.signed .i32 (start + 1))) 4 (oldAfter 4 (by decide))).trans
      ((oldParameter 4 (by decide)).symm.trans (by rfl))
  · rfl
  · simpa [initial, State.bindLocal] using offsetEntry

theorem DigitRunState.afterFrameExtension
    (invariant : DigitRunState offsetCell state source start base offset)
    (extension : FrameExtension state after)
    (afterWellFormed : StateWellFormed after) :
    DigitRunState offsetCell after source start base offset := by
  have old (cell : Nat) (bound : cell < 6) : cell < state.nextCell :=
    Nat.lt_of_lt_of_le bound invariant.nextCell
  constructor
  · exact afterWellFormed
  · exact Nat.le_trans invariant.nextCell extension.nextCell
  · exact invariant.offsetBound
  · exact invariant.offsetCellFresh
  · exact Nat.lt_of_lt_of_le invariant.offsetCellBound extension.nextCell
  · exact (extension.oldCells 0 (old 0 (by decide))).trans
      invariant.sourceCell
  · simpa [State.cellId?, extension.locals] using invariant.sourceLocalId
  · exact (extension.oldCells 1 (old 1 (by decide))).trans
      invariant.sourceLocalCell
  · simpa [State.cellId?, extension.locals] using invariant.limitLocalId
  · exact (extension.oldCells 2 (old 2 (by decide))).trans
      invariant.limitLocalCell
  · simpa [State.cellId?, extension.locals] using invariant.startLocalId
  · exact (extension.oldCells 3 (old 3 (by decide))).trans
      invariant.startLocalCell
  · simpa [State.cellId?, extension.locals] using invariant.baseLocalId
  · exact (extension.oldCells 4 (old 4 (by decide))).trans
      invariant.baseLocalCell
  · simpa [State.cellId?, extension.locals] using invariant.offsetLocalId
  · exact (extension.oldCells offsetCell invariant.offsetCellBound).trans
      invariant.offsetLocalCell

/-- The numeric-run proof depends on a program only through these three
    source calls. Indexing, mutation, control flow, loop invariants, and frame
    reasoning are shared by every implementation of this interface. -/
class DigitRunCallSemantics (program : Program) : Prop where
  target : program.target = lexerProgram.target
  isDigitForBaseCall_executes :
    ∀ (state : State), StateWellFormed state →
      ∀ (byteExpr baseExpr : Expr) (byte : Byte) (base : Nat),
        Evaluates program state byteExpr (.signed .i32 byte.val) state →
        Evaluates program state baseExpr (.signed .i32 base) state →
        Evaluates program state (callIsDigitForBase byteExpr baseExpr)
          (.boolean (isDigitForBase byte base))
          (twoI32CallState state byte.val base)
  successfulDigitsCall_executes :
    ∀ (state : State), StateWellFormed state →
      ∀ (argument : Expr) (offset : Nat),
        Evaluates program state argument (.signed .i32 offset) state →
        Evaluates program state (callSuccessfulDigits argument)
          (digitScanValue (.success offset))
          (singleArgumentCallState state (.signed .i32 offset))
  failedDigitsCall_executes :
    ∀ (state : State), StateWellFormed state →
      ∀ (argument : Expr) (offset : Nat),
        Evaluates program state argument (.signed .i32 offset) state →
        Evaluates program state (callFailedDigits argument)
          (digitScanValue (.failure offset))
          (singleArgumentCallState state (.signed .i32 offset))

instance lexerProgramDigitRunCallSemantics :
    DigitRunCallSemantics lexerProgram where
  target := rfl
  isDigitForBaseCall_executes := by
    intro state wellFormed byteExpr baseExpr byte base byteResult baseResult
    exact isDigitForBaseCall_executes state wellFormed byteExpr baseExpr byte
      base byteResult baseResult
  successfulDigitsCall_executes := by
    intro state wellFormed argument offset argumentResult
    exact successfulDigitsCall_executes state wellFormed argument offset
      argumentResult
  failedDigitsCall_executes := by
    intro state wellFormed argument offset argumentResult
    exact failedDigitsCall_executes state wellFormed argument offset
      argumentResult

theorem DigitRunCallSemantics.wrapSigned_i32_ofNat
    {program : Program} [contracts : DigitRunCallSemantics program]
    (value : Nat) (bounded : value ≤ 2147483647) :
    wrapSigned program.target .i32 (Int.ofNat value) = Int.ofNat value := by
  rw [contracts.target]
  exact Lanius.Compiler.Lexer.Program.wrapSigned_i32_ofNat value bounded

section GenericDigitRunExecution

variable {program : Program} [DigitRunCallSemantics program]

theorem DigitRunState.evalLoopCondition
    (invariant : DigitRunState offsetCell state source start base offset) :
    evalExpr 13 program state
      (.binary .less (.local 4) (.local 1)) =
      .done (.boolean (offset < source.length)) state :=
  evalLocalLessLocal state offset source.length 4 1
    invariant.offsetLocal invariant.limitLocal

theorem DigitRunState.evalSourceByte
    (invariant : DigitRunState offsetCell state source start base offset)
    (inBounds : offset < source.length) :
    evalExpr 10 program state (.index (.local 0) (.local 4)) =
      .done (.signed .i32 (source.get ⟨offset, inBounds⟩).val) state :=
  evalSourceIndexAt state source offset 4 inBounds invariant.sourceLocal
    invariant.offsetLocal invariant.sourceCell

theorem FrameExtension.domainExtension
    (extension : FrameExtension before after)
    (beforeWellFormed : StateWellFormed before) :
    CellDomainExtension before after := by
  constructor
  intro entry member
  have old := beforeWellFormed.cellIdsBelowNext entry member
  have foundBefore := stateWellFormed_cellEntry_of_mem beforeWellFormed member
  have foundAfter : after.cellEntry? entry.id = some entry := by
    rw [extension.oldCells entry.id old, foundBefore]
  exact ⟨entry, List.mem_of_find?_eq_some foundAfter, rfl⟩

def digitByteState (state : State) (byte : Byte) : State :=
  state.bindLocal 5 (.signed .i32 byte.val)

theorem DigitRunState.afterByteBind
    (invariant : DigitRunState offsetCell state source start base offset)
    (byte : Byte) :
    DigitRunState offsetCell (digitByteState state byte)
      source start base offset := by
  have old (cell : Nat) (bound : cell < 6) : cell < state.nextCell :=
    Nat.lt_of_lt_of_le bound invariant.nextCell
  let next := digitByteState state byte
  constructor
  · exact bindLocal_preserves_well_formed state 5 (.signed .i32 byte.val)
      invariant.wellFormed
  · change 6 ≤ state.nextCell + 1
    exact Nat.le_trans invariant.nextCell (Nat.le_succ state.nextCell)
  · exact invariant.offsetBound
  · exact invariant.offsetCellFresh
  · exact Nat.lt_succ_of_lt invariant.offsetCellBound
  · exact (bindCell_preserves_old_cell state 5
      (some (.signed .i32 byte.val)) 0 (old 0 (by decide))).trans
      invariant.sourceCell
  · simpa [next, digitByteState, State.bindLocal, State.bindCell,
      State.cellId?] using invariant.sourceLocalId
  · exact (bindCell_preserves_old_cell state 5
      (some (.signed .i32 byte.val)) 1 (old 1 (by decide))).trans
      invariant.sourceLocalCell
  · simpa [next, digitByteState, State.bindLocal, State.bindCell,
      State.cellId?] using invariant.limitLocalId
  · exact (bindCell_preserves_old_cell state 5
      (some (.signed .i32 byte.val)) 2 (old 2 (by decide))).trans
      invariant.limitLocalCell
  · simpa [next, digitByteState, State.bindLocal, State.bindCell,
      State.cellId?] using invariant.startLocalId
  · exact (bindCell_preserves_old_cell state 5
      (some (.signed .i32 byte.val)) 3 (old 3 (by decide))).trans
      invariant.startLocalCell
  · simpa [next, digitByteState, State.bindLocal, State.bindCell,
      State.cellId?] using invariant.baseLocalId
  · exact (bindCell_preserves_old_cell state 5
      (some (.signed .i32 byte.val)) 4 (old 4 (by decide))).trans
      invariant.baseLocalCell
  · simpa [next, digitByteState, State.bindLocal, State.bindCell,
      State.cellId?] using invariant.offsetLocalId
  · exact (bindCell_preserves_old_cell state 5
      (some (.signed .i32 byte.val)) offsetCell
      invariant.offsetCellBound).trans
      invariant.offsetLocalCell

theorem digitByteState_byteLocal
    (invariant : DigitRunState offsetCell state source start base offset)
    (byte : Byte) :
    (digitByteState state byte).local? 5 =
      some (.signed .i32 byte.val) := by
  have fresh := bindCell_finds_fresh_cell state 5
    (some (.signed .i32 byte.val)) invariant.wellFormed
  simp only [digitByteState, State.bindLocal, State.local?, State.cellId?,
    State.bindCell, List.find?_cons, beq_self_eq_true]
  exact congrArg (fun entry => entry.bind Cell.value) fresh

theorem bindLocal_finds_bound
    (state : State) (wellFormed : StateWellFormed state)
    (id : VarId) (value : Value) :
    (state.bindLocal id value).local? id = some value := by
  have fresh := bindCell_finds_fresh_cell state id (some value) wellFormed
  simp only [State.bindLocal, State.local?, State.cellId?, State.bindCell,
    List.find?_cons, beq_self_eq_true]
  exact congrArg (fun entry => entry.bind Cell.value) fresh

theorem DigitRunState.afterAuxBind
    (invariant : DigitRunState offsetCell state source start base offset)
    (id : VarId) (auxiliary : 4 < id) (value : Value) :
    DigitRunState offsetCell (state.bindLocal id value)
      source start base offset := by
  have old (cell : Nat) (bound : cell < 6) : cell < state.nextCell :=
    Nat.lt_of_lt_of_le bound invariant.nextCell
  have id0 : id ≠ 0 := Nat.ne_of_gt
    (Nat.lt_trans (by decide : 0 < 4) auxiliary)
  have id1 : id ≠ 1 := Nat.ne_of_gt
    (Nat.lt_trans (by decide : 1 < 4) auxiliary)
  have id2 : id ≠ 2 := Nat.ne_of_gt
    (Nat.lt_trans (by decide : 2 < 4) auxiliary)
  have id3 : id ≠ 3 := Nat.ne_of_gt
    (Nat.lt_trans (by decide : 3 < 4) auxiliary)
  have id4 : id ≠ 4 := Nat.ne_of_gt auxiliary
  constructor
  · exact bindLocal_preserves_well_formed state id value invariant.wellFormed
  · change 6 ≤ state.nextCell + 1
    exact Nat.le_trans invariant.nextCell (Nat.le_succ state.nextCell)
  · exact invariant.offsetBound
  · exact invariant.offsetCellFresh
  · exact Nat.lt_succ_of_lt invariant.offsetCellBound
  · exact (bindCell_preserves_old_cell state id (some value) 0
      (old 0 (by decide))).trans invariant.sourceCell
  · simpa [State.bindLocal, State.bindCell, State.cellId?, id0] using
      invariant.sourceLocalId
  · exact (bindCell_preserves_old_cell state id (some value) 1
      (old 1 (by decide))).trans invariant.sourceLocalCell
  · simpa [State.bindLocal, State.bindCell, State.cellId?, id1] using
      invariant.limitLocalId
  · exact (bindCell_preserves_old_cell state id (some value) 2
      (old 2 (by decide))).trans invariant.limitLocalCell
  · simpa [State.bindLocal, State.bindCell, State.cellId?, id2] using
      invariant.startLocalId
  · exact (bindCell_preserves_old_cell state id (some value) 3
      (old 3 (by decide))).trans invariant.startLocalCell
  · simpa [State.bindLocal, State.bindCell, State.cellId?, id3] using
      invariant.baseLocalId
  · exact (bindCell_preserves_old_cell state id (some value) 4
      (old 4 (by decide))).trans invariant.baseLocalCell
  · simpa [State.bindLocal, State.bindCell, State.cellId?, id4] using
      invariant.offsetLocalId
  · exact (bindCell_preserves_old_cell state id (some value) offsetCell
      invariant.offsetCellBound).trans invariant.offsetLocalCell

def updatedDigitOffsetState
    (state : State) (offsetCell nextOffset : Nat) : State :=
  { state with
    cells := replaceCell state.cells offsetCell (.signed .i32 nextOffset) }

theorem DigitRunState.assignOffset
    (invariant : DigitRunState offsetCell state source start base offset)
    (nextOffset : Nat) :
    state.assignCell offsetCell (.signed .i32 nextOffset) =
      some (updatedDigitOffsetState state offsetCell nextOffset) := by
  simp [State.assignCell, invariant.offsetLocalCell,
    updatedDigitOffsetState]

theorem DigitRunState.afterOffsetAssignment
    (invariant : DigitRunState offsetCell state source start base offset)
    (nextOffset : Nat) (nextBound : nextOffset ≤ source.length) :
    DigitRunState offsetCell
      (updatedDigitOffsetState state offsetCell nextOffset)
      source start base nextOffset := by
  have assigned := invariant.assignOffset nextOffset
  have framed : (digitRunFrameAssertion source start base).holds
      (updatedDigitOffsetState state offsetCell nextOffset) :=
    (assignCell_effect assigned).preserve invariant.wellFormed
      (digitRunFrameAssertion source start base) invariant.frameHolds
      (digitRunFrameAssertion_disjoint_offset invariant.offsetCellFresh)
  have frameFacts := digitRunFrameAssertion_holds_iff.mp framed
  rcases frameFacts with ⟨sourceCell, sourceLocalId, sourceLocalCell,
    limitLocalId, limitLocalCell, startLocalId, startLocalCell,
    baseLocalId, baseLocalCell⟩
  constructor
  · exact assignCell_preserves_well_formed invariant.wellFormed assigned
  · simpa [updatedDigitOffsetState] using invariant.nextCell
  · exact nextBound
  · exact invariant.offsetCellFresh
  · simpa [updatedDigitOffsetState] using invariant.offsetCellBound
  · exact sourceCell
  · exact sourceLocalId
  · exact sourceLocalCell
  · exact limitLocalId
  · exact limitLocalCell
  · exact startLocalId
  · exact startLocalCell
  · exact baseLocalId
  · exact baseLocalCell
  · simpa [updatedDigitOffsetState, State.cellId?] using invariant.offsetLocalId
  · exact assignCell_finds_assigned assigned

theorem DigitRunState.restoreAfter
    (beforeInvariant : DigitRunState offsetCell before source start base beforeOffset)
    (completedInvariant : DigitRunState offsetCell completed source start base afterOffset)
    (domain : CellDomainExtension before completed) :
    DigitRunState offsetCell (restoreLocals before completed)
      source start base afterOffset := by
  constructor
  · exact domain.restoreLocals_well_formed beforeInvariant.wellFormed
      completedInvariant.wellFormed
  · exact completedInvariant.nextCell
  · exact completedInvariant.offsetBound
  · exact completedInvariant.offsetCellFresh
  · exact completedInvariant.offsetCellBound
  · exact completedInvariant.sourceCell
  · simpa [restoreLocals, State.cellId?] using beforeInvariant.sourceLocalId
  · exact completedInvariant.sourceLocalCell
  · simpa [restoreLocals, State.cellId?] using beforeInvariant.limitLocalId
  · exact completedInvariant.limitLocalCell
  · simpa [restoreLocals, State.cellId?] using beforeInvariant.startLocalId
  · exact completedInvariant.startLocalCell
  · simpa [restoreLocals, State.cellId?] using beforeInvariant.baseLocalId
  · exact completedInvariant.baseLocalCell
  · simpa [restoreLocals, State.cellId?] using beforeInvariant.offsetLocalId
  · exact completedInvariant.offsetLocalCell

theorem evalI32LocalGreaterEqualLocal
    (state : State) (leftId rightId : VarId) (left right : Nat)
    (leftFound : state.local? leftId = some (.signed .i32 left))
    (rightFound : state.local? rightId = some (.signed .i32 right)) :
    evalExpr 4 program state
      (.binary .greaterEqual (.local leftId) (.local rightId)) =
      .done (.boolean (decide (right ≤ left))) state := by
  have leftResult := evalLocal_of_local 2 program state leftId
    (.signed .i32 left) leftFound
  have rightResult := evalLocal_of_local 2 program state rightId
    (.signed .i32 right) rightFound
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [leftResult]
  simp only
  rw [rightResult]
  simp only [evalBinaryValue, beq_self_eq_true, if_true, evalSignedBinary]
  have equivalent : decide ((left : Int) ≥ (right : Int)) =
      decide (right ≤ left) := by
    simpa using intOfNat_le_decide right left
  rw [equivalent]

theorem DigitRunState.execOffsetSet
    (invariant : DigitRunState offsetCell state source start base offset)
    (expression : Expr) (nextOffset : Nat)
    (valueResult : evalExpr 9 program state expression =
      .done (.signed .i32 nextOffset) state) :
    execStmt 11 program state
      (.expression (.assign .set (.local 4) expression)) =
      .done .next
        (updatedDigitOffsetState state offsetCell nextOffset) := by
  have assigned := invariant.assignOffset nextOffset
  have placeResult :
      evalPlace 9 program state (.local 4) =
        .done { root := offsetCell, projections := [], value := some (.signed .i32 offset) } state := by
    rw [Lanius.Semantics.evalPlace.eq_def]
    simp only
    rw [invariant.offsetLocalId]
    simp only
    rw [invariant.offsetLocalCell]
  have writeResult :
      writeResolvedPlace state
        { root := offsetCell, projections := [], value := some (.signed .i32 offset) }
        (.signed .i32 nextOffset) =
        .ok (updatedDigitOffsetState state offsetCell nextOffset) := by
    simp [writeResolvedPlace, assigned]
  have operationResult :
      evalAssignValue program.target .set
        (some (.signed .i32 offset)) (.signed .i32 nextOffset) =
        .ok (.signed .i32 nextOffset) := by rfl
  have assignmentResult :
      evalExpr 10 program state
        (.assign .set (.local 4) expression) =
        .done .unit
          (updatedDigitOffsetState state offsetCell nextOffset) := by
    rw [Lanius.Semantics.evalExpr.eq_def]
    simp only
    rw [placeResult]
    simp only
    rw [valueResult]
    simp only
    rw [operationResult]
    simp only
    rw [writeResult]
  rw [Lanius.Semantics.execStmt.eq_def]
  simp only
  rw [assignmentResult]

theorem DigitRunState.execOffsetIncrement
    (invariant : DigitRunState offsetCell state source start base offset)
    (bounded : offset + 1 ≤ 2147483647) :
    execStmt 11 program state (incrementLocal 4 1) =
      .done .next
        (updatedDigitOffsetState state offsetCell (offset + 1)) := by
  have assigned := invariant.assignOffset (offset + 1)
  have assignedCoerced :
      state.assignCell offsetCell (.signed .i32 ((offset : Int) + 1)) =
        some (updatedDigitOffsetState state offsetCell (offset + 1)) := by
    simpa using assigned
  have placeResult :
      evalPlace 9 program state (.local 4) =
        .done { root := offsetCell, projections := [], value := some (.signed .i32 offset) } state := by
    rw [Lanius.Semantics.evalPlace.eq_def]
    simp only
    rw [invariant.offsetLocalId]
    simp only
    rw [invariant.offsetLocalCell]
  have rightResult :
      evalExpr 9 program state (i32Literal 1) =
        .done (.signed .i32 1) state := by rfl
  have wrapped := DigitRunCallSemantics.wrapSigned_i32_ofNat
    (program := program) (offset + 1) bounded
  have wrappedCoerced :
      wrapSigned program.target .i32 ((offset : Int) + 1) =
        Int.ofNat (offset + 1) := by
    simpa using wrapped
  have arithmeticResult :
      evalAssignValue program.target .add
        (some (.signed .i32 offset)) (.signed .i32 1) =
        .ok (.signed .i32 (Int.ofNat (offset + 1))) := by
    simp only [evalAssignValue, assignOpBinary?, evalBinaryValue,
      beq_self_eq_true, if_true, evalSignedBinary]
    simpa using congrArg
      (fun value => (Except.ok (.signed .i32 value) : Except Trap Value))
      wrappedCoerced
  have writeResult :
      writeResolvedPlace state
        { root := offsetCell, projections := [], value := some (.signed .i32 offset) }
        (.signed .i32 (Int.ofNat (offset + 1))) =
        .ok (updatedDigitOffsetState state offsetCell (offset + 1)) := by
    simp [writeResolvedPlace, assignedCoerced]
  have assignmentResult :
      evalExpr 10 program state
        (.assign .add (.local 4) (i32Literal 1)) =
        .done .unit
          (updatedDigitOffsetState state offsetCell (offset + 1)) := by
    rw [Lanius.Semantics.evalExpr.eq_def]
    simp only
    rw [placeResult]
    simp only
    rw [rightResult]
    simp only
    rw [arithmeticResult]
    simp only
    rw [writeResult]
  rw [Lanius.Semantics.execStmt.eq_def]
  simp only [incrementLocal]
  rw [assignmentResult]

def digitPredicateState (state : State) (byte : Byte) (base : Nat) : State :=
  twoI32CallState state byte.val base

theorem DigitRunState.execPredicateFromByteLocal
    (invariant : DigitRunState offsetCell state source start base offset)
    (byte : Byte)
    (byteLocal : state.local? 5 = some (.signed .i32 byte.val)) :
    Evaluates program state
      (callIsDigitForBase (.local 5) (.local 3))
      (.boolean (isDigitForBase byte base))
      (digitPredicateState state byte base) := by
  have byteResult : Evaluates program state (.local 5)
      (.signed .i32 byte.val) state :=
    ⟨1, evalLocal_of_local 0 program state 5
      (.signed .i32 byte.val) byteLocal⟩
  have baseResult : Evaluates program state (.local 3)
      (.signed .i32 base) state :=
    ⟨1, evalLocal_of_local 0 program state 3
      (.signed .i32 base) invariant.baseLocal⟩
  simpa [digitPredicateState] using
    DigitRunCallSemantics.isDigitForBaseCall_executes state invariant.wellFormed
      (.local 5) (.local 3) byte base byteResult baseResult

theorem DigitRunState.execAcceptedDigitBody
    (invariant : DigitRunState offsetCell state source start base offset)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : offset < source.length)
    (accepted : isDigitForBase
      (source.get ⟨offset, inBounds⟩) base = true) :
    ∃ finalState,
      Executes program state digitRunLoopBody .next finalState ∧
      DigitRunState offsetCell finalState source start base (offset + 1) ∧
      CellDomainExtension state finalState := by
  let byte := source.get ⟨offset, inBounds⟩
  let withByte := digitByteState state byte
  have byteInvariant := invariant.afterByteBind byte
  have byteLocal := digitByteState_byteLocal invariant byte
  have initializer :
      Evaluates program state (.index (.local 0) (.local 4))
        (.signed .i32 byte.val) state := by
    exact ⟨10, by simpa [byte] using invariant.evalSourceByte inBounds⟩
  let called := digitPredicateState withByte byte base
  have predicateCall := byteInvariant.execPredicateFromByteLocal
    (program := program) byte byteLocal
  have acceptedByte : isDigitForBase byte base = true := by
    simpa [byte] using accepted
  rw [acceptedByte] at predicateCall
  have predicateCondition :
      Evaluates program withByte
        (callIsDigitForBase (.local 5) (.local 3))
        (.boolean true) called := by
    simpa [called, withByte] using predicateCall
  have predicateExtension : FrameExtension withByte called := by
    simpa [called, digitPredicateState] using
      twoI32CallState_extends withByte byte.val base
  have calledWellFormed : StateWellFormed called := by
    simpa [called, digitPredicateState] using
      twoI32CallState_well_formed withByte byteInvariant.wellFormed
        byte.val base
  have calledInvariant := byteInvariant.afterFrameExtension
    predicateExtension calledWellFormed
  let assigned := updatedDigitOffsetState called offsetCell (offset + 1)
  have incrementBound : offset + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound
  have incrementExec :
      Executes program called (incrementLocal 4 1) .next assigned :=
    ⟨11, by simpa [assigned] using
      calledInvariant.execOffsetIncrement incrementBound⟩
  have assignedInvariant :
      DigitRunState offsetCell assigned source start base (offset + 1) := by
    exact calledInvariant.afterOffsetAssignment (offset + 1)
      (Nat.succ_le_of_lt inBounds)
  have branchExec :
      Executes program withByte
        (.ifThenElse (callIsDigitForBase (.local 5) (.local 3))
          (incrementLocal 4 1)
          (.ifThenElse (.binary .equal (.local 5) (i32Literal 95))
            (.letLocal 6 i32Type
              (.binary .add (.local 4) (i32Literal 1))
              (.sequence
                (.ifThenElse (.binary .greaterEqual (.local 6) (.local 1))
                  (.returnValue (some (callFailedDigits (.local 6)))) .skip)
                (.sequence
                  (.ifThenElse
                    (.unary .logicalNot
                      (callIsDigitForBase
                        (.index (.local 0) (.local 6)) (.local 3)))
                    (.returnValue (some (callFailedDigits (.local 6)))) .skip)
                  (assignLocal 4
                    (.binary .add (.local 6) (i32Literal 1))))))
            (.returnValue (some (callSuccessfulDigits (.local 4))))))
        .next assigned :=
    executesIfTrue predicateCondition incrementExec
  have letExec := executesLetLocal (type := i32Type) initializer (by
    simpa [withByte, digitByteState] using branchExec)
  let finalState := restoreLocals state assigned
  have bindDomain : CellDomainExtension state withByte := by
    simpa [withByte, digitByteState] using
      bindLocal_domain_extends state 5 (.signed .i32 byte.val)
  have callDomain : CellDomainExtension withByte called :=
    predicateExtension.domainExtension byteInvariant.wellFormed
  have assignmentDomain : CellDomainExtension called assigned := by
    exact assignCell_domain_extends
      (calledInvariant.assignOffset (offset + 1))
  have completedDomain : CellDomainExtension state assigned :=
    bindDomain.trans (callDomain.trans assignmentDomain)
  have finalInvariant :
      DigitRunState offsetCell finalState source start base (offset + 1) := by
    exact invariant.restoreAfter assignedInvariant completedDomain
  have finalDomain : CellDomainExtension state finalState := by
    simpa [finalState] using completedDomain.restoreLocals
  exact ⟨finalState, by simpa [digitRunLoopBody, finalState] using letExec,
    finalInvariant, finalDomain⟩

private def digitSeparatorBody : Stmt :=
  .letLocal 6 i32Type (.binary .add (.local 4) (i32Literal 1))
    (.sequence
      (.ifThenElse (.binary .greaterEqual (.local 6) (.local 1))
        (.returnValue (some (callFailedDigits (.local 6)))) .skip)
      (.sequence
        (.ifThenElse
          (.unary .logicalNot
            (callIsDigitForBase (.index (.local 0) (.local 6)) (.local 3)))
          (.returnValue (some (callFailedDigits (.local 6)))) .skip)
        (assignLocal 4 (.binary .add (.local 6) (i32Literal 1)))))

private def rejectedDigitBody : Stmt :=
  .ifThenElse (.binary .equal (.local 5) (i32Literal 95))
    digitSeparatorBody
    (.returnValue (some (callSuccessfulDigits (.local 4))))

private theorem evalLogicalNot_executes
    (operandResult : Evaluates program state operand (.boolean value) finalState) :
    Evaluates program state (.unary .logicalNot operand)
      (.boolean (!value)) finalState := by
  obtain ⟨fuel, operandResult⟩ := operandResult
  refine ⟨fuel + 1, ?_⟩
  rw [Lanius.Semantics.evalExpr.eq_def]
  simp only
  rw [operandResult]
  simp [evalUnaryValue]

private theorem DigitRunState.execRejectedDigitBodyFrom
    (invariant : DigitRunState offsetCell state source start base offset)
    (inBounds : offset < source.length)
    (rejected : isDigitForBase
      (source.get ⟨offset, inBounds⟩) base = false)
    (branchResult : Executes program
      (digitPredicateState
        (digitByteState state (source.get ⟨offset, inBounds⟩))
        (source.get ⟨offset, inBounds⟩) base)
      rejectedDigitBody completion completed) :
    Executes program state digitRunLoopBody completion
      (restoreLocals state completed) := by
  let byte := source.get ⟨offset, inBounds⟩
  let withByte := digitByteState state byte
  let afterPredicate := digitPredicateState withByte byte base
  have byteInvariant := invariant.afterByteBind byte
  have byteLocal := digitByteState_byteLocal invariant byte
  have initializer :
      Evaluates program state (.index (.local 0) (.local 4))
        (.signed .i32 byte.val) state := by
    exact ⟨10, by simpa [byte] using invariant.evalSourceByte inBounds⟩
  have predicateCall := byteInvariant.execPredicateFromByteLocal
    (program := program) byte byteLocal
  have rejectedByte : isDigitForBase byte base = false := by
    simpa [byte] using rejected
  rw [rejectedByte] at predicateCall
  have predicateCondition :
      Evaluates program withByte
        (callIsDigitForBase (.local 5) (.local 3))
        (.boolean false) afterPredicate := by
    simpa [afterPredicate, withByte] using predicateCall
  have predicateBranch := executesIfFalse
    (thenBranch := incrementLocal 4 1) predicateCondition (by
      simpa [afterPredicate, withByte, byte] using branchResult)
  have letExec := executesLetLocal (id := 5) (type := i32Type)
    initializer (by simpa [withByte, digitByteState] using predicateBranch)
  simpa [digitRunLoopBody, rejectedDigitBody, digitSeparatorBody] using letExec

theorem DigitRunState.execBoundaryDigitBody
    (invariant : DigitRunState offsetCell state source start base offset)
    (inBounds : offset < source.length)
    (rejected : isDigitForBase
      (source.get ⟨offset, inBounds⟩) base = false)
    (notSeparator : (source.get ⟨offset, inBounds⟩).val ≠ 95) :
    ∃ finalState,
      Executes program state digitRunLoopBody
        (.returned (some (digitScanValue (.success offset)))) finalState := by
  let byte := source.get ⟨offset, inBounds⟩
  let withByte := digitByteState state byte
  have byteInvariant := invariant.afterByteBind byte
  have byteLocal := digitByteState_byteLocal invariant byte
  let afterPredicate := digitPredicateState withByte byte base
  have predicateExtension : FrameExtension withByte afterPredicate := by
    simpa [afterPredicate, digitPredicateState] using
      twoI32CallState_extends withByte byte.val base
  have afterPredicateWellFormed : StateWellFormed afterPredicate := by
    simpa [afterPredicate, digitPredicateState] using
      twoI32CallState_well_formed withByte byteInvariant.wellFormed
        byte.val base
  have afterPredicateInvariant := byteInvariant.afterFrameExtension
    predicateExtension afterPredicateWellFormed
  have afterPredicateByteLocal :
      afterPredicate.local? 5 = some (.signed .i32 byte.val) :=
    predicateExtension.preserves_local byteInvariant.wellFormed byteLocal
  have separatorBase := evalI32LocalEqualNatLiteral (program := program)
    afterPredicate 5 byte.val 95 afterPredicateByteLocal
  have notSeparatorByte : byte.val ≠ 95 := by
    simpa [byte] using notSeparator
  have separatorBoolean : (byte.val == 95) = false :=
    by simp [notSeparatorByte]
  rw [separatorBoolean] at separatorBase
  have separatorCondition :
      Evaluates program afterPredicate
        (.binary .equal (.local 5) (i32Literal 95))
        (.boolean false) afterPredicate := ⟨4, separatorBase⟩
  have offsetResult : Evaluates program afterPredicate (.local 4)
      (.signed .i32 offset) afterPredicate :=
    ⟨1, evalLocal_of_local 0 program afterPredicate 4
      (.signed .i32 offset) afterPredicateInvariant.offsetLocal⟩
  let afterSuccess := singleArgumentCallState afterPredicate
    (.signed .i32 offset)
  have successCall :
      Evaluates program afterPredicate (callSuccessfulDigits (.local 4))
        (digitScanValue (.success offset)) afterSuccess := by
    simpa [afterSuccess] using DigitRunCallSemantics.successfulDigitsCall_executes
      afterPredicate afterPredicateWellFormed (.local 4) offset offsetResult
  have returned :
      Executes program afterPredicate
        (.returnValue (some (callSuccessfulDigits (.local 4))))
        (.returned (some (digitScanValue (.success offset)))) afterSuccess :=
    executesReturnValue successCall
  have branchResult : Executes program afterPredicate rejectedDigitBody
      (.returned (some (digitScanValue (.success offset)))) afterSuccess := by
    exact executesIfFalse separatorCondition returned
  exact ⟨restoreLocals state afterSuccess,
    invariant.execRejectedDigitBodyFrom inBounds rejected (by
      simpa [afterPredicate, withByte, byte] using branchResult)⟩

theorem DigitRunState.execSeparatorAtEndBody
    (invariant : DigitRunState offsetCell state source start base offset)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : offset < source.length)
    (separator : (source.get ⟨offset, inBounds⟩).val = 95)
    (requiredAtEnd : offset + 1 = source.length) :
    ∃ finalState,
      Executes program state digitRunLoopBody
        (.returned (some (digitScanValue (.failure (offset + 1)))))
        finalState := by
  let byte := source.get ⟨offset, inBounds⟩
  let withByte := digitByteState state byte
  have byteInvariant := invariant.afterByteBind byte
  have byteLocal := digitByteState_byteLocal invariant byte
  let afterPredicate := digitPredicateState withByte byte base
  have predicateExtension : FrameExtension withByte afterPredicate := by
    simpa [afterPredicate, digitPredicateState] using
      twoI32CallState_extends withByte byte.val base
  have afterPredicateWellFormed : StateWellFormed afterPredicate := by
    simpa [afterPredicate, digitPredicateState] using
      twoI32CallState_well_formed withByte byteInvariant.wellFormed
        byte.val base
  have afterPredicateInvariant := byteInvariant.afterFrameExtension
    predicateExtension afterPredicateWellFormed
  have afterPredicateByteLocal :
      afterPredicate.local? 5 = some (.signed .i32 byte.val) :=
    predicateExtension.preserves_local byteInvariant.wellFormed byteLocal
  have separatorBase := evalI32LocalEqualNatLiteral (program := program)
    afterPredicate 5 byte.val 95 afterPredicateByteLocal
  have separatorByte : byte.val = 95 := by simpa [byte] using separator
  have separatorCondition :
      Evaluates program afterPredicate
        (.binary .equal (.local 5) (i32Literal 95))
        (.boolean true) afterPredicate := by
    exact ⟨4, by simpa [separatorByte] using separatorBase⟩
  have requiredBound : offset + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound
  have requiredInitializer :
      Evaluates program afterPredicate
        (.binary .add (.local 4) (i32Literal 1))
        (.signed .i32 (offset + 1)) afterPredicate :=
    ⟨4, evalI32LocalAddOne (program := program) afterPredicate 4 offset
      afterPredicateInvariant.offsetLocal requiredBound
      DigitRunCallSemantics.target⟩
  let withRequired := afterPredicate.bindLocal 6
    (.signed .i32 (offset + 1))
  have requiredInvariant := afterPredicateInvariant.afterAuxBind 6
    (by decide) (.signed .i32 (offset + 1))
  have requiredLocal : withRequired.local? 6 =
      some (.signed .i32 (offset + 1)) := by
    simpa [withRequired] using bindLocal_finds_bound afterPredicate
      afterPredicateWellFormed 6 (.signed .i32 (offset + 1))
  have atEndBase := evalI32LocalGreaterEqualLocal (program := program)
    withRequired 6 1
    (offset + 1) source.length requiredLocal requiredInvariant.limitLocal
  have atEndCondition :
      Evaluates program withRequired
        (.binary .greaterEqual (.local 6) (.local 1))
        (.boolean true) withRequired := by
    exact ⟨4, by simpa [requiredAtEnd] using atEndBase⟩
  have argumentResult : Evaluates program withRequired (.local 6)
      (.signed .i32 (offset + 1)) withRequired :=
    ⟨1, evalLocal_of_local 0 program withRequired 6
      (.signed .i32 (offset + 1)) requiredLocal⟩
  let afterFailure := singleArgumentCallState withRequired
    (.signed .i32 (offset + 1))
  have failureCall :
      Evaluates program withRequired (callFailedDigits (.local 6))
        (digitScanValue (.failure (offset + 1))) afterFailure := by
    simpa [afterFailure] using DigitRunCallSemantics.failedDigitsCall_executes withRequired
      requiredInvariant.wellFormed (.local 6) (offset + 1) argumentResult
  have returned : Executes program withRequired
      (.returnValue (some (callFailedDigits (.local 6))))
      (.returned (some (digitScanValue (.failure (offset + 1)))))
      afterFailure := executesReturnValue failureCall
  have atEndBranch := executesIfTrue
    (elseBranch := .skip) atEndCondition returned
  have requiredSequence : Executes program withRequired
      (.sequence
        (.ifThenElse (.binary .greaterEqual (.local 6) (.local 1))
          (.returnValue (some (callFailedDigits (.local 6)))) .skip)
        (.sequence
          (.ifThenElse
            (.unary .logicalNot
              (callIsDigitForBase
                (.index (.local 0) (.local 6)) (.local 3)))
            (.returnValue (some (callFailedDigits (.local 6)))) .skip)
          (assignLocal 4 (.binary .add (.local 6) (i32Literal 1)))))
      (.returned (some (digitScanValue (.failure (offset + 1)))))
      afterFailure := executesSequenceReturned atEndBranch
  have separatorExec : Executes program afterPredicate digitSeparatorBody
      (.returned (some (digitScanValue (.failure (offset + 1)))))
      (restoreLocals afterPredicate afterFailure) := by
    simpa [digitSeparatorBody, withRequired] using
      executesLetLocal (id := 6) (type := i32Type)
        requiredInitializer requiredSequence
  have branchResult : Executes program afterPredicate rejectedDigitBody
      (.returned (some (digitScanValue (.failure (offset + 1)))))
      (restoreLocals afterPredicate afterFailure) := by
    exact executesIfTrue separatorCondition separatorExec
  have rejected : isDigitForBase
      (source.get ⟨offset, inBounds⟩) base = false := by
    have byteEq : source.get ⟨offset, inBounds⟩ = ⟨95, by omega⟩ :=
      Fin.ext separator
    rw [byteEq]
    exact isDigitForBase_underscore base
  exact ⟨restoreLocals state (restoreLocals afterPredicate afterFailure),
    invariant.execRejectedDigitBodyFrom inBounds rejected (by
      simpa [afterPredicate, withByte, byte] using branchResult)⟩

theorem DigitRunState.execSeparatorBeforeInvalidBody
    (invariant : DigitRunState offsetCell state source start base offset)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : offset < source.length)
    (separator : (source.get ⟨offset, inBounds⟩).val = 95)
    (nextInBounds : offset + 1 < source.length)
    (nextRejected : isDigitForBase
      (source.get ⟨offset + 1, nextInBounds⟩) base = false) :
    ∃ finalState,
      Executes program state digitRunLoopBody
        (.returned (some (digitScanValue (.failure (offset + 1)))))
        finalState := by
  let byte := source.get ⟨offset, inBounds⟩
  let withByte := digitByteState state byte
  have byteInvariant := invariant.afterByteBind byte
  have byteLocal := digitByteState_byteLocal invariant byte
  let afterPredicate := digitPredicateState withByte byte base
  have predicateExtension : FrameExtension withByte afterPredicate := by
    simpa [afterPredicate, digitPredicateState] using
      twoI32CallState_extends withByte byte.val base
  have afterPredicateWellFormed : StateWellFormed afterPredicate := by
    simpa [afterPredicate, digitPredicateState] using
      twoI32CallState_well_formed withByte byteInvariant.wellFormed
        byte.val base
  have afterPredicateInvariant := byteInvariant.afterFrameExtension
    predicateExtension afterPredicateWellFormed
  have afterPredicateByteLocal :
      afterPredicate.local? 5 = some (.signed .i32 byte.val) :=
    predicateExtension.preserves_local byteInvariant.wellFormed byteLocal
  have separatorBase := evalI32LocalEqualNatLiteral (program := program)
    afterPredicate 5 byte.val 95 afterPredicateByteLocal
  have separatorByte : byte.val = 95 := by simpa [byte] using separator
  have separatorCondition :
      Evaluates program afterPredicate
        (.binary .equal (.local 5) (i32Literal 95))
        (.boolean true) afterPredicate := by
    exact ⟨4, by simpa [separatorByte] using separatorBase⟩
  have requiredBound : offset + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound
  have requiredInitializer :
      Evaluates program afterPredicate
        (.binary .add (.local 4) (i32Literal 1))
        (.signed .i32 (offset + 1)) afterPredicate :=
    ⟨4, evalI32LocalAddOne (program := program) afterPredicate 4 offset
      afterPredicateInvariant.offsetLocal requiredBound
      DigitRunCallSemantics.target⟩
  let withRequired := afterPredicate.bindLocal 6
    (.signed .i32 (offset + 1))
  have requiredInvariant := afterPredicateInvariant.afterAuxBind 6
    (by decide) (.signed .i32 (offset + 1))
  have requiredLocal : withRequired.local? 6 =
      some (.signed .i32 (offset + 1)) := by
    simpa [withRequired] using bindLocal_finds_bound afterPredicate
      afterPredicateWellFormed 6 (.signed .i32 (offset + 1))
  have atEndBase := evalI32LocalGreaterEqualLocal (program := program)
    withRequired 6 1
    (offset + 1) source.length requiredLocal requiredInvariant.limitLocal
  have atEndCondition :
      Evaluates program withRequired
        (.binary .greaterEqual (.local 6) (.local 1))
        (.boolean false) withRequired := by
    exact ⟨4, by simpa [Nat.not_le.mpr nextInBounds] using atEndBase⟩
  have atEndBranch : Executes program withRequired
      (.ifThenElse (.binary .greaterEqual (.local 6) (.local 1))
        (.returnValue (some (callFailedDigits (.local 6)))) .skip)
      .next withRequired :=
    executesIfFalse atEndCondition (executesSkip program withRequired)
  let nextByte := source.get ⟨offset + 1, nextInBounds⟩
  have nextByteResult : Evaluates program withRequired
      (.index (.local 0) (.local 6)) (.signed .i32 nextByte.val)
      withRequired := by
    have nextBase := evalSourceIndexAt (program := program) withRequired
      source (offset + 1) 6 nextInBounds requiredInvariant.sourceLocal
      requiredLocal requiredInvariant.sourceCell
    exact ⟨10, by simpa [nextByte] using nextBase⟩
  have baseResult : Evaluates program withRequired (.local 3)
      (.signed .i32 base) withRequired :=
    ⟨1, evalLocal_of_local 0 program withRequired 3
      (.signed .i32 base) requiredInvariant.baseLocal⟩
  let afterNextPredicate := twoI32CallState withRequired nextByte.val base
  have nextPredicateCall := DigitRunCallSemantics.isDigitForBaseCall_executes withRequired
    requiredInvariant.wellFormed (.index (.local 0) (.local 6)) (.local 3)
    nextByte base nextByteResult baseResult
  have rejectedNextByte : isDigitForBase nextByte base = false := by
    simpa [nextByte] using nextRejected
  rw [rejectedNextByte] at nextPredicateCall
  have nextPredicateResult : Evaluates program withRequired
      (callIsDigitForBase (.index (.local 0) (.local 6)) (.local 3))
      (.boolean false) afterNextPredicate := by
    simpa [afterNextPredicate] using nextPredicateCall
  have invalidCondition : Evaluates program withRequired
      (.unary .logicalNot
        (callIsDigitForBase (.index (.local 0) (.local 6)) (.local 3)))
      (.boolean true) afterNextPredicate := by
    simpa using evalLogicalNot_executes nextPredicateResult
  have nextPredicateExtension : FrameExtension withRequired
      afterNextPredicate := by
    simpa [afterNextPredicate] using
      twoI32CallState_extends withRequired nextByte.val base
  have afterNextWellFormed : StateWellFormed afterNextPredicate := by
    simpa [afterNextPredicate] using twoI32CallState_well_formed
      withRequired requiredInvariant.wellFormed nextByte.val base
  have afterNextRequiredLocal : afterNextPredicate.local? 6 =
      some (.signed .i32 (offset + 1)) :=
    nextPredicateExtension.preserves_local requiredInvariant.wellFormed
      requiredLocal
  have argumentResult : Evaluates program afterNextPredicate (.local 6)
      (.signed .i32 (offset + 1)) afterNextPredicate :=
    ⟨1, evalLocal_of_local 0 program afterNextPredicate 6
      (.signed .i32 (offset + 1)) afterNextRequiredLocal⟩
  let afterFailure := singleArgumentCallState afterNextPredicate
    (.signed .i32 (offset + 1))
  have failureCall : Evaluates program afterNextPredicate
      (callFailedDigits (.local 6))
      (digitScanValue (.failure (offset + 1))) afterFailure := by
    simpa [afterFailure] using DigitRunCallSemantics.failedDigitsCall_executes afterNextPredicate
      afterNextWellFormed (.local 6) (offset + 1) argumentResult
  have returned : Executes program afterNextPredicate
      (.returnValue (some (callFailedDigits (.local 6))))
      (.returned (some (digitScanValue (.failure (offset + 1)))))
      afterFailure := executesReturnValue failureCall
  have invalidBranch := executesIfTrue
    (elseBranch := .skip) invalidCondition returned
  have remainingSequence : Executes program withRequired
      (.sequence
        (.ifThenElse
          (.unary .logicalNot
            (callIsDigitForBase (.index (.local 0) (.local 6)) (.local 3)))
          (.returnValue (some (callFailedDigits (.local 6)))) .skip)
        (assignLocal 4 (.binary .add (.local 6) (i32Literal 1))))
      (.returned (some (digitScanValue (.failure (offset + 1)))))
      afterFailure := executesSequenceReturned invalidBranch
  have requiredSequence : Executes program withRequired
      (.sequence
        (.ifThenElse (.binary .greaterEqual (.local 6) (.local 1))
          (.returnValue (some (callFailedDigits (.local 6)))) .skip)
        (.sequence
          (.ifThenElse
            (.unary .logicalNot
              (callIsDigitForBase (.index (.local 0) (.local 6)) (.local 3)))
            (.returnValue (some (callFailedDigits (.local 6)))) .skip)
          (assignLocal 4 (.binary .add (.local 6) (i32Literal 1)))))
      (.returned (some (digitScanValue (.failure (offset + 1)))))
      afterFailure := executesSequence atEndBranch remainingSequence
  have separatorExec : Executes program afterPredicate digitSeparatorBody
      (.returned (some (digitScanValue (.failure (offset + 1)))))
      (restoreLocals afterPredicate afterFailure) := by
    simpa [digitSeparatorBody, withRequired] using
      executesLetLocal (id := 6) (type := i32Type)
        requiredInitializer requiredSequence
  have branchResult : Executes program afterPredicate rejectedDigitBody
      (.returned (some (digitScanValue (.failure (offset + 1)))))
      (restoreLocals afterPredicate afterFailure) :=
    executesIfTrue separatorCondition separatorExec
  have rejected : isDigitForBase
      (source.get ⟨offset, inBounds⟩) base = false := by
    have byteEq : source.get ⟨offset, inBounds⟩ = ⟨95, by omega⟩ :=
      Fin.ext separator
    rw [byteEq]
    exact isDigitForBase_underscore base
  exact ⟨restoreLocals state (restoreLocals afterPredicate afterFailure),
    invariant.execRejectedDigitBodyFrom inBounds rejected (by
      simpa [afterPredicate, withByte, byte] using branchResult)⟩

theorem DigitRunState.execAcceptedSeparatorBody
    (invariant : DigitRunState offsetCell state source start base offset)
    (sourceBound : source.length ≤ 2147483647)
    (inBounds : offset < source.length)
    (separator : (source.get ⟨offset, inBounds⟩).val = 95)
    (nextInBounds : offset + 1 < source.length)
    (nextAccepted : isDigitForBase
      (source.get ⟨offset + 1, nextInBounds⟩) base = true) :
    ∃ finalState,
      Executes program state digitRunLoopBody .next finalState ∧
      DigitRunState offsetCell finalState source start base (offset + 2) ∧
      CellDomainExtension state finalState := by
  let byte := source.get ⟨offset, inBounds⟩
  let withByte := digitByteState state byte
  have byteInvariant := invariant.afterByteBind byte
  have byteLocal := digitByteState_byteLocal invariant byte
  let afterPredicate := digitPredicateState withByte byte base
  have predicateExtension : FrameExtension withByte afterPredicate := by
    simpa [afterPredicate, digitPredicateState] using
      twoI32CallState_extends withByte byte.val base
  have afterPredicateWellFormed : StateWellFormed afterPredicate := by
    simpa [afterPredicate, digitPredicateState] using
      twoI32CallState_well_formed withByte byteInvariant.wellFormed
        byte.val base
  have afterPredicateInvariant := byteInvariant.afterFrameExtension
    predicateExtension afterPredicateWellFormed
  have afterPredicateByteLocal :
      afterPredicate.local? 5 = some (.signed .i32 byte.val) :=
    predicateExtension.preserves_local byteInvariant.wellFormed byteLocal
  have separatorBase := evalI32LocalEqualNatLiteral (program := program)
    afterPredicate 5 byte.val 95 afterPredicateByteLocal
  have separatorByte : byte.val = 95 := by simpa [byte] using separator
  have separatorCondition :
      Evaluates program afterPredicate
        (.binary .equal (.local 5) (i32Literal 95))
        (.boolean true) afterPredicate := by
    exact ⟨4, by simpa [separatorByte] using separatorBase⟩
  have requiredBound : offset + 1 ≤ 2147483647 :=
    Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound
  have requiredInitializer :
      Evaluates program afterPredicate
        (.binary .add (.local 4) (i32Literal 1))
        (.signed .i32 (offset + 1)) afterPredicate :=
    ⟨4, evalI32LocalAddOne (program := program) afterPredicate 4 offset
      afterPredicateInvariant.offsetLocal requiredBound
      DigitRunCallSemantics.target⟩
  let withRequired := afterPredicate.bindLocal 6
    (.signed .i32 (offset + 1))
  have requiredInvariant := afterPredicateInvariant.afterAuxBind 6
    (by decide) (.signed .i32 (offset + 1))
  have requiredLocal : withRequired.local? 6 =
      some (.signed .i32 (offset + 1)) := by
    simpa [withRequired] using bindLocal_finds_bound afterPredicate
      afterPredicateWellFormed 6 (.signed .i32 (offset + 1))
  have atEndBase := evalI32LocalGreaterEqualLocal (program := program)
    withRequired 6 1
    (offset + 1) source.length requiredLocal requiredInvariant.limitLocal
  have atEndCondition :
      Evaluates program withRequired
        (.binary .greaterEqual (.local 6) (.local 1))
        (.boolean false) withRequired := by
    exact ⟨4, by simpa [Nat.not_le.mpr nextInBounds] using atEndBase⟩
  have atEndBranch : Executes program withRequired
      (.ifThenElse (.binary .greaterEqual (.local 6) (.local 1))
        (.returnValue (some (callFailedDigits (.local 6)))) .skip)
      .next withRequired :=
    executesIfFalse atEndCondition (executesSkip program withRequired)
  let nextByte := source.get ⟨offset + 1, nextInBounds⟩
  have nextByteResult : Evaluates program withRequired
      (.index (.local 0) (.local 6)) (.signed .i32 nextByte.val)
      withRequired := by
    have nextBase := evalSourceIndexAt (program := program)
      withRequired source (offset + 1) 6
      nextInBounds requiredInvariant.sourceLocal requiredLocal
      requiredInvariant.sourceCell
    exact ⟨10, by simpa [nextByte] using nextBase⟩
  have baseResult : Evaluates program withRequired (.local 3)
      (.signed .i32 base) withRequired :=
    ⟨1, evalLocal_of_local 0 program withRequired 3
      (.signed .i32 base) requiredInvariant.baseLocal⟩
  let afterNextPredicate := twoI32CallState withRequired nextByte.val base
  have nextPredicateCall := DigitRunCallSemantics.isDigitForBaseCall_executes withRequired
    requiredInvariant.wellFormed (.index (.local 0) (.local 6)) (.local 3)
    nextByte base nextByteResult baseResult
  have acceptedNextByte : isDigitForBase nextByte base = true := by
    simpa [nextByte] using nextAccepted
  rw [acceptedNextByte] at nextPredicateCall
  have nextPredicateResult : Evaluates program withRequired
      (callIsDigitForBase (.index (.local 0) (.local 6)) (.local 3))
      (.boolean true) afterNextPredicate := by
    simpa [afterNextPredicate] using nextPredicateCall
  have validCondition : Evaluates program withRequired
      (.unary .logicalNot
        (callIsDigitForBase (.index (.local 0) (.local 6)) (.local 3)))
      (.boolean false) afterNextPredicate := by
    simpa using evalLogicalNot_executes nextPredicateResult
  have nextPredicateExtension : FrameExtension withRequired
      afterNextPredicate := by
    simpa [afterNextPredicate] using
      twoI32CallState_extends withRequired nextByte.val base
  have afterNextWellFormed : StateWellFormed afterNextPredicate := by
    simpa [afterNextPredicate] using twoI32CallState_well_formed
      withRequired requiredInvariant.wellFormed nextByte.val base
  have afterNextInvariant := requiredInvariant.afterFrameExtension
    nextPredicateExtension afterNextWellFormed
  have afterNextRequiredLocal : afterNextPredicate.local? 6 =
      some (.signed .i32 (offset + 1)) :=
    nextPredicateExtension.preserves_local requiredInvariant.wellFormed
      requiredLocal
  have invalidBranch : Executes program withRequired
      (.ifThenElse
        (.unary .logicalNot
          (callIsDigitForBase (.index (.local 0) (.local 6)) (.local 3)))
        (.returnValue (some (callFailedDigits (.local 6)))) .skip)
      .next afterNextPredicate :=
    executesIfFalse validCondition (executesSkip program afterNextPredicate)
  have nextOffsetBound : offset + 2 ≤ 2147483647 :=
    Nat.le_trans (Nat.succ_le_of_lt nextInBounds) sourceBound
  have assignmentValue : evalExpr 9 program afterNextPredicate
      (.binary .add (.local 6) (i32Literal 1)) =
      .done (.signed .i32 (offset + 2)) afterNextPredicate := by
    have baseValue := evalI32LocalAddOne (program := program)
      afterNextPredicate 6 (offset + 1)
      afterNextRequiredLocal nextOffsetBound DigitRunCallSemantics.target
    have coerced : ((offset + 1 : Nat) : Int) + 1 =
        (offset : Int) + 2 := by omega
    rw [coerced] at baseValue
    exact evalExpr_done_at_larger_fuel
      (program := program) (by decide : 4 ≤ 9) baseValue
  let assigned := updatedDigitOffsetState afterNextPredicate offsetCell
    (offset + 2)
  have assignmentExec : Executes program afterNextPredicate
      (assignLocal 4 (.binary .add (.local 6) (i32Literal 1)))
      .next assigned := by
    have setBase := afterNextInvariant.execOffsetSet
      (.binary .add (.local 6) (i32Literal 1)) (offset + 2)
      assignmentValue
    exact ⟨11, by simpa [assignLocal, assigned] using setBase⟩
  have assignedInvariant :
      DigitRunState offsetCell assigned source start base (offset + 2) :=
    afterNextInvariant.afterOffsetAssignment (offset + 2)
      (Nat.succ_le_of_lt nextInBounds)
  have remainingSequence : Executes program withRequired
      (.sequence
        (.ifThenElse
          (.unary .logicalNot
            (callIsDigitForBase (.index (.local 0) (.local 6)) (.local 3)))
          (.returnValue (some (callFailedDigits (.local 6)))) .skip)
        (assignLocal 4 (.binary .add (.local 6) (i32Literal 1))))
      .next assigned := executesSequence invalidBranch assignmentExec
  have requiredSequence : Executes program withRequired
      (.sequence
        (.ifThenElse (.binary .greaterEqual (.local 6) (.local 1))
          (.returnValue (some (callFailedDigits (.local 6)))) .skip)
        (.sequence
          (.ifThenElse
            (.unary .logicalNot
              (callIsDigitForBase (.index (.local 0) (.local 6)) (.local 3)))
            (.returnValue (some (callFailedDigits (.local 6)))) .skip)
          (assignLocal 4 (.binary .add (.local 6) (i32Literal 1)))))
      .next assigned := executesSequence atEndBranch remainingSequence
  let afterSeparator := restoreLocals afterPredicate assigned
  have separatorExec : Executes program afterPredicate digitSeparatorBody
      .next afterSeparator := by
    simpa [digitSeparatorBody, withRequired, afterSeparator] using
      executesLetLocal (id := 6) (type := i32Type)
        requiredInitializer requiredSequence
  have branchResult : Executes program afterPredicate rejectedDigitBody
      .next afterSeparator := executesIfTrue separatorCondition separatorExec
  have rejected : isDigitForBase
      (source.get ⟨offset, inBounds⟩) base = false := by
    have byteEq : source.get ⟨offset, inBounds⟩ = ⟨95, by omega⟩ :=
      Fin.ext separator
    rw [byteEq]
    exact isDigitForBase_underscore base
  let finalState := restoreLocals state afterSeparator
  have bodyExec : Executes program state digitRunLoopBody .next
      finalState := by
    simpa [finalState, afterSeparator, afterPredicate, withByte, byte] using
      invariant.execRejectedDigitBodyFrom inBounds rejected (by
        simpa [afterSeparator, afterPredicate, withByte, byte] using
          branchResult)
  have byteDomain : CellDomainExtension state withByte := by
    simpa [withByte, digitByteState] using
      bindLocal_domain_extends state 5 (.signed .i32 byte.val)
  have predicateDomain : CellDomainExtension withByte afterPredicate :=
    predicateExtension.domainExtension byteInvariant.wellFormed
  have requiredDomain : CellDomainExtension afterPredicate withRequired := by
    simpa [withRequired] using bindLocal_domain_extends afterPredicate 6
      (.signed .i32 (offset + 1))
  have nextPredicateDomain : CellDomainExtension withRequired
      afterNextPredicate :=
    nextPredicateExtension.domainExtension requiredInvariant.wellFormed
  have assignmentDomain : CellDomainExtension afterNextPredicate assigned :=
    assignCell_domain_extends
      (afterNextInvariant.assignOffset (offset + 2))
  have separatorCompletedDomain : CellDomainExtension afterPredicate assigned :=
    requiredDomain.trans (nextPredicateDomain.trans assignmentDomain)
  have afterSeparatorInvariant :
      DigitRunState offsetCell afterSeparator source start base (offset + 2) := by
    exact afterPredicateInvariant.restoreAfter assignedInvariant
      separatorCompletedDomain
  have afterSeparatorDomain : CellDomainExtension afterPredicate
      afterSeparator := by
    simpa [afterSeparator] using separatorCompletedDomain.restoreLocals
  have completedDomain : CellDomainExtension state afterSeparator :=
    byteDomain.trans (predicateDomain.trans afterSeparatorDomain)
  have finalInvariant :
      DigitRunState offsetCell finalState source start base (offset + 2) := by
    exact invariant.restoreAfter afterSeparatorInvariant completedDomain
  have finalDomain : CellDomainExtension state finalState := by
    simpa [finalState] using completedDomain.restoreLocals
  exact ⟨finalState, bodyExec, finalInvariant, finalDomain⟩

theorem executesDigitRunWhile
    (invariant : DigitRunState offsetCell state source start base offset)
    (sourceBound : source.length ≤ 2147483647) :
    (∃ finalState,
      scanDigitTail base (source.drop offset) offset =
        .success source.length ∧
      Executes program state
        (.whileLoop (.binary .less (.local 4) (.local 1))
          digitRunLoopBody) .next finalState ∧
      DigitRunState offsetCell finalState source start base source.length ∧
      CellDomainExtension state finalState) ∨
    (∃ finalState,
      Executes program state
        (.whileLoop (.binary .less (.local 4) (.local 1))
          digitRunLoopBody)
        (.returned (some
          (digitScanValue (scanDigitTail base (source.drop offset) offset))))
        finalState) := by
  by_cases inBounds : offset < source.length
  · have conditionResult : Evaluates program state
        (.binary .less (.local 4) (.local 1)) (.boolean true) state :=
      ⟨13, by simpa [inBounds] using invariant.evalLoopCondition⟩
    let byte := source.get ⟨offset, inBounds⟩
    have dropped := List.drop_eq_getElem_cons inBounds
    have droppedByte : source.drop offset =
        byte :: source.drop (offset + 1) := by
      simpa [byte] using dropped
    by_cases accepted : isDigitForBase byte base = true
    · obtain ⟨next, bodyExec, nextInvariant, bodyDomain⟩ :=
        invariant.execAcceptedDigitBody (program := program)
          sourceBound inBounds (by
          simpa [byte] using accepted)
      have acceptedSource : isDigitForBase
          (source.get ⟨offset, inBounds⟩) base = true := by
        simpa [byte] using accepted
      have stepResult :
          scanDigitTail base (source.drop offset) offset =
            scanDigitTail base (source.drop (offset + 1)) (offset + 1) := by
        rw [droppedByte, scanDigitTail.eq_def]
        simp [accepted]
      rcases executesDigitRunWhile nextInvariant sourceBound with
        ⟨finalState, resultEq, restExec, finalInvariant, restDomain⟩ |
        ⟨finalState, restExec⟩
      · left
        exact ⟨finalState, stepResult.trans resultEq,
          executesWhileTrueThen conditionResult bodyExec restExec,
          finalInvariant, bodyDomain.trans restDomain⟩
      · right
        refine ⟨finalState, ?_⟩
        rw [stepResult]
        exact executesWhileTrueThen conditionResult bodyExec restExec
    · have rejected : isDigitForBase byte base = false := by
        cases value : isDigitForBase byte base with
        | false => rfl
        | true => exact False.elim (accepted value)
      have rejectedSource : isDigitForBase
          (source.get ⟨offset, inBounds⟩) base = false := by
        simpa [byte] using rejected
      by_cases separator : byte.val = 95
      · by_cases nextInBounds : offset + 1 < source.length
        · let nextByte := source.get ⟨offset + 1, nextInBounds⟩
          have nextDropped := List.drop_eq_getElem_cons nextInBounds
          have twoStep : offset + 1 + 1 = offset + 2 := by omega
          rw [twoStep] at nextDropped
          have nextDroppedByte : source.drop (offset + 1) =
              nextByte :: source.drop (offset + 2) := by
            simpa [nextByte] using nextDropped
          have separatorSource :
              (source.get ⟨offset, inBounds⟩).val = 95 := by
            simpa [byte] using separator
          by_cases nextAccepted : isDigitForBase nextByte base = true
          · obtain ⟨next, bodyExec, nextInvariant, bodyDomain⟩ :=
              invariant.execAcceptedSeparatorBody (program := program)
                sourceBound inBounds
                (by simpa [byte] using separator) nextInBounds
                (by simpa [nextByte] using nextAccepted)
            have nextAcceptedSource : isDigitForBase
                (source.get ⟨offset + 1, nextInBounds⟩) base = true := by
              simpa [nextByte] using nextAccepted
            have stepResult :
                scanDigitTail base (source.drop offset) offset =
                  scanDigitTail base (source.drop (offset + 2))
                    (offset + 2) := by
              rw [droppedByte, nextDroppedByte, scanDigitTail.eq_def]
              simp [rejected, separator, nextAccepted]
            rcases executesDigitRunWhile nextInvariant sourceBound with
              ⟨finalState, resultEq, restExec, finalInvariant, restDomain⟩ |
              ⟨finalState, restExec⟩
            · left
              exact ⟨finalState, stepResult.trans resultEq,
                executesWhileTrueThen conditionResult bodyExec restExec,
                finalInvariant, bodyDomain.trans restDomain⟩
            · right
              refine ⟨finalState, ?_⟩
              rw [stepResult]
              exact executesWhileTrueThen conditionResult bodyExec restExec
          · have nextRejected : isDigitForBase nextByte base = false := by
              cases value : isDigitForBase nextByte base with
              | false => rfl
              | true => exact False.elim (nextAccepted value)
            obtain ⟨finalState, bodyExec⟩ :=
              invariant.execSeparatorBeforeInvalidBody (program := program)
                sourceBound inBounds
                (by simpa [byte] using separator) nextInBounds
                (by simpa [nextByte] using nextRejected)
            have nextRejectedSource : isDigitForBase
                (source.get ⟨offset + 1, nextInBounds⟩) base = false := by
              simpa [nextByte] using nextRejected
            have resultEq :
                scanDigitTail base (source.drop offset) offset =
                  .failure (offset + 1) := by
              rw [droppedByte, nextDroppedByte, scanDigitTail.eq_def]
              simp [rejected, separator, nextRejected]
            right
            refine ⟨finalState, ?_⟩
            rw [resultEq]
            exact executesWhileReturned conditionResult bodyExec
        · have requiredAtEnd : offset + 1 = source.length := by omega
          have droppedNext : source.drop (offset + 1) = [] :=
            List.drop_eq_nil_of_le (Nat.le_of_not_gt nextInBounds)
          obtain ⟨finalState, bodyExec⟩ :=
            invariant.execSeparatorAtEndBody (program := program)
              sourceBound inBounds
              (by simpa [byte] using separator) requiredAtEnd
          have separatorSource :
              (source.get ⟨offset, inBounds⟩).val = 95 := by
            simpa [byte] using separator
          have resultEq :
              scanDigitTail base (source.drop offset) offset =
                .failure (offset + 1) := by
            rw [droppedByte, droppedNext, scanDigitTail.eq_def]
            simp [rejected, separator]
          right
          refine ⟨finalState, ?_⟩
          rw [resultEq]
          exact executesWhileReturned conditionResult bodyExec
      · obtain ⟨finalState, bodyExec⟩ :=
          invariant.execBoundaryDigitBody (program := program) inBounds (by
            simpa [byte] using rejected) (by simpa [byte] using separator)
        have notSeparatorSource :
            (source.get ⟨offset, inBounds⟩).val ≠ 95 := by
          simpa [byte] using separator
        have resultEq : scanDigitTail base (source.drop offset) offset =
            .success offset := by
          rw [droppedByte, scanDigitTail.eq_def]
          simp [rejected, separator]
        right
        refine ⟨finalState, ?_⟩
        rw [resultEq]
        exact executesWhileReturned conditionResult bodyExec
  · have atEnd : offset = source.length :=
      Nat.le_antisymm invariant.offsetBound (Nat.le_of_not_gt inBounds)
    have conditionResult : Evaluates program state
        (.binary .less (.local 4) (.local 1)) (.boolean false) state :=
      ⟨13, by simpa [inBounds] using invariant.evalLoopCondition⟩
    left
    refine ⟨state, ?_, executesWhileFalse conditionResult, ?_,
      CellDomainExtension.refl state⟩
    · simp [atEnd, scanDigitTail]
    · simpa [atEnd] using invariant
termination_by source.length - offset
decreasing_by all_goals omega

theorem executesDigitRunLoopAndFallback
    (invariant : DigitRunState offsetCell state source start base offset)
    (sourceBound : source.length ≤ 2147483647) :
    ∃ finalState,
      Executes program state
        (.sequence
          (.whileLoop (.binary .less (.local 4) (.local 1))
            digitRunLoopBody)
          (.returnValue (some (callSuccessfulDigits (.local 4)))))
        (.returned (some
          (digitScanValue (scanDigitTail base (source.drop offset) offset))))
        finalState := by
  rcases executesDigitRunWhile (program := program)
    invariant sourceBound with
    ⟨afterLoop, resultEq, loopExec, finalInvariant, _⟩ |
    ⟨finalState, loopExec⟩
  · have argumentResult : Evaluates program afterLoop (.local 4)
        (.signed .i32 source.length) afterLoop :=
      ⟨1, evalLocal_of_local 0 program afterLoop 4
        (.signed .i32 source.length) finalInvariant.offsetLocal⟩
    let afterSuccess := singleArgumentCallState afterLoop
      (.signed .i32 source.length)
    have successCall : Evaluates program afterLoop
        (callSuccessfulDigits (.local 4))
        (digitScanValue (.success source.length)) afterSuccess := by
      simpa [afterSuccess] using DigitRunCallSemantics.successfulDigitsCall_executes afterLoop
        finalInvariant.wellFormed (.local 4) source.length argumentResult
    have returnExec : Executes program afterLoop
        (.returnValue (some (callSuccessfulDigits (.local 4))))
        (.returned (some (digitScanValue (.success source.length))))
        afterSuccess := executesReturnValue successCall
    refine ⟨afterSuccess, ?_⟩
    rw [resultEq]
    exact executesSequence loopExec returnExec
  · exact ⟨finalState, executesSequenceReturned loopExec⟩

theorem scanDigitRunBody_executes
    (source : List Byte) (start base : Nat)
    (sourceBound : source.length ≤ 2147483647) :
    ∃ finalState,
      Executes program (digitParameterState source start base)
        scanDigitRunBody
        (.returned (some (digitScanValue (scanDigitRun source start base))))
        finalState := by
  let parameters := digitParameterState source start base
  have parametersWellFormed := digitParameterState_well_formed source start base
  have startConditionBase := evalI32LocalGreaterEqualLocal
    (program := program) parameters 2 1
    start source.length (digitParameterState_startLocal source start base)
    (digitParameterState_limitLocal source start base)
  by_cases inBounds : start < source.length
  · have startCondition : Evaluates program parameters
        (.binary .greaterEqual (.local 2) (.local 1))
        (.boolean false) parameters := by
      exact ⟨4, by simpa [Nat.not_le.mpr inBounds] using startConditionBase⟩
    have startBranch : Executes program parameters
        (.ifThenElse (.binary .greaterEqual (.local 2) (.local 1))
          (.returnValue (some (callFailedDigits (.local 2)))) .skip)
        .next parameters :=
      executesIfFalse startCondition (executesSkip program parameters)
    let first := source.get ⟨start, inBounds⟩
    have firstResult : Evaluates program parameters
        (.index (.local 0) (.local 2)) (.signed .i32 first.val)
        parameters := by
      have indexed := evalSourceIndexAt (program := program)
        parameters source start 2 inBounds
        (digitParameterState_sourceLocal source start base)
        (digitParameterState_startLocal source start base)
        (digitParameterState_sourceCell source start base)
      exact ⟨10, by simpa [parameters, first] using indexed⟩
    have baseResult : Evaluates program parameters (.local 3)
        (.signed .i32 base) parameters :=
      ⟨1, evalLocal_of_local 0 program parameters 3
        (.signed .i32 base)
        (digitParameterState_baseLocal source start base)⟩
    let afterPredicate := twoI32CallState parameters first.val base
    have predicateCall := DigitRunCallSemantics.isDigitForBaseCall_executes parameters
      parametersWellFormed (.index (.local 0) (.local 2)) (.local 3)
      first base firstResult baseResult
    have predicateExtension : FrameExtension parameters afterPredicate := by
      simpa [afterPredicate] using
        twoI32CallState_extends parameters first.val base
    have afterPredicateWellFormed : StateWellFormed afterPredicate := by
      simpa [afterPredicate] using twoI32CallState_well_formed parameters
        parametersWellFormed first.val base
    by_cases accepted : isDigitForBase first base = true
    · rw [accepted] at predicateCall
      have predicateResult : Evaluates program parameters
          (callIsDigitForBase (.index (.local 0) (.local 2)) (.local 3))
          (.boolean true) afterPredicate := by
        simpa [afterPredicate] using predicateCall
      have validCondition : Evaluates program parameters
          (.unary .logicalNot
            (callIsDigitForBase (.index (.local 0) (.local 2)) (.local 3)))
          (.boolean false) afterPredicate := by
        simpa using evalLogicalNot_executes predicateResult
      have validBranch : Executes program parameters
          (.ifThenElse
            (.unary .logicalNot
              (callIsDigitForBase
                (.index (.local 0) (.local 2)) (.local 3)))
            (.returnValue (some (callFailedDigits (.local 2)))) .skip)
          .next afterPredicate :=
        executesIfFalse validCondition
          (executesSkip program afterPredicate)
      have afterStartLocal : afterPredicate.local? 2 =
          some (.signed .i32 start) :=
        predicateExtension.preserves_local parametersWellFormed
          (digitParameterState_startLocal source start base)
      have initializerBound : start + 1 ≤ 2147483647 :=
        Nat.le_trans (Nat.succ_le_of_lt inBounds) sourceBound
      have offsetInitializer : Evaluates program afterPredicate
          (.binary .add (.local 2) (i32Literal 1))
          (.signed .i32 (start + 1)) afterPredicate :=
        ⟨4, evalI32LocalAddOne (program := program)
          afterPredicate 2 start afterStartLocal
          initializerBound DigitRunCallSemantics.target⟩
      let initial := afterPredicate.bindLocal 4
        (.signed .i32 (start + 1))
      have initialInvariant := digitInitialState_after_frame_invariant
        source start base afterPredicate predicateExtension
        afterPredicateWellFormed inBounds
      obtain ⟨loopFinal, loopExec⟩ := executesDigitRunLoopAndFallback
        (program := program) initialInvariant sourceBound
      have offsetLetExec : Executes program afterPredicate
          (.letLocal 4 i32Type
            (.binary .add (.local 2) (i32Literal 1))
            (.sequence
              (.whileLoop (.binary .less (.local 4) (.local 1))
                digitRunLoopBody)
              (.returnValue (some (callSuccessfulDigits (.local 4))))))
          (.returned (some (digitScanValue
            (scanDigitTail base (source.drop (start + 1)) (start + 1)))))
          (restoreLocals afterPredicate loopFinal) := by
        simpa [initial] using executesLetLocal
          (id := 4) (type := i32Type) offsetInitializer loopExec
      have secondSequence := executesSequence validBranch offsetLetExec
      have bodyExec := executesSequence startBranch secondSequence
      have dropped := List.drop_eq_getElem_cons inBounds
      have droppedFirst : source.drop start =
          first :: source.drop (start + 1) := by
        simpa [first] using dropped
      have resultEq : scanDigitRun source start base =
          scanDigitTail base (source.drop (start + 1)) (start + 1) := by
        simp [scanDigitRun, droppedFirst, accepted]
      refine ⟨restoreLocals afterPredicate loopFinal, ?_⟩
      rw [resultEq]
      simpa [scanDigitRunBody, parameters] using bodyExec
    · have rejected : isDigitForBase first base = false := by
        cases value : isDigitForBase first base with
        | false => rfl
        | true => exact False.elim (accepted value)
      rw [rejected] at predicateCall
      have predicateResult : Evaluates program parameters
          (callIsDigitForBase (.index (.local 0) (.local 2)) (.local 3))
          (.boolean false) afterPredicate := by
        simpa [afterPredicate] using predicateCall
      have invalidCondition : Evaluates program parameters
          (.unary .logicalNot
            (callIsDigitForBase (.index (.local 0) (.local 2)) (.local 3)))
          (.boolean true) afterPredicate := by
        simpa using evalLogicalNot_executes predicateResult
      have afterStartLocal : afterPredicate.local? 2 =
          some (.signed .i32 start) :=
        predicateExtension.preserves_local parametersWellFormed
          (digitParameterState_startLocal source start base)
      have argumentResult : Evaluates program afterPredicate (.local 2)
          (.signed .i32 start) afterPredicate :=
        ⟨1, evalLocal_of_local 0 program afterPredicate 2
          (.signed .i32 start) afterStartLocal⟩
      let afterFailure := singleArgumentCallState afterPredicate
        (.signed .i32 start)
      have failureCall : Evaluates program afterPredicate
          (callFailedDigits (.local 2))
          (digitScanValue (.failure start)) afterFailure := by
        simpa [afterFailure] using DigitRunCallSemantics.failedDigitsCall_executes afterPredicate
          afterPredicateWellFormed (.local 2) start argumentResult
      have returned : Executes program afterPredicate
          (.returnValue (some (callFailedDigits (.local 2))))
          (.returned (some (digitScanValue (.failure start))))
          afterFailure := executesReturnValue failureCall
      have invalidBranch := executesIfTrue
        (elseBranch := .skip) invalidCondition returned
      have secondSequence : Executes program parameters
          (.sequence
            (.ifThenElse
              (.unary .logicalNot
                (callIsDigitForBase
                  (.index (.local 0) (.local 2)) (.local 3)))
              (.returnValue (some (callFailedDigits (.local 2)))) .skip)
            (.letLocal 4 i32Type
              (.binary .add (.local 2) (i32Literal 1))
              (.sequence
                (.whileLoop (.binary .less (.local 4) (.local 1))
                  digitRunLoopBody)
                (.returnValue (some (callSuccessfulDigits (.local 4)))))))
          (.returned (some (digitScanValue (.failure start)))) afterFailure :=
        executesSequenceReturned invalidBranch
      have bodyExec := executesSequence startBranch secondSequence
      have dropped := List.drop_eq_getElem_cons inBounds
      have droppedFirst : source.drop start =
          first :: source.drop (start + 1) := by
        simpa [first] using dropped
      have resultEq : scanDigitRun source start base = .failure start := by
        simp [scanDigitRun, droppedFirst, rejected]
      refine ⟨afterFailure, ?_⟩
      rw [resultEq]
      simpa [scanDigitRunBody, parameters] using bodyExec
  · have startAtOrAfter : source.length ≤ start := Nat.le_of_not_gt inBounds
    have startCondition : Evaluates program parameters
        (.binary .greaterEqual (.local 2) (.local 1))
        (.boolean true) parameters := by
      exact ⟨4, by simpa [startAtOrAfter] using startConditionBase⟩
    have argumentResult : Evaluates program parameters (.local 2)
        (.signed .i32 start) parameters :=
      ⟨1, evalLocal_of_local 0 program parameters 2
        (.signed .i32 start)
        (digitParameterState_startLocal source start base)⟩
    let afterFailure := singleArgumentCallState parameters (.signed .i32 start)
    have failureCall : Evaluates program parameters
        (callFailedDigits (.local 2))
        (digitScanValue (.failure start)) afterFailure := by
      simpa [afterFailure] using DigitRunCallSemantics.failedDigitsCall_executes parameters
        parametersWellFormed (.local 2) start argumentResult
    have returned : Executes program parameters
        (.returnValue (some (callFailedDigits (.local 2))))
        (.returned (some (digitScanValue (.failure start)))) afterFailure :=
      executesReturnValue failureCall
    have startBranch := executesIfTrue
      (elseBranch := .skip) startCondition returned
    have bodyExec : Executes program parameters scanDigitRunBody
        (.returned (some (digitScanValue (.failure start)))) afterFailure := by
      simpa [scanDigitRunBody] using executesSequenceReturned startBranch
    have droppedEmpty : source.drop start = [] :=
      List.drop_eq_nil_of_le startAtOrAfter
    have resultEq : scanDigitRun source start base = .failure start := by
      simp [scanDigitRun, droppedEmpty]
    refine ⟨afterFailure, ?_⟩
    rw [resultEq]
    simpa [parameters] using bodyExec

end GenericDigitRunExecution

def scanDigitRunCall (source : List Byte) (start base : Nat) : Expr :=
  .call scanDigitRunFunction.id
    [sourceSlice source, i32Literal source.length, i32Literal start,
      i32Literal base]

theorem lexerProgram_finds_scanDigitRunFunction :
    lexerProgram.function? scanDigitRunFunction.id =
      some scanDigitRunFunction := by rfl

/-- The actual represented four-argument Lanius function executes to the
abstract numeric-run result. This theorem crosses argument evaluation,
parameter binding, the complete body, and caller-frame restoration. -/
theorem scanDigitRunFunction_executes
    (source : List Byte) (start base : Nat)
    (sourceBound : source.length ≤ 2147483647) :
    ∃ finalState,
      Evaluates lexerProgram (sourceState source)
        (scanDigitRunCall source start base)
        (digitScanValue (scanDigitRun source start base)) finalState := by
  obtain ⟨bodyFinal, bodyExec⟩ :=
    scanDigitRunBody_executes (program := lexerProgram)
      source start base sourceBound
  obtain ⟨bodyFuel, bodyResult⟩ := bodyExec
  have argumentsBase :
      evalExprs 5 lexerProgram (sourceState source)
        [sourceSlice source, i32Literal source.length, i32Literal start,
          i32Literal base] =
        .done
          [.slice i32Type 0 [] 0 source.length,
            .signed .i32 source.length, .signed .i32 start,
            .signed .i32 base]
          (sourceState source) := by rfl
  let fuel := max 5 bodyFuel
  have argumentsAtFuel := evalExprs_done_at_larger_fuel
    (Nat.le_max_left 5 bodyFuel) argumentsBase
  have bodyAtFuel := execStmt_done_at_larger_fuel
    (Nat.le_max_right 5 bodyFuel) bodyResult
  have boundParameters :
      bindParameters scanDigitRunFunction.parameters
        [.slice i32Type 0 [] 0 source.length,
          .signed .i32 source.length, .signed .i32 start,
          .signed .i32 base] =
        some
          [(0, .slice i32Type 0 [] 0 source.length),
            (1, .signed .i32 source.length), (2, .signed .i32 start),
            (3, .signed .i32 base)] := by rfl
  have callee :
      ({ sourceState source with locals := [] }).bindLocals
        [(0, .slice i32Type 0 [] 0 source.length),
          (1, .signed .i32 source.length), (2, .signed .i32 start),
          (3, .signed .i32 base)] =
        digitParameterState source start base := by rfl
  let finalState := restoreLocals (sourceState source) bodyFinal
  refine ⟨finalState, fuel + 1, ?_⟩
  unfold scanDigitRunCall
  rw [evalExpr, argumentsAtFuel]
  simp only
  rw [lexerProgram_finds_scanDigitRunFunction]
  simp only
  rw [boundParameters]
  simp only [scanDigitRunFunction]
  rw [callee, bodyAtFuel]

/-- Relational refinement form: any result admitted by the independent
`DigitRunScan` specification is produced by the represented Lanius function. -/
theorem scanDigitRunFunction_executes_spec
    (source : List Byte) (start base : Nat) (result : DigitScanResult)
    (sourceBound : source.length ≤ 2147483647)
    (scan : DigitRunScan source start base result) :
    ∃ finalState,
      Evaluates lexerProgram (sourceState source)
        (scanDigitRunCall source start base) (digitScanValue result)
        finalState := by
  obtain ⟨finalState, execution⟩ :=
    scanDigitRunFunction_executes source start base sourceBound
  have resultEq : scanDigitRun source start base = result := scan.executes
  rw [resultEq] at execution
  exact ⟨finalState, execution⟩

private theorem evaluates_done_deterministic
    (leftResult : Evaluates program state expression left leftState)
    (rightResult : Evaluates program state expression right rightState) :
    left = right ∧ leftState = rightState := by
  obtain ⟨leftFuel, leftExecution⟩ := leftResult
  obtain ⟨rightFuel, rightExecution⟩ := rightResult
  let fuel := max leftFuel rightFuel
  have leftAtFuel := evalExpr_done_at_larger_fuel
    (program := program) (Nat.le_max_left leftFuel rightFuel) leftExecution
  have rightAtFuel := evalExpr_done_at_larger_fuel
    (program := program) (Nat.le_max_right leftFuel rightFuel) rightExecution
  have sameOutcome := leftAtFuel.symm.trans rightAtFuel
  exact Outcome.done.inj sameOutcome

/-- Fuel choice cannot change either the value or final store of the actual
represented `scan_digit_run` call. -/
theorem scanDigitRunFunction_deterministic
    (source : List Byte) (start base : Nat)
    {left right : Value} {leftState rightState : State}
    (leftResult : Evaluates lexerProgram (sourceState source)
      (scanDigitRunCall source start base) left leftState)
    (rightResult : Evaluates lexerProgram (sourceState source)
      (scanDigitRunCall source start base) right rightState) :
    left = right ∧ leftState = rightState :=
  evaluates_done_deterministic leftResult rightResult

/-- Bases that can be selected by Lanius numeric-literal syntax. Keeping this
contract explicit avoids silently proving only a finite range of arbitrary
runtime inputs while covering every invocation made by the lexer. -/
def SupportedDigitBase (base : Nat) : Prop :=
  base = 2 ∨ base = 8 ∨ base = 10 ∨ base = 16

instance (base : Nat) : Decidable (SupportedDigitBase base) := by
  unfold SupportedDigitBase
  infer_instance

/-- Executing the represented `verified::digits::is_digit_for_base` function
agrees with the abstract digit predicate for every byte and every base the
language's numeric syntax can select. -/
theorem isDigitForBaseFunction_correct
    (base : Nat) (supported : SupportedDigitBase base) :
    ∀ byte : Byte,
      outcomeBool? (evalExpr 24 lexerProgram {}
        (.call isDigitForBaseFunction.id
          [i32Literal byte.val, i32Literal base])) =
        some (isDigitForBase byte base) := by
  rcases supported with rfl | rfl | rfl | rfl <;> native_decide

theorem isDigitForBaseFunction_deterministic
    (byte : Byte) (base : Nat) (supported : SupportedDigitBase base)
    {left right : Bool}
    (leftResult : outcomeBool? (evalExpr 24 lexerProgram {}
      (.call isDigitForBaseFunction.id
        [i32Literal byte.val, i32Literal base])) = some left)
    (rightResult : outcomeBool? (evalExpr 24 lexerProgram {}
      (.call isDigitForBaseFunction.id
        [i32Literal byte.val, i32Literal base])) = some right) :
    left = right := by
  have correct := isDigitForBaseFunction_correct base supported byte
  exact Option.some.inj (leftResult.symm.trans rightResult)

end Lanius.Compiler.Lexer.Program
