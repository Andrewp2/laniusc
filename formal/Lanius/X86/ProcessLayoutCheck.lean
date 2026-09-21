import Lanius.X86.StartupCheck
import Lanius.X86.Machine.FrameSlots
import Lanius.X86.ExpressionFunctionCheck
import Lanius.X86.FunctionCheck

namespace Lanius.X86.ProcessLayoutCheck

open Lanius Lanius.X86
open Lanius.Core
open Lanius.X86.Machine
open Lanius.X86.StartupCheck
open Lanius.X86.FunctionCheck

/- The continuation written by the startup CALL and the syscall instruction
   reached after the result move and exit-number load.  These are addresses in
   the authenticated startup bytes, not an OS execution model. -/
def startupReturnAddress : Machine.Address :=
  callAddress + BitVec.ofNat 64 callCode.length

def startupExitAddress : Machine.Address :=
  startupReturnAddress + BitVec.ofNat 64 (returnResult.length + loadExit.length)

theorem startup_exit_address :
    startupExitAddress =
      callAddress + BitVec.ofNat 64
        (callCode.length + returnResult.length + loadExit.length) := by
  simp only [startupExitAddress, startupReturnAddress, BitVec.add_assoc,
    ← BitVec.ofNat_add]
  congr 1

/- The ordinary return words are always present.  A direct call adds its
   authenticated call/return window; a connected body adds exactly the slots
   named by its recursive statement shape. -/
def entryStackFootprint (entry : Function) : List Nat :=
  [8, 16] ++ match entry.body with
  | some (.returnValue (some (.call _ _))) => [32, 40]
  | some (.sequence (.returnValue (some (.call _ _))) .skip) => [32, 40]
  | some source =>
      (List.range (statementAllocationCount source)).map (fun slot => 16 + 8 * slot)
  | _ => []

private theorem return_footprint {source : Core.Expr}
    (expression : StatementCheck.ExpressionCertificate source) :
    (match (some (.returnValue (some source)) : Option Stmt) with
      | some (.returnValue (some (.call _ _))) => [32, 40]
      | some (.sequence (.returnValue (some (.call _ _))) .skip) => [32, 40]
      | some source =>
          (List.range (statementAllocationCount source)).map
            (fun slot => 16 + 8 * slot)
      | _ => []) =
      (List.range (statementAllocationCount (.returnValue (some source)))).map
        (fun slot => 16 + 8 * slot) := by
  split <;> simp_all [statementAllocationCount] <;>
    try subst_vars <;>
    try cases expression.checked.1 <;>
    simp_all [statementAllocationCount]

theorem body_frame_slot_mem {entry : Function} {source : Stmt}
    {shape : ExpressionFunctionCheck.BodyShape source}
    (bodyExact : entry.body = some source)
    {slot : Nat} (slotBound : slot < shape.allocations) :
    16 + 8 * slot ∈ entryStackFootprint entry := by
  cases shape with
  | terminal expression =>
      unfold entryStackFootprint
      rw [bodyExact]
      rw [return_footprint expression]
      simp only [List.mem_append, List.mem_cons, List.not_mem_nil, or_false]
      right
      apply List.mem_map.mpr
      exact ⟨slot, by
        rw [body_allocation_count_eq (shape :=
          ExpressionFunctionCheck.BodyShape.terminal expression)]
        simpa using slotBound, rfl⟩
  | sequence head tail =>
      have countExact := body_allocation_count_eq (shape :=
        ExpressionFunctionCheck.BodyShape.sequence head tail)
      cases head <;> simp only [entryStackFootprint, bodyExact]
      all_goals
        apply List.mem_append.mpr
        right
        apply List.mem_map.mpr
        exact ⟨slot, by simpa [countExact] using slotBound, rfl⟩
  | @letLocal id type initializer initializerShape initializerI32 =>
      simp only [entryStackFootprint, bodyExact]
      apply List.mem_append.mpr
      right
      apply List.mem_map.mpr
      have countExact := body_allocation_count_eq (shape :=
        ExpressionFunctionCheck.BodyShape.letLocal (id := id) (type := type)
          (initializer := initializer) initializerShape initializerI32)
      exact ⟨slot, by simpa [countExact] using slotBound, rfl⟩

def startupStackFootprint (entry : Function) : List Nat :=
  [8, 16, 24] ++ (entryStackFootprint entry).map (fun slot => 24 + slot)

theorem startupStackFootprint_mem (entry : Function) :
    8 ∈ startupStackFootprint entry ∧
    16 ∈ startupStackFootprint entry ∧
    24 ∈ startupStackFootprint entry ∧
    32 ∈ startupStackFootprint entry ∧
    40 ∈ startupStackFootprint entry := by
  unfold startupStackFootprint entryStackFootprint
  split <;> simp

def ImageStackDisjoint (elf : List UInt8) (before : Machine.State)
    (entry : Function) : Prop :=
  ∀ offset, offset < elf.length → ∀ slot, slot ∈ startupStackFootprint entry →
    ∀ lane : Fin 8,
    base + BitVec.ofNat 64 offset ≠
      before.registers rspRegister - BitVec.ofNat 64 slot + BitVec.ofNat 64 lane.val

def StackCodeDisjoint (before : Machine.State) (code : Machine.Address)
    (length : Nat) (entry : Function) : Prop :=
  ∀ index, index < length → ∀ lane : Fin 8, ∀ slot,
    slot ∈ entryStackFootprint entry →
    code + BitVec.ofNat 64 index ≠
      before.registers rspRegister - BitVec.ofNat 64 slot + BitVec.ofNat 64 lane.val

def FunctionTextDisjoint (before : Machine.State) (target : Machine.Address)
    (length : Nat) : Prop :=
  ∀ index, index < length → ∀ lane : Fin 8,
      target + BitVec.ofNat 64 index ≠
        before.registers rspRegister - 24 - 8 + BitVec.ofNat 64 lane.val ∧
      target + BitVec.ofNat 64 index ≠
        before.registers rspRegister - 24 - 16 + BitVec.ofNat 64 lane.val

private theorem bmod32_self {d : Int} (lower : -(2^31 : Int) ≤ d) (upper : d < 2^31) :
    d.bmod (2^32) = d := by
  rw [Int.bmod_eq_emod]
  have nonnegative : 0 ≤ d % (2^32 : Int) := Int.emod_nonneg _ (by decide); have below : d % (2^32 : Int) < (2^32 : Int) := Int.emod_lt _ (by decide)
  split <;> omega

private theorem bmod64_self {d : Int} (lower : -(2^63 : Int) ≤ d) (upper : d < 2^63) :
    d.bmod (2^64) = d := by
  rw [Int.bmod_eq_emod]
  have nonnegative : 0 ≤ d % (2^64 : Int) := Int.emod_nonneg _ (by decide); have below : d % (2^64 : Int) < (2^64 : Int) := Int.emod_lt _ (by decide)
  split <;> omega

private theorem sign_extend_i32_of_bounds {d : Int} (lower : -(2^31 : Int) ≤ d) (upper : d < 2^31) :
    (BitVec.ofInt 32 d).signExtend 64 = BitVec.ofInt 64 d := by
  apply BitVec.eq_of_toInt_eq
  rw [BitVec.toInt_signExtend, BitVec.toInt_ofInt, BitVec.toInt_ofInt]
  have h32 := bmod32_self lower upper; have h64 := bmod64_self (d := d) (by omega) (by omega)
  simp only [Nat.min_eq_right (by decide : 32 ≤ 64), h32, h64]

private theorem frame_slot_address_exact {rsp : Machine.Address} {slot : Nat} (slotBound : slot < 2^28) :
    frameSlotAddress (rsp - 8) slot = rsp - BitVec.ofNat 64 (16 + 8 * slot) := by
  unfold frameSlotAddress frameDisplacement
  have lower : -(2^31 : Int) ≤ -Int.ofNat ((slot + 1) * 8) := by simp only [Int.ofNat_eq_natCast, Int.natCast_mul, Int.natCast_add]; omega
  have upper : -Int.ofNat ((slot + 1) * 8) < (2^31 : Int) := by simp only [Int.ofNat_eq_natCast, Int.natCast_mul, Int.natCast_add]; omega
  rw [sign_extend_i32_of_bounds lower upper, BitVec.ofInt_neg]
  simp only [Int.ofNat_eq_natCast]
  have natCast : BitVec.ofInt 64 (↑((slot + 1) * 8) : Int) = BitVec.ofNat 64 ((slot + 1) * 8) := BitVec.ofInt_ofNat 64 _
  rw [natCast]
  have offset : (- (8 : BitVec 64)) + -BitVec.ofNat 64 ((slot + 1) * 8) =
      -BitVec.ofNat 64 (16 + 8 * slot) := by
    rw [← BitVec.sub_eq_add_neg, ← BitVec.neg_add]; congr 1
    change BitVec.ofNat 64 8 + BitVec.ofNat 64 ((slot + 1) * 8) = BitVec.ofNat 64 (16 + 8 * slot)
    rw [← BitVec.ofNat_add]; congr 1; omega
  simpa [BitVec.sub_eq_add_neg, BitVec.add_assoc, offset]

/- The flat memory model cannot infer that the recursive frame windows do not
   wrap into one another.  This is the single runtime layout fact needed by an
   authenticated expression frame; its slot count is computed from the
   authenticated function body, so no fixed maximum is hidden here. -/
structure DynamicFrameWindow (before : Machine.State) (slots : Nat) : Prop where
  slotAddressExact : ∀ slot, slot < slots →
    frameSlotAddress (before.registers rspRegister - 8) slot =
      before.registers rspRegister - BitVec.ofNat 64 (16 + 8 * slot)
  savedFrameDisjoint : ∀ slot, slot < slots → ∀ i : Fin 8, ∀ j : Fin 4,
    before.registers rspRegister - 8 + BitVec.ofNat 64 i.val ≠
      frameSlotAddress (before.registers rspRegister - 8) slot + BitVec.ofNat 64 j.val
  returnAddressDisjoint : ∀ slot, slot < slots → ∀ i : Fin 8, ∀ j : Fin 4,
    before.registers rspRegister + BitVec.ofNat 64 i.val ≠
      frameSlotAddress (before.registers rspRegister - 8) slot + BitVec.ofNat 64 j.val
  slotsSeparated : ∀ left right, left < slots → right < slots → left ≠ right →
    ∀ i j : Fin 4,
      frameSlotAddress (before.registers rspRegister - 8) left + BitVec.ofNat 64 i.val ≠
      frameSlotAddress (before.registers rspRegister - 8) right + BitVec.ofNat 64 j.val

private theorem neg_nat_add_toNat {d i : Nat} (dPos : 0 < d) (dBound : d < 2^64) (iBound : i < d) :
    ((-(BitVec.ofNat 64 d)) + BitVec.ofNat 64 i).toNat = 2^64 - d + i := by
  rw [BitVec.toNat_add, BitVec.toNat_neg, BitVec.toNat_ofNat, Nat.mod_eq_of_lt dBound]
  have negUpper : 2^64 - d < 2^64 := by omega
  rw [Nat.mod_eq_of_lt negUpper, BitVec.toNat_ofNat, Nat.mod_eq_of_lt (show i < 2^64 by omega), Nat.mod_eq_of_lt (show 2^64 - d + i < 2^64 by omega)]

private theorem offset_form {d i : Nat} (dPos : 0 < d) (dBound : d < 2^64) (iBound : i < d) :
    (-(BitVec.ofNat 64 d)) + BitVec.ofNat 64 i =
      BitVec.ofNat 64 (2^64 - d + i) := by
  apply BitVec.eq_of_toNat_eq
  rw [neg_nat_add_toNat dPos dBound iBound, BitVec.toNat_ofNat, Nat.mod_eq_of_lt (by omega)]

private theorem sub_offsets_ne {base : Machine.Address} {dl dr il ir : Nat}
    (dlPos : 0 < dl) (dlBound : dl < 2^64) (ilBound : il < dl) (drPos : 0 < dr)
    (drBound : dr < 2^64) (irBound : ir < dr) (different : 2^64 - dl + il ≠ 2^64 - dr + ir) :
    base - BitVec.ofNat 64 dl + BitVec.ofNat 64 il ≠ base - BitVec.ofNat 64 dr + BitVec.ofNat 64 ir := by
  intro h
  have hl := offset_form dlPos dlBound ilBound; have hr := offset_form drPos drBound irBound
  have h' : base + BitVec.ofNat 64 (2^64 - dl + il) = base + BitVec.ofNat 64 (2^64 - dr + ir) := by
    simpa only [BitVec.sub_eq_add_neg, BitVec.add_assoc, hl, hr] using h
  exact Machine.offset_ne _ _ _ (by omega) (by omega) different h'

private theorem offset_sub_ne {base : Machine.Address} {d i j : Nat}
    (dPos : 0 < d) (dBound : d < 2^64) (jBound : j < d) (iBound : i < 2^64)
    (different : i ≠ 2^64 - d + j) : base + BitVec.ofNat 64 i ≠ base - BitVec.ofNat 64 d + BitVec.ofNat 64 j := by
  intro h
  have hd := offset_form dPos dBound jBound
  have h' : base + BitVec.ofNat 64 i = base + BitVec.ofNat 64 (2^64 - d + j) := by
    simpa only [BitVec.sub_eq_add_neg, BitVec.add_assoc, hd] using h
  have rightBound : 2^64 - d + j < 2^64 := by omega
  exact Machine.offset_ne _ _ _ iBound rightBound different h'

theorem dynamic_frame_window_of_slots_le {before : Machine.State} {slots : Nat}
    (slotsBound : slots ≤ 2^28) : DynamicFrameWindow before slots := by
  have exactSlot : ∀ slot, slot < slots → frameSlotAddress (before.registers rspRegister - 8) slot =
      before.registers rspRegister - BitVec.ofNat 64 (16 + 8 * slot) := by
    intro slot bound; exact frame_slot_address_exact (by omega)
  have offset : ∀ slot, slot < slots → 0 < 16 + 8 * slot ∧ 16 + 8 * slot < 2^64 := by
    intro slot bound; constructor <;> omega
  refine { slotAddressExact := exactSlot, savedFrameDisjoint := ?_, returnAddressDisjoint := ?_, slotsSeparated := ?_ }
  · intro slot bound i j
    rw [exactSlot slot bound]
    exact sub_offsets_ne (base := before.registers rspRegister) (dl := 8) (dr := 16 + 8 * slot) (il := i.val) (ir := j.val)
      (by omega) (by omega) i.isLt (offset slot bound).1 (offset slot bound).2 (by omega)
      (by omega : 2^64 - 8 + i.val ≠ 2^64 - (16 + 8 * slot) + j.val)
  · intro slot bound i j
    rw [exactSlot slot bound]
    exact offset_sub_ne (base := before.registers rspRegister) (d := 16 + 8 * slot) (i := i.val) (j := j.val)
      (offset slot bound).1 (offset slot bound).2 (by omega) (by omega)
      (by omega : i.val ≠ 2^64 - (16 + 8 * slot) + j.val)
  · intro left right leftBound rightBound different i j
    rw [exactSlot left leftBound, exactSlot right rightBound]
    exact sub_offsets_ne (base := before.registers rspRegister) (dl := 16 + 8 * left) (dr := 16 + 8 * right) (il := i.val) (ir := j.val)
      (offset left leftBound).1 (offset left leftBound).2 (by omega) (offset right rightBound).1 (offset right rightBound).2 (by omega)
      (by omega : 2^64 - (16 + 8 * left) + i.val ≠
        2^64 - (16 + 8 * right) + j.val)

structure ProcessLayout (elf : List UInt8) (before : Machine.State)
    (functionLength : Nat) (displacement : BitVec 32) : Type where
  entryFunction : Function
  mapped : CodeAt before.memory base elf
  startup : StartupEvidence elf
  jump : JumpEvidence elf displacement
  ripAtEntry : before.rip = entry
  separation : ImageStackDisjoint elf before entryFunction
  targetOffset : Nat
  targetCodeOffset : 512 ≤ targetOffset
  targetBound : targetOffset + functionLength ≤ elf.length
  targetExact : jumpTarget displacement = base + BitVec.ofNat 64 targetOffset

theorem startup_stack {elf : List UInt8} {before : Machine.State}
    {functionLength : Nat} {displacement : BitVec 32}
    (layout : ProcessLayout elf before functionLength displacement) :
    StackDisjoint before := by
  intro index bound lane
  have sourceBound : 256 + index < elf.length := by
    have h := layout.startup.offsetBound
    omega
  have footprint := startupStackFootprint_mem layout.entryFunction
  have h8 := layout.separation (256 + index) sourceBound 8
    footprint.1 lane
  have h16 := layout.separation (256 + index) sourceBound 16
    footprint.2.1 lane
  constructor
  · change base + BitVec.ofNat 64 256 + BitVec.ofNat 64 index ≠ _
    rw [BitVec.add_assoc, ← BitVec.ofNat_add]
    exact h8
  · change base + BitVec.ofNat 64 256 + BitVec.ofNat 64 index ≠ _
    rw [BitVec.add_assoc, ← BitVec.ofNat_add]
    exact h16

theorem code_stack {elf : List UInt8} {before : Machine.State}
    {functionLength : Nat} {displacement : BitVec 32}
    (layout : ProcessLayout elf before functionLength displacement) :
    CodeStackDisjoint before displacement := by
  intro index bound lane
  have sourceBound : 512 + index < elf.length := by
    have h := layout.jump.offsetBound
    omega
  have footprint := startupStackFootprint_mem layout.entryFunction
  have h8 := layout.separation (512 + index) sourceBound 8
    footprint.1 lane
  have h16 := layout.separation (512 + index) sourceBound 16
    footprint.2.1 lane
  have h24 := layout.separation (512 + index) sourceBound 24
    footprint.2.2.1 lane
  constructor
  · change base + BitVec.ofNat 64 512 + BitVec.ofNat 64 index ≠ _
    rw [BitVec.add_assoc, ← BitVec.ofNat_add]
    exact h8
  constructor
  · change base + BitVec.ofNat 64 512 + BitVec.ofNat 64 index ≠ _
    rw [BitVec.add_assoc, ← BitVec.ofNat_add]
    exact h16
  · change base + BitVec.ofNat 64 512 + BitVec.ofNat 64 index ≠ _
    rw [BitVec.add_assoc, ← BitVec.ofNat_add]
    exact h24

theorem ProcessLayout.startupLayout {elf : List UInt8} {before : Machine.State}
    {functionLength : Nat} {displacement : BitVec 32}
    (layout : ProcessLayout elf before functionLength displacement) :
    StartupLayout before displacement := by
  exact {
    ripAtEntry := layout.ripAtEntry
    stackDisjoint := startup_stack layout
    codeStackDisjoint := code_stack layout
  }

def reachedState (before : Machine.State) (displacement : BitVec 32) : Machine.State :=
  (afterCall before).jump displacement (jumpBytes displacement).length

theorem reached_stack {elf : List UInt8} {before : Machine.State}
    {functionLength : Nat} {displacement : BitVec 32}
    (layout : ProcessLayout elf before functionLength displacement) :
    (reachedState before displacement).registers rspRegister =
      before.registers rspRegister - 24 := by
  have code := reaches_code layout.ripAtEntry
    (by simpa only [layout.ripAtEntry] using layout.startup.loaded layout.mapped)
    (startup_stack layout)
  change (afterCall before).registers StartupCheck.rsp =
    before.registers StartupCheck.rsp - 24
  exact code.2.2.1

theorem reached_return_slot {elf : List UInt8} {before : Machine.State}
    {functionLength : Nat} {displacement : BitVec 32}
    (layout : ProcessLayout elf before functionLength displacement) :
    Machine.read64 (reachedState before displacement).memory
      ((reachedState before displacement).registers rspRegister) =
        startupReturnAddress := by
  have rips := startup_rips layout.ripAtEntry
  change Machine.read64 (afterCall before).memory
      ((afterCall before).registers rspRegister) = startupReturnAddress
  change Machine.read64
      (Machine.write64 (afterClear before).memory
        ((afterClear before).registers rsp - 8)
        ((afterClear before).rip + BitVec.ofNat 64 callCode.length))
      ((afterClear before).registers rsp - 8) = startupReturnAddress
  rw [Machine.read64_write64]
  simp only [startupReturnAddress, rips.2.2.2.2.2]

theorem function_text {elf : List UInt8} {before : Machine.State}
    {functionLength : Nat} {displacement : BitVec 32}
    (layout : ProcessLayout elf before functionLength displacement) :
    FunctionTextDisjoint before (jumpTarget displacement) functionLength := by
  intro index bound lane
  have sourceBound : layout.targetOffset + index < elf.length := by
    have h := layout.targetBound
    omega
  have footprint := startupStackFootprint_mem layout.entryFunction
  have h32 := layout.separation (layout.targetOffset + index) sourceBound 32
    footprint.2.2.2.1 lane
  have h40 := layout.separation (layout.targetOffset + index) sourceBound 40
    footprint.2.2.2.2 lane
  have h32' : jumpTarget displacement + BitVec.ofNat 64 index ≠
      before.registers rspRegister - BitVec.ofNat 64 32 + BitVec.ofNat 64 lane.val := by
    rw [layout.targetExact]
    simpa only [BitVec.add_assoc, ← BitVec.ofNat_add] using h32
  have h40' : jumpTarget displacement + BitVec.ofNat 64 index ≠
      before.registers rspRegister - BitVec.ofNat 64 40 + BitVec.ofNat 64 lane.val := by
    rw [layout.targetExact]
    simpa only [BitVec.add_assoc, ← BitVec.ofNat_add] using h40
  constructor
  · rw [BitVec.sub_sub]
    change jumpTarget displacement + BitVec.ofNat 64 index ≠
      before.registers rspRegister - BitVec.ofNat 64 32 + BitVec.ofNat 64 lane.val
    exact h32'
  · rw [BitVec.sub_sub]
    change jumpTarget displacement + BitVec.ofNat 64 index ≠
      before.registers rspRegister - BitVec.ofNat 64 40 + BitVec.ofNat 64 lane.val
    exact h40'

theorem reached_textStack {elf : List UInt8} {before : Machine.State}
    {functionLength : Nat} {displacement : BitVec 32}
    (layout : ProcessLayout elf before functionLength displacement) :
    TextStackDisjoint (reachedState before displacement) (jumpTarget displacement)
      functionLength := by
  have hRsp := reached_stack layout
  have text := function_text layout
  intro index bound lane
  rw [hRsp]
  simpa only [rspRegister, StartupCheck.rsp] using text index bound lane

/- The same authenticated image separation, shifted by the CALL-created stack
   top, gives the selected function's complete dynamic frame window. -/
theorem reached_function_stack_disjoint
    {elf : List UInt8} {before : Machine.State}
    {functionLength : Nat} {displacement : BitVec 32}
    (layout : ProcessLayout elf before functionLength displacement) :
    ∀ index, index < functionLength → ∀ lane : Fin 8, ∀ slot,
      slot ∈ entryStackFootprint layout.entryFunction →
      jumpTarget displacement + BitVec.ofNat 64 index ≠
        (reachedState before displacement).registers rspRegister -
          BitVec.ofNat 64 slot + BitVec.ofNat 64 lane.val := by
  intro index bound lane slot slotMember
  have sourceBound : layout.targetOffset + index < elf.length := by
    have targetBound := layout.targetBound
    omega
  have shifted : 24 + slot ∈ startupStackFootprint layout.entryFunction := by
    unfold startupStackFootprint
    simp only [List.mem_append, List.mem_cons, List.mem_map]
    exact Or.inr ⟨slot, slotMember, rfl⟩
  have h := layout.separation (layout.targetOffset + index) sourceBound
    (24 + slot) shifted lane
  simp only [BitVec.ofNat_add] at h
  rw [reached_stack layout, layout.targetExact]
  rw [BitVec.sub_sub]
  change ImageCheck.lanius.base + BitVec.ofNat 64 layout.targetOffset +
      BitVec.ofNat 64 index ≠
    before.registers rspRegister -
      (BitVec.ofNat 64 24 + BitVec.ofNat 64 slot) +
      BitVec.ofNat 64 lane.val
  simpa only [StartupCheck.base, rspRegister, BitVec.sub_sub,
    BitVec.add_assoc] using h

/- The public result discharges the machine obligations expected by the
   function checker: actual RIP, the CALL-created stack top and return word,
   and text/stack separation for the selected authenticated span. -/
theorem reaches_function_layout {elf : List UInt8} {before : Machine.State}
    {functionLength : Nat} {displacement : BitVec 32}
    (layout : ProcessLayout elf before functionLength displacement) :
    Steps 8 before (reachedState before displacement) ∧
      (reachedState before displacement).rip = jumpTarget displacement ∧
      (reachedState before displacement).registers rspRegister =
        before.registers rspRegister - 24 ∧
      Machine.read64 (reachedState before displacement).memory
        ((reachedState before displacement).registers rspRegister) =
          startupReturnAddress ∧
      TextStackDisjoint (reachedState before displacement) (jumpTarget displacement)
        functionLength := by
  have path := StartupCheck.reaches_function layout.startup layout.jump layout.mapped
    layout.startupLayout
  have hRsp := reached_stack layout
  exact ⟨path.1, path.2, hRsp, reached_return_slot layout, reached_textStack layout⟩

end Lanius.X86.ProcessLayoutCheck
