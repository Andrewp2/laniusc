import Lean.Elab.Tactic.Omega
import Lanius.Semantics.Frame
import Lanius.Semantics.Loop
import Lanius.Semantics.Pure
import Lanius.Semantics.Rules
import Lanius.Semantics.Fuel

namespace Lanius.Semantics

open Lanius Lanius.Core

/-- A contract valid at every fuel value above an evaluator threshold. -/
def StableExpr (threshold : Nat) (program : Program) (state : State)
    (expression : Expr) (value : Value) (after : State) : Prop :=
  ∀ fuel, threshold ≤ fuel →
    evalExpr fuel program state expression = .done value after

/-- A statement analogue of `StableExpr`, for fixed completion and state. -/
def StableStmt (threshold : Nat) (program : Program) (state : State)
    (statement : Stmt) (completion : Completion) (after : State) : Prop :=
  ∀ fuel, threshold ≤ fuel →
    execStmt fuel program state statement = .done completion after

/-- A single completed evaluation suffices for every greater fuel budget. -/
theorem StableExpr.ofEval (run : evalExpr threshold program state expression = .done value after) :
    StableExpr threshold program state expression value after :=
  fun _ enough => evalExpr_of_le run (by intro h; cases h) enough

theorem StableStmt.ofExec (run : execStmt threshold program state statement = .done completion after) :
    StableStmt threshold program state statement completion after :=
  fun _ enough => execStmt_of_le run (by intro h; cases h) enough

theorem Evaluates.stable (run : Evaluates program state expression value after) :
    ∃ threshold, StableExpr threshold program state expression value after := by
  obtain ⟨threshold, run⟩ := run
  exact ⟨threshold, .ofEval run⟩

theorem Executes.stable (run : Executes program state statement completion after) :
    ∃ threshold, StableStmt threshold program state statement completion after := by
  obtain ⟨threshold, run⟩ := run
  exact ⟨threshold, .ofExec run⟩

theorem StableExpr.weaken (run : StableExpr old program state expression value after)
    (enough : old ≤ threshold) : StableExpr threshold program state expression value after :=
  fun fuel available => run fuel (Nat.le_trans enough available)

theorem StableExpr.booleanResult
    (run : StableExpr threshold program state expression (.boolean actual) after)
    (result : actual = expected) :
    StableExpr threshold program state expression (.boolean expected) after := result ▸ run

theorem StableExpr.value {value : Value} : StableExpr 1 program state (.value value) value state := .ofEval rfl

theorem StableExpr.enumEmpty :
    StableExpr 2 program state (.enumValue typeId ordinal []) (.enumeration typeId ordinal []) state := .ofEval rfl

theorem StableExpr.constant (found : program.constant? constantId = some declaration) :
    StableExpr 1 program state (.constant constantId) declaration.value state := by
  intro fuel enough
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [found]

theorem StableExpr.constantResult {value : Value}
    (found : program.constant? constantId = some declaration)
    (result : declaration.value = value) :
    StableExpr 1 program state (.constant constantId) value state := result ▸ .constant found

theorem StableExpr.unary {value : Value}
    (operand : StableExpr threshold program state expression value after)
    (evaluates : evalUnaryValue program.target operation value = .ok result) :
    StableExpr (threshold + 1) program state (.unary operation expression) result after := by
  intro fuel enough
  have run := operand (fuel - 1) (by omega)
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [run, evaluates]

theorem StableExpr.cast {value : Value}
    (operand : StableExpr threshold program state expression value after)
    (evaluates : evalScalarCast program.target destination value = .ok result) :
    StableExpr (threshold + 1) program state (.cast destination expression) result after := by
  intro fuel enough
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [operand (fuel - 1) (by omega), evaluates]

theorem StableExpr.binary
    {leftFuel rightFuel : Nat} {program : Program} {before middle after : State}
    {operation : BinaryOp} {left right : Expr} {leftValue rightValue result : Value}
    (leftRun : StableExpr leftFuel program before left leftValue middle)
    (rightRun : StableExpr rightFuel program middle right rightValue after)
    (eager : operation ≠ .logicalAnd ∧ operation ≠ .logicalOr)
    (evaluates : evalBinaryValue program.target operation leftValue rightValue = .ok result) :
    StableExpr (max leftFuel rightFuel + 1) program before
      (.binary operation left right) result after := by
  intro fuel enough
  have left := leftRun (fuel - 1) (by omega)
  have right := rightRun (fuel - 1) (by omega)
  simpa [show fuel - 1 + 1 = fuel by omega] using
    evalExpr_binary_done (fuel - 1) program before operation _ _ _ _ _ middle after
      left right eager evaluates

theorem StableExpr.logicalOr
    (left : StableExpr leftFuel program state leftExpr (.boolean a) state)
    (right : StableExpr rightFuel program state rightExpr (.boolean b) state) :
    StableExpr (max leftFuel rightFuel + 1) program state
      (.binary .logicalOr leftExpr rightExpr) (.boolean (a || b)) state := by
  intro fuel enough
  simpa [show fuel - 1 + 1 = fuel by omega] using
    evalExpr_logicalOr_booleans (fuel - 1) program state leftExpr rightExpr a b
      (left (fuel - 1) (by omega)) (right (fuel - 1) (by omega))

theorem StableExpr.logicalAndFalse
    (left : StableExpr threshold program before leftExpr (.boolean false) after) :
    StableExpr (threshold + 1) program before (.binary .logicalAnd leftExpr rightExpr) (.boolean false) after := by
  intro fuel enough
  simpa [show fuel - 1 + 1 = fuel by omega] using
    evalExpr_logicalAnd_false (fuel - 1) program before leftExpr rightExpr after (left (fuel - 1) (by omega))

theorem StableExpr.logicalAndTrue
    {value : Value}
    (left : StableExpr leftFuel program before leftExpr (.boolean true) middle)
    (right : StableExpr rightFuel program middle rightExpr value after) :
    StableExpr (max leftFuel rightFuel + 1) program before (.binary .logicalAnd leftExpr rightExpr) value after := by
  intro fuel enough
  simpa [show fuel - 1 + 1 = fuel by omega] using
    evalExpr_logicalAnd_true (fuel - 1) program before leftExpr rightExpr value middle after
      (left (fuel - 1) (by omega)) (right (fuel - 1) (by omega))

theorem StableExpr.logicalAnd
    (left : StableExpr leftFuel program state leftExpr (.boolean a) state)
    (right : StableExpr rightFuel program state rightExpr (.boolean b) state) :
    StableExpr (max leftFuel rightFuel + 1) program state
      (.binary .logicalAnd leftExpr rightExpr) (.boolean (a && b)) state := by
  intro fuel enough
  simpa [show fuel - 1 + 1 = fuel by omega] using
    evalExpr_logicalAnd_booleans (fuel - 1) program state leftExpr rightExpr a b
      (left (fuel - 1) (by omega)) (right (fuel - 1) (by omega))

/-- A true left operand skips the right operand, even if it would trap. -/
theorem StableExpr.logicalOrTrue
    (left : StableExpr threshold program before leftExpr (.boolean true) after) :
    StableExpr (threshold + 1) program before (.binary .logicalOr leftExpr rightExpr)
      (.boolean true) after := by
  intro fuel enough
  simpa [show fuel - 1 + 1 = fuel by omega] using
    evalExpr_logicalOr_true (fuel - 1) program before leftExpr rightExpr after
      (left (fuel - 1) (by omega))

theorem StableExpr.local {value : Value} (found : state.local? localId = some value) :
    StableExpr 1 program state (.local localId) value state := by
  intro fuel enough
  simpa [show fuel - 1 + 1 = fuel by omega] using
    evalExpr_local_of_local? (fuel - 1) program state localId value found

/-- Reading a field composes with the base's actual execution and effects. -/
theorem StableExpr.field {value : Value}
    (base : StableExpr threshold program before expression (.structure typeId fields) after)
    (found : fields[fieldId]? = some value) :
    StableExpr (threshold + 1) program before (.field expression fieldId) value after := by
  intro fuel enough
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [base (fuel - 1) (by omega), found]

/-- Indexed raw reads compose the base and index computations before loading
    from their resulting heap. The index need not be a temporary local. -/
theorem StableExpr.rawSliceRead {value : Value}
    (source : StableExpr sourceFuel program state sourceExpr (.rawSlice element address length) middle)
    (index : StableExpr indexFuel program middle indexExpr (.signed .i32 (position : Nat)) after)
    (readable : readRawSliceIndex program after element address length position = .ok value) :
    StableExpr (max sourceFuel indexFuel + 1) program state
      (.index sourceExpr indexExpr) value after := by
  intro fuel enough
  have sourceRun := source (fuel - 1) (by omega)
  have indexRun := index (fuel - 1) (by omega)
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [sourceRun, indexRun, integerIndex,
    Int.not_lt_of_ge (Int.natCast_nonneg position), ↓reduceIte, Int.toNat_natCast, readable]

/-- An empty descriptor needs no allocation, even when its pointer is null. -/
theorem StableExpr.emptyRawI32Slice
    (pointer : StableExpr pointerFuel program before expression (.pointer address) middle)
    (length : StableExpr lengthFuel program middle lengthExpr (.signed .i32 0) after) :
    StableExpr (max pointerFuel lengthFuel + 1) program before
      (.i32SliceFromRawParts expression lengthExpr)
      (.rawSlice (.scalar (.signed .i32)) address 0) after := by
  intro fuel enough
  rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
  simp only [pointer (fuel - 1) (by omega), length (fuel - 1) (by omega),
    mapRawI32Slice, Int.lt_irrefl, ↓reduceIte]

theorem StableExpr.emptyRawNominalSlice
    (pointer : StableExpr pointerFuel program before expression (.pointer address) middle)
    (length : StableExpr lengthFuel program middle lengthExpr (.signed .i32 0) after)
    (nominal : (match element with | .structure _ | .enumeration _ => true | _ => false) = true)
    (layout : NativeLayout.valueWords? program element = some words) (positive : 0 < words) :
    StableExpr (max pointerFuel lengthFuel + 1) program before
      (.typedSliceFromRawParts element expression lengthExpr) (.rawSlice element address 0) after := by
  cases element <;> simp at nominal
  all_goals
    intro fuel enough
    rw [show fuel = (fuel - 1).succ by omega, evalExpr.eq_def]
    simp [pointer (fuel - 1) (by omega), length (fuel - 1) (by omega),
      mapRawNominalSlice, layout, Nat.ne_of_gt positive]

/-- A raw-slice read follows from local bindings and a readable heap element,
    not from an assumed successful evaluation of the source expression. -/
theorem StableExpr.rawSliceIndex {value : Value}
    (source : state.local? sourceId = some (.rawSlice element address length))
    (index : state.local? indexId = some (.signed .i32 (Int.ofNat position)))
    (readable : readRawSliceIndex program state element address length position = .ok value) :
    StableExpr 2 program state (.index (.local sourceId) (.local indexId)) value state := by
  intro fuel enough
  rw [show fuel = (fuel - 2).succ.succ by omega, evalExpr.eq_def]
  dsimp only
  simp only [evalExpr_local_of_local? _ _ _ _ _ source,
    evalExpr_local_of_local? _ _ _ _ _ index]
  have nonnegative : ¬((position : Int) < 0) := Int.not_lt_of_ge (Int.natCast_nonneg position)
  simp only [integerIndex, Int.ofNat_eq_natCast, nonnegative, ↓reduceIte,
    Int.toNat_natCast, readable]

theorem StableStmt.skip (program : Program) (state : State) :
    StableStmt 1 program state .skip .next state := .ofExec rfl

/-- A pure execution may append fresh cells while preserving the caller frame. -/
structure PureFrame (before after : State) : Prop where
  beforeFormed : before.CellsWellFormed
  cells : FreshCellFrame before after
  locals : after.locals = before.locals
  heap : after.heap = before.heap
  world : after.world = before.world
  views : after.i32ArrayViews = before.i32ArrayViews

theorem PureFrame.refl (formed : state.CellsWellFormed) : PureFrame state state :=
  ⟨formed, ⟨[], by simp, Nat.le_refl _, by simp⟩, rfl, rfl, rfl, rfl⟩

theorem PureFrame.afterFormed
    (frame : PureFrame before after) : after.CellsWellFormed :=
  FreshCellFrame.after_cellsWellFormed frame.beforeFormed frame.cells

theorem PureFrame.localFound {id : VarId} {value : Value} (frame : PureFrame before after)
    (found : before.local? id = some value) : after.local? id = some value :=
  frame.cells.localFound frame.locals id value found

theorem PureFrame.trans
    (left : PureFrame before middle)
    (right : PureFrame middle after) : PureFrame before after :=
  ⟨left.beforeFormed, left.cells.trans right.cells, right.locals.trans left.locals,
    right.heap.trans left.heap, right.world.trans left.world, right.views.trans left.views⟩

/-- A contract valid at every fuel value above its evaluator threshold. -/
structure ThresholdPure (fuelThreshold : Nat)
    (program : Program) (before : State) (expression : Expr)
    (value : Value) (after : State) : Prop where
  run : ∀ fuel, fuelThreshold ≤ fuel →
    evalExpr fuel program before expression = .done value after
  frame : PureFrame before after

theorem StableStmt.letLocal
    {initFuel bodyFuel : Nat} (program : Program) (state : State)
    (id : VarId) (type : Ty) (initializer : Expr) (body : Stmt)
    (value : Value) (afterInit afterBody : State) (completion : Completion)
    (initializerContract : StableExpr initFuel program state initializer value afterInit)
    (bodyContract : StableStmt bodyFuel program (afterInit.bindLocal id value)
      body completion afterBody) :
    StableStmt (max initFuel bodyFuel + 1) program state
      (.letLocal id type initializer body) completion
      (restoreLocals afterInit afterBody) := by
  intro fuel enough
  have initializerRun := initializerContract (fuel - 1) (by omega)
  have bodyRun := bodyContract (fuel - 1) (by omega)
  simpa [show fuel - 1 + 1 = fuel by omega] using
    (execStmt_letLocal (fuel := fuel - 1) program state id type initializer body
      value afterInit afterBody completion initializerRun bodyRun)

theorem ThresholdPure.erase
    {fuelThreshold : Nat} {program : Program} {before : State} {expression : Expr}
    {value : Value} {after : State}
    (contract : ThresholdPure fuelThreshold program before expression value after) :
    PurelyEvaluates program before expression value := by
  exact ⟨after, ⟨⟨fuelThreshold, contract.run _ (Nat.le_refl _)⟩,
    contract.frame.beforeFormed, contract.frame.afterFormed, contract.frame.locals,
    contract.frame.heap, contract.frame.world, contract.frame.views⟩⟩

theorem ThresholdPure.weaken
    {oldThreshold newThreshold : Nat} {program : Program} {before : State}
    {expression : Expr} {value : Value} {after : State}
    (contract : ThresholdPure oldThreshold program before expression value after)
    (threshold : oldThreshold ≤ newThreshold) :
    ThresholdPure newThreshold program before expression value after := by
  exact ⟨fun fuel enough => contract.run fuel (Nat.le_trans threshold enough), contract.frame⟩

theorem logicalOrTrue
    {leftFuel : Nat} {program : Program} {before after : State} {left right : Expr}
    (leftContract : ThresholdPure leftFuel program before left (.boolean true) after) :
    ThresholdPure (leftFuel + 1) program before (.binary .logicalOr left right)
      (.boolean true) after := by
  refine ⟨?_, leftContract.frame⟩
  intro fuel enough
  have leftEval := leftContract.run (fuel - 1) (by omega)
  simpa [show fuel - 1 + 1 = fuel by omega] using
    (evalExpr_logicalOr_true (fuel - 1) program before left right after leftEval)

theorem logicalOrFalse
    {leftFuel rightFuel : Nat} {program : Program} {before : State} {left right : Expr}
    {middle after : State} {rightValue : Bool}
    (leftContract : ThresholdPure leftFuel program before left (.boolean false) middle)
    (rightContract : ThresholdPure rightFuel program middle right (.boolean rightValue) after) :
    ThresholdPure (max leftFuel rightFuel + 1) program before (.binary .logicalOr left right)
      (.boolean rightValue) after := by
  refine ⟨?_, ?_⟩
  · intro fuel enough
    have leftEval := leftContract.run (fuel - 1) (by omega)
    have rightEval := rightContract.run (fuel - 1) (by omega)
    simpa [show fuel - 1 + 1 = fuel by omega] using
      (evalExpr_logicalOr_false (fuel - 1) program before left right
      (.boolean rightValue) middle after leftEval rightEval)
  · exact leftContract.frame.trans rightContract.frame

theorem logicalOr3
    {program : Program} {state : State} {first second third : Expr}
    {a b c : Bool}
    (firstRun : ThresholdPure 3 program state first (.boolean a) state)
    (secondRun : ThresholdPure 3 program state second (.boolean b) state)
    (thirdRun : ThresholdPure 3 program state third (.boolean c) state) :
    ∃ fuel, ThresholdPure fuel program state
      (.binary .logicalOr (.binary .logicalOr first second) third)
      (.boolean (a || b || c)) state := by
  cases a with
  | false =>
      cases b with
      | false =>
          cases c with
          | false => exact ⟨_, logicalOrFalse (logicalOrFalse firstRun secondRun) thirdRun⟩
          | true => exact ⟨_, logicalOrFalse (logicalOrFalse firstRun secondRun) thirdRun⟩
      | true =>
          cases c <;> exact ⟨_, logicalOrTrue (logicalOrFalse firstRun secondRun)⟩
  | true =>
      cases b <;> cases c <;>
        exact ⟨_, logicalOrTrue (logicalOrTrue firstRun)⟩

end Lanius.Semantics
