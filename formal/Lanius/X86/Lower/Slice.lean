import Lanius.X86.Storage.Slice
import Lanius.X86.Frame.Function
import Lanius.ExecutionRules

namespace Lanius.X86.Lower.Slice

open Lanius.Core Lanius.Semantics Lanius.Fuel

/-- The final element access emitted by `backend::compile`: the checked
address is in RAX for a read and in R11 for a store. Address calculation and
the bounds guard are separate simulation obligations, not assumed verified. -/
def loadBytes : List UInt8 := Machine.memoryBytes .w32 true 0 0 0
def storeBytes : List UInt8 := Machine.memoryBytes .w32 false 0 11 0

theorem load_decodes : Machine.decode loadBytes = some (.load32 0 0 0, loadBytes.length) := by
  simpa [loadBytes, Machine.memoryInstruction] using
    Machine.memory_decodes .w32 true 0 0 0 []

theorem store_decodes : Machine.decode storeBytes = some (.store32 0 11 0, storeBytes.length) := by
  simpa [storeBytes, Machine.memoryInstruction] using
    Machine.memory_decodes .w32 false 0 11 0 []

theorem load_correct (before : Machine.State) (base : Machine.Address) (values : List Int)
    (start length index : Nat) (view : start + length ≤ values.length) (inside : index < length)
    (stored : Storage.Slice.Represents before.memory base values)
    (pointer : before.registers 0 = Storage.Slice.address (Storage.Slice.address base start) index)
    (loaded : Machine.CodeAt before.memory before.rip loadBytes) :
    let after := before.load32 0 0 0 loadBytes.length
    Machine.Step before after ∧
      (after.registers 0).setWidth 32 = BitVec.ofInt 32 values[start + index] ∧
      ((after.registers 0).setWidth 32).toInt = values[start + index] ∧
      (∀ register, register ≠ 0 → after.registers register = before.registers register) ∧
      after.memory = before.memory ∧ after.flags = before.flags := by
  dsimp only
  have word := stored.elements (start + index) (by omega)
  have read := stored.read start length index view inside
  refine ⟨.decoded _ loaded _ _ load_decodes rfl, ?_, ?_, ?_, rfl, rfl⟩
  · simpa [Machine.State.load32, Machine.State.immediate32, pointer,
      Storage.Slice.address_add] using word
  · simpa [Machine.State.load32, Machine.State.immediate32, pointer] using read
  · intro register different
    simp [Machine.State.load32, Machine.State.immediate32, different]

theorem store_correct (before : Machine.State) (base : Machine.Address) (values : List Int)
    (index : Nat) (inside : index < values.length) (replacement : Int)
    (signed : -2147483648 ≤ replacement ∧ replacement ≤ 2147483647)
    (stored : Storage.Slice.Represents before.memory base values)
    (pointer : before.registers 11 = Storage.Slice.address base index)
    (value : (before.registers 0).setWidth 32 = BitVec.ofInt 32 replacement)
    (loaded : Machine.CodeAt before.memory before.rip storeBytes) :
    let after := before.store32 0 11 0 storeBytes.length
    Machine.Step before after ∧
      Storage.Slice.Represents after.memory base (values.set index replacement) ∧
      (∀ candidate, (∀ lane : Fin 4,
        candidate ≠ Storage.Slice.address base index + BitVec.ofNat 64 lane.val) →
        after.memory candidate = before.memory candidate) ∧
      after.registers = before.registers ∧ after.flags = before.flags := by
  dsimp only
  refine ⟨.decoded _ loaded _ _ store_decodes rfl, ?_, ?_, rfl, rfl⟩
  · simpa [Machine.State.store32, pointer, value] using stored.store index inside replacement signed
  · intro candidate outside
    simpa [Machine.State.store32, pointer, value] using
      Storage.Slice.store_frame before.memory base index replacement candidate outside

/-- Heap ownership must separate an element store from the saved caller
header. Given that boundary, the existing whole-function frame invariant
survives the exact store instruction used by slice assignment. -/
theorem store_preserves_caller {entry started before : Machine.State}
    (frame : Frame.BodyFrame entry started before)
    (base : Machine.Address) (index : Nat)
    (pointer : before.registers 11 = Storage.Slice.address base index)
    (separate : ∀ header : Fin 16, ∀ lane : Fin 4,
      started.registers 5 + BitVec.ofNat 64 header.val ≠
        Storage.Slice.address base index + BitVec.ofNat 64 lane.val) :
    Frame.BodyFrame entry started (before.store32 0 11 0 storeBytes.length) := by
  apply frame.write32
  simpa [pointer] using separate

/-- Core reads the descriptor before the index expression, but reads its
backing array after that expression. Both may have effects. The view may
start inside an allocation and its cell may be reached through projections. -/
theorem index_core (program : Program) (before afterBase afterIndex : State)
    (base indexExpression : Expr) (cell : CellId) (path : List ValueProjection)
    (values : List Int) (start length index : Nat) (indexValue : Value)
    (view : start + length ≤ values.length) (inside : index < length)
    (baseResult : Evaluates program before base
      (.slice (.scalar (.signed .i32)) cell path start length) afterBase)
    (indexResult : Evaluates program afterBase indexExpression indexValue afterIndex)
    (integer : integerIndex indexValue = .ok index)
    (backing : readCellProjection afterIndex cell path = .ok (.array (signedI32Values values))) :
    Evaluates program before (.index base indexExpression)
      (.signed .i32 values[start + index]) afterIndex := by
  obtain ⟨baseFuel, baseAtFuel⟩ := baseResult
  obtain ⟨indexFuel, indexAtFuel⟩ := indexResult
  have baseAtCommon := evalExpr_done_at_larger_fuel (Nat.le_max_left baseFuel indexFuel) baseAtFuel
  have indexAtCommon := evalExpr_done_at_larger_fuel (Nat.le_max_right baseFuel indexFuel) indexAtFuel
  refine ⟨max baseFuel indexFuel + 1, ?_⟩
  rw [evalExpr.eq_def]
  simp only
  rw [baseAtCommon]
  simp only
  rw [indexAtCommon]
  simp only
  rw [integer]
  simp only
  rw [if_pos inside]
  have slice : sliceValues afterIndex cell path start length =
      .ok (((signedI32Values values).drop start).take length) := by
    simp [sliceValues, backing, signedI32Values, view]
  rw [slice]
  simp only
  have selected : (((signedI32Values values).drop start).take length)[index]? =
      some (.signed .i32 values[start + index]) := by
    rw [List.getElem?_take_of_lt inside, List.getElem?_drop]
    simp [signedI32Values, show start + index < values.length by omega]
  rw [selected]

/-- The final decoded load and the effectful Core indexing expression return
the same signed i32, with the backing representation taken at the actual
read point. Recursive lowering must supply the base/index simulations and
checked effective address; this is their memory-operation continuation. -/
theorem index_refines (program : Program) (before afterBase afterIndex : State)
    (base indexExpression : Expr) (cell : CellId) (path : List ValueProjection)
    (values : List Int) (start length index : Nat) (indexValue : Value)
    (view : start + length ≤ values.length) (inside : index < length)
    (baseResult : Evaluates program before base
      (.slice (.scalar (.signed .i32)) cell path start length) afterBase)
    (indexResult : Evaluates program afterBase indexExpression indexValue afterIndex)
    (integer : integerIndex indexValue = .ok index)
    (backing : readCellProjection afterIndex cell path = .ok (.array (signedI32Values values)))
    (native : Machine.State) (data : Machine.Address)
    (stored : Storage.Slice.Represents native.memory data values)
    (pointer : native.registers 0 = Storage.Slice.address (Storage.Slice.address data start) index)
    (loaded : Machine.CodeAt native.memory native.rip loadBytes) :
    let after := native.load32 0 0 0 loadBytes.length
    Evaluates program before (.index base indexExpression)
      (.signed .i32 ((after.registers 0).setWidth 32).toInt) afterIndex ∧
      Machine.Step native after ∧ after.memory = native.memory := by
  have core := index_core program before afterBase afterIndex base indexExpression cell path
    values start length index indexValue view inside baseResult indexResult integer backing
  have machine := load_correct native data values start length index view inside stored pointer loaded
  exact ⟨machine.2.2.1.symm ▸ core, machine.1, machine.2.2.2.2.1⟩

/-- Assignment consumes the previously resolved location and old value.
The RHS may mutate the backing array; the final store updates its *current*
contents, not the array captured during place resolution. This covers both
plain and compound assignment once the scalar operation has been simulated. -/
theorem assign_core (program : Program) (before afterPlace afterRight : State)
    (place : Place) (right : Expr) (op : AssignOp) (old : Option Value) (rightValue : Value)
    (cell : CellId) (index : Nat) (values : List Int) (replacement : Int)
    (inside : index < values.length)
    (placeResult : ∃ fuel, evalPlace fuel program before place =
      .done { root := cell, projections := [.index index], value := old } afterPlace)
    (rightResult : Evaluates program afterPlace right rightValue afterRight)
    (operation : evalAssignValue program.target op old rightValue = .ok (.signed .i32 replacement))
    (backing : afterRight.cellEntry? cell = some {
      id := cell, value := some (.array (signedI32Values values)) }) :
    ∃ after, Evaluates program before (.assign op place right) .unit after ∧
      after.cellEntry? cell = some {
        id := cell, value := some (.array (signedI32Values (values.set index replacement))) } ∧
      (∀ other, other ≠ cell → after.cellEntry? other = afterRight.cellEntry? other) ∧
      after.heap = afterRight.heap ∧ after.world = afterRight.world := by
  let after : State := { afterRight with
    cells := replaceCell afterRight.cells cell (.array (signedI32Values (values.set index replacement))) }
  have assigned : afterRight.assignCell cell
      (.array (signedI32Values (values.set index replacement))) = some after := by
    simp [State.assignCell, backing, after]
  have valueAt : (signedI32Values values)[index]? = some (.signed .i32 values[index]) := by
    simp [signedI32Values, inside]
  have written : writeResolvedPlace afterRight
      { root := cell, projections := [.index index], value := old } (.signed .i32 replacement) = .ok after := by
    simp [writeResolvedPlace, backing, replaceProjectedValue, valueAt,
      setValue_signedI32Values, setI32Value, assigned]
  obtain ⟨placeFuel, placeAtFuel⟩ := placeResult
  obtain ⟨rightFuel, rightAtFuel⟩ := rightResult
  have placeAtCommon := evalPlace_done_at_larger_fuel (Nat.le_max_left placeFuel rightFuel) placeAtFuel
  have rightAtCommon := evalExpr_done_at_larger_fuel (Nat.le_max_right placeFuel rightFuel) rightAtFuel
  refine ⟨after, ⟨max placeFuel rightFuel + 1, ?_⟩,
    Lanius.Properties.assignCell_finds_assigned assigned, ?_, rfl, rfl⟩
  · rw [evalExpr.eq_def]
    simp only
    rw [placeAtCommon]
    simp only
    rw [rightAtCommon]
    simp only
    rw [operation]
    simp only
    rw [written]
  · intro other different
    exact Lanius.Properties.assignCell_preserves_other assigned different

/-- Core and native stores preserve one shared backing-array relation after
arbitrary RHS effects. The scalar operation's result and saved target address
are explicit premises for the enclosing expression simulation to establish. -/
theorem assign_refines (program : Program) (before afterPlace afterRight : State)
    (place : Place) (right : Expr) (op : AssignOp) (old : Option Value) (rightValue : Value)
    (cell : CellId) (index : Nat) (values : List Int) (replacement : Int)
    (inside : index < values.length)
    (placeResult : ∃ fuel, evalPlace fuel program before place =
      .done { root := cell, projections := [.index index], value := old } afterPlace)
    (rightResult : Evaluates program afterPlace right rightValue afterRight)
    (operation : evalAssignValue program.target op old rightValue = .ok (.signed .i32 replacement))
    (backing : afterRight.cellEntry? cell = some {
      id := cell, value := some (.array (signedI32Values values)) })
    (native : Machine.State) (data : Machine.Address)
    (signed : -2147483648 ≤ replacement ∧ replacement ≤ 2147483647)
    (stored : Storage.Slice.Represents native.memory data values)
    (pointer : native.registers 11 = Storage.Slice.address data index)
    (value : (native.registers 0).setWidth 32 = BitVec.ofInt 32 replacement)
    (loaded : Machine.CodeAt native.memory native.rip storeBytes) :
    let after := native.store32 0 11 0 storeBytes.length
    ∃ coreAfter, Evaluates program before (.assign op place right) .unit coreAfter ∧
      coreAfter.cellEntry? cell = some {
        id := cell, value := some (.array (signedI32Values (values.set index replacement))) } ∧
      Machine.Step native after ∧ Storage.Slice.Represents after.memory data (values.set index replacement) ∧
      (∀ candidate, (∀ lane : Fin 4,
        candidate ≠ Storage.Slice.address data index + BitVec.ofNat 64 lane.val) →
        after.memory candidate = native.memory candidate) := by
  obtain ⟨coreAfter, run, backingAfter, _⟩ := assign_core program before afterPlace afterRight
    place right op old rightValue cell index values replacement inside placeResult rightResult operation backing
  have machine := store_correct native data values index inside replacement signed stored pointer value loaded
  exact ⟨coreAfter, run, backingAfter, machine.1, machine.2.1, machine.2.2.1⟩

end Lanius.X86.Lower.Slice
