import Lanius.X86.Storage.Slice
import Lanius.ExecutionRules
import Lanius.X86.Machine.Index
import Lanius.X86.Lower.Slice

namespace Lanius.X86.Lower.Index

open Lanius.Core Lanius.Semantics

/-- These are the two supported index representations. The signed value is
normalized from its low 32 bits; unrelated ABI padding cannot affect bounds. -/
inductive Value where
  | signed (bits : BitVec 32)
  | unsigned (bits : BitVec 64)

def Value.core : Value → Core.Value
  | .signed bits => .signed .i32 bits.toInt
  | .unsigned bits => .unsigned .usize bits.toNat

def Value.word : Value → BitVec 64
  | .signed bits => bits.signExtend 64
  | .unsigned bits => bits

def Value.narrow : Value → Bool
  | .signed _ => true
  | .unsigned _ => false

def Value.argument : Value → BitVec 64 → Prop
  | .signed bits, raw => raw.setWidth 32 = bits
  | .unsigned bits, raw => raw = bits

theorem Value.normalized (value : Value) (argument : value.argument raw) :
    Machine.Index.word value.narrow raw = value.word := by
  cases value with
  | signed bits => exact congrArg (BitVec.signExtend 64) argument
  | unsigned bits => exact argument

/-- A represented packed allocation has at most 2^62 i32 elements. This is
an allocation invariant, not an unchecked restriction on caller input. -/
theorem length_bound (stored : Storage.Slice.Represents memory base values)
    (view : start + length ≤ values.length) : length ≤ 2^62 := by
  have extent := stored.bounded
  omega

theorem signed_word (bits : BitVec 32) :
    (bits.signExtend 64).toNat = if bits.toInt < 0 then
      (bits.toInt + 18446744073709551616).toNat else bits.toInt.toNat := by
  have lower : -2147483648 ≤ bits.toInt := BitVec.le_toInt bits
  have upper : bits.toInt < 2147483648 := BitVec.toInt_lt
  simp only [BitVec.signExtend, BitVec.toNat_ofInt]
  split <;> omega

/-- One unsigned comparison implements both Core's signed-negative check
and its length check, on the valid packed-storage domain. It also retains
all 64 bits for usize indices. No backing element is accessed by this test. -/
theorem bounds (value : Value) (length : Nat) (bounded : length ≤ 2^62) :
    value.word.toNat < length ↔
      ∃ index, integerIndex value.core = .ok index ∧ index < length := by
  cases value with
  | unsigned bits => simp [Value.word, Value.core, integerIndex]
  | signed bits =>
    have lower : -2147483648 ≤ bits.toInt := BitVec.le_toInt bits
    have upper : bits.toInt < 2147483648 := BitVec.toInt_lt
    by_cases negative : bits.toInt < 0
    · simp [Value.word, signed_word, Value.core, integerIndex, negative]
      omega
    · simp [Value.word, signed_word, negative, Value.core, integerIndex]

theorem accepted_index (value : Value) (length : Nat) (bounded : length ≤ 2^62)
    (accepted : value.word.toNat < length) :
    integerIndex value.core = .ok value.word.toNat := by
  cases value with
  | unsigned bits => rfl
  | signed bits =>
    have lower : -2147483648 ≤ bits.toInt := BitVec.le_toInt bits
    have upper : bits.toInt < 2147483648 := BitVec.toInt_lt
    have nonnegative : ¬ bits.toInt < 0 := by
      intro negative
      simp only [Value.word, signed_word, if_pos negative] at accepted
      omega
    simp [Value.core, Value.word, integerIndex, signed_word, nonnegative]

/-- The complete checked-address machine sequence establishes the effective
address required by the packed-element continuation. Descriptor and backing
storage are read at the post-index-expression state, and unrelated registers
and all memory survive. The source-emission proof remains separate. -/
theorem address_success (before : Machine.State) (value : Value)
    (argument : value.argument (before.registers 0))
    (layout : Frame.Layout) (slot : Fin layout.slots)
    (bounded : layout.slots ≤ 1048576) (frame : before.registers 5 = BitVec.ofNat 64 layout.base)
    (descriptor data : Machine.Address) (values : List Int) (start length index : Nat)
    (view : start + length ≤ values.length) (inside : index < length)
    (stored : Storage.Slice.Represents before.memory data values)
    (integer : integerIndex value.core = .ok index)
    (saved : Machine.read64 before.memory (layout.address slot) = descriptor)
    (pointer : Machine.read64 before.memory descriptor = Storage.Slice.address data start)
    (extent : Machine.read64 before.memory (descriptor + 8) = BitVec.ofNat 64 length)
    (loaded : Machine.CodeAt before.memory before.rip (Machine.Index.bytes value.narrow slot.val)) :
    ∃ after, Machine.Steps ((Machine.Index.prepare value.narrow slot.val).length + 2) before after ∧
      after.registers 0 = Storage.Slice.address (Storage.Slice.address data start) index ∧
      after.memory = before.memory ∧
      after.rip = before.rip + BitVec.ofNat 64 (Machine.Index.bytes value.narrow slot.val).length ∧
      (∀ register, register ≠ 0 → register ≠ 10 → register ≠ 11 →
        after.registers register = before.registers register) ∧
      after.flags.getLsbD 10 = before.flags.getLsbD 10 := by
  have lengthBound := length_bound stored view
  have accepted := (bounds value length lengthBound).mpr ⟨index, integer, inside⟩
  have number : value.word.toNat = index :=
    Except.ok.inj ((accepted_index value length lengthBound accepted).symm.trans integer)
  have wordIs : value.word = BitVec.ofNat 64 index := by rw [← number]; simp
  have lengthIs : (BitVec.ofNat 64 length).toNat = length := by
    rw [BitVec.toNat_ofNat, Nat.mod_eq_of_lt (by omega)]
  have run := Machine.Index.correct before value.narrow layout slot bounded frame descriptor
    (Storage.Slice.address data start) (BitVec.ofNat 64 length) saved pointer extent loaded
  rw [value.normalized argument, lengthIs, if_pos accepted] at run
  obtain ⟨after, steps, address, memory, rip, registers, flags⟩ := run
  refine ⟨after, steps, ?_, memory, rip, registers, flags⟩
  rw [address, wordIs]
  simp [Storage.Slice.address, BitVec.ofNat_mul]

theorem address_rejects (before : Machine.State) (value : Value)
    (argument : value.argument (before.registers 0))
    (layout : Frame.Layout) (slot : Fin layout.slots)
    (bounded : layout.slots ≤ 1048576) (frame : before.registers 5 = BitVec.ofNat 64 layout.base)
    (descriptor data : Machine.Address) (values : List Int) (start length : Nat)
    (view : start + length ≤ values.length)
    (stored : Storage.Slice.Represents before.memory data values)
    (rejected : ¬ ∃ index, integerIndex value.core = .ok index ∧ index < length)
    (saved : Machine.read64 before.memory (layout.address slot) = descriptor)
    (pointer : Machine.read64 before.memory descriptor = Storage.Slice.address data start)
    (extent : Machine.read64 before.memory (descriptor + 8) = BitVec.ofNat 64 length)
    (loaded : Machine.CodeAt before.memory before.rip (Machine.Index.bytes value.narrow slot.val)) :
    ∃ after, Machine.Steps ((Machine.Index.prepare value.narrow slot.val).length + 1) before after ∧
      Machine.Fault after ∧ after.memory = before.memory := by
  have lengthBound := length_bound stored view
  have failed : ¬ value.word.toNat < length := fun accepted => rejected ((bounds value length lengthBound).mp accepted)
  have lengthIs : (BitVec.ofNat 64 length).toNat = length := by
    rw [BitVec.toNat_ofNat, Nat.mod_eq_of_lt (by omega)]
  have run := Machine.Index.correct before value.narrow layout slot bounded frame descriptor
    (Storage.Slice.address data start) (BitVec.ofNat 64 length) saved pointer extent loaded
  rw [value.normalized argument, lengthIs, if_neg failed] at run
  obtain ⟨after, steps, fault, memory, _⟩ := run
  exact ⟨after, steps, fault, memory⟩

/-- The whole address-check-plus-load sequence refines effectful Core slice
indexing. The caller supplies the already evaluated base/index and their
shared storage relation; no effective-address premise remains. -/
theorem read_refines (program : Program) (before afterBase afterIndex : State)
    (base indexExpression : Expr) (cell : CellId) (path : List ValueProjection)
    (values : List Int) (start length index : Nat) (value : Value)
    (view : start + length ≤ values.length) (inside : index < length)
    (baseResult : Evaluates program before base
      (.slice (.scalar (.signed .i32)) cell path start length) afterBase)
    (indexResult : Evaluates program afterBase indexExpression value.core afterIndex)
    (integer : integerIndex value.core = .ok index)
    (backing : readCellProjection afterIndex cell path = .ok (.array (signedI32Values values)))
    (native : Machine.State) (argument : value.argument (native.registers 0))
    (layout : Frame.Layout) (slot : Fin layout.slots)
    (bounded : layout.slots ≤ 1048576) (frame : native.registers 5 = BitVec.ofNat 64 layout.base)
    (descriptor data : Machine.Address)
    (stored : Storage.Slice.Represents native.memory data values)
    (saved : Machine.read64 native.memory (layout.address slot) = descriptor)
    (pointer : Machine.read64 native.memory descriptor = Storage.Slice.address data start)
    (extent : Machine.read64 native.memory (descriptor + 8) = BitVec.ofNat 64 length)
    (loaded : Machine.CodeAt native.memory native.rip
      (Machine.Index.bytes value.narrow slot.val ++ Slice.loadBytes)) :
    ∃ after, Machine.Steps ((Machine.Index.prepare value.narrow slot.val).length + 3) native after ∧
      Evaluates program before (.index base indexExpression)
        (.signed .i32 ((after.registers 0).setWidth 32).toInt) afterIndex ∧
      after.memory = native.memory := by
  obtain ⟨middle, steps, address, memory, rip, _⟩ := address_success native value argument layout slot
    bounded frame descriptor data values start length index view inside stored integer saved pointer extent loaded.prefix
  have continuation : Machine.CodeAt middle.memory middle.rip Slice.loadBytes := by
    rw [memory, rip]
    exact loaded.suffix
  have backingStorage : Storage.Slice.Represents middle.memory data values := by rw [memory]; exact stored
  have final := Slice.index_refines program before afterBase afterIndex base indexExpression cell path
    values start length index value.core view inside baseResult indexResult integer backing
    middle data backingStorage address continuation
  refine ⟨middle.load32 0 0 0 Slice.loadBytes.length, ?_, final.1, final.2.2.trans memory⟩
  simpa [Nat.add_assoc] using steps.trans (.cons final.2.1 (.refl _))

/-- Core rejects a negative or out-of-range index after evaluating the base
and index expressions, without reading an array element. -/
theorem reject_core (program : Program) (before afterBase afterIndex : State)
    (base indexExpression : Expr) (cell : CellId) (path : List ValueProjection)
    (start length : Nat) (value : Value)
    (baseResult : Evaluates program before base
      (.slice (.scalar (.signed .i32)) cell path start length) afterBase)
    (indexResult : Evaluates program afterBase indexExpression value.core afterIndex)
    (rejected : ¬ ∃ index, integerIndex value.core = .ok index ∧ index < length) :
    ∃ fuel, evalExpr fuel program before (.index base indexExpression) = .trapped .arrayBounds afterIndex := by
  obtain ⟨baseFuel, baseAtFuel⟩ := baseResult
  obtain ⟨indexFuel, indexAtFuel⟩ := indexResult
  have baseAtCommon := Lanius.Fuel.evalExpr_done_at_larger_fuel (Nat.le_max_left baseFuel indexFuel) baseAtFuel
  have indexAtCommon := Lanius.Fuel.evalExpr_done_at_larger_fuel (Nat.le_max_right baseFuel indexFuel) indexAtFuel
  refine ⟨max baseFuel indexFuel + 1, ?_⟩
  rw [evalExpr.eq_def]
  simp only
  rw [baseAtCommon]
  simp only
  rw [indexAtCommon]
  simp only
  cases value with
  | unsigned bits =>
    have outside : ¬ bits.toNat < length := by simpa [Value.core, integerIndex] using rejected
    simp [Value.core, integerIndex, outside]
  | signed bits =>
    by_cases negative : bits.toInt < 0
    · simp [Value.core, integerIndex, negative]
    · have outside : ¬ bits.toInt.toNat < length := by simpa [Value.core, integerIndex, negative] using rejected
      simp [Value.core, integerIndex, negative, outside]

/-- Invalid Core indices reach the explicit machine fault, not an element
load. The native descriptor must still refer to a valid packed allocation;
forged foreign descriptors are outside the storage contract. -/
theorem reject_refines (program : Program) (before afterBase afterIndex : State)
    (base indexExpression : Expr) (cell : CellId) (path : List ValueProjection)
    (values : List Int) (start length : Nat) (value : Value)
    (view : start + length ≤ values.length)
    (baseResult : Evaluates program before base
      (.slice (.scalar (.signed .i32)) cell path start length) afterBase)
    (indexResult : Evaluates program afterBase indexExpression value.core afterIndex)
    (rejected : ¬ ∃ index, integerIndex value.core = .ok index ∧ index < length)
    (native : Machine.State) (argument : value.argument (native.registers 0))
    (layout : Frame.Layout) (slot : Fin layout.slots)
    (bounded : layout.slots ≤ 1048576) (frame : native.registers 5 = BitVec.ofNat 64 layout.base)
    (descriptor data : Machine.Address)
    (stored : Storage.Slice.Represents native.memory data values)
    (saved : Machine.read64 native.memory (layout.address slot) = descriptor)
    (pointer : Machine.read64 native.memory descriptor = Storage.Slice.address data start)
    (extent : Machine.read64 native.memory (descriptor + 8) = BitVec.ofNat 64 length)
    (loaded : Machine.CodeAt native.memory native.rip (Machine.Index.bytes value.narrow slot.val)) :
    (∃ fuel, evalExpr fuel program before (.index base indexExpression) = .trapped .arrayBounds afterIndex) ∧
      ∃ after, Machine.Steps ((Machine.Index.prepare value.narrow slot.val).length + 1) native after ∧
        Machine.Fault after ∧ after.memory = native.memory :=
  ⟨reject_core program before afterBase afterIndex base indexExpression cell path start length value
      baseResult indexResult rejected,
    address_rejects native value argument layout slot bounded frame descriptor data values start length
      view stored rejected saved pointer extent loaded⟩

end Lanius.X86.Lower.Index
