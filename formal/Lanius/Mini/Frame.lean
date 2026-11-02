module

public import Lanius.Mini.Bytes
public import Lanius.Mini.Compiler.P.larger
import all Lanius.Mini.Compiler.P.BinOp_folds
import all Lanius.Mini.Compiler.P.DivOp_size
import all Lanius.Mini.Compiler.P.Expr_agrees
import all Lanius.Mini.Compiler.P.FArith_opcode
import all Lanius.Mini.Compiler.P.FloatTy_rex
import all Lanius.Mini.Compiler.P.Instr_pieces
import all Lanius.Mini.Compiler.P.Lists_empty
import all Lanius.Mini.Compiler.P.SrcExpr_guard
import all Lanius.Mini.Compiler.P.SrcType_size
import all Lanius.Mini.Compiler.P.Stmt_kills
import all Lanius.Mini.Compiler.P.UintTy_half
import all Lanius.Mini.Compiler.P.UintTy_isWide
import all Lanius.Mini.Compiler.P.UintTy_mask
import all Lanius.Mini.Compiler.P.Word_compute
import all Lanius.Mini.Compiler.P.Word_narrows
import all Lanius.Mini.Compiler.P.applyGuard
import all Lanius.Mini.Compiler.P.arithShiftRight
import all Lanius.Mini.Compiler.P.arithUint
import all Lanius.Mini.Compiler.P.arities
import all Lanius.Mini.Compiler.P.armBodyScope
import all Lanius.Mini.Compiler.P.armPayload
import all Lanius.Mini.Compiler.P.armScope
import all Lanius.Mini.Compiler.P.assignAgrees
import all Lanius.Mini.Compiler.P.assignFrom
import all Lanius.Mini.Compiler.P.binaryConstant
import all Lanius.Mini.Compiler.P.callAgrees
import all Lanius.Mini.Compiler.P.codeSize
import all Lanius.Mini.Compiler.P.compileArgs
import all Lanius.Mini.Compiler.P.compileModules
import all Lanius.Mini.Compiler.P.compileOr
import all Lanius.Mini.Compiler.P.compileSource
import all Lanius.Mini.Compiler.P.conjunction
import all Lanius.Mini.Compiler.P.consArgs
import all Lanius.Mini.Compiler.P.declareFuncs
import all Lanius.Mini.Compiler.P.declareProgram
import all Lanius.Mini.Compiler.P.elementAddress
import all Lanius.Mini.Compiler.P.elementBase
import all Lanius.Mini.Compiler.P.enumVariants
import all Lanius.Mini.Compiler.P.equality
import all Lanius.Mini.Compiler.P.evalDivide
import all Lanius.Mini.Compiler.P.evalDivideSint
import all Lanius.Mini.Compiler.P.evalNot
import all Lanius.Mini.Compiler.P.evalSame
import all Lanius.Mini.Compiler.P.extentAfter
import all Lanius.Mini.Compiler.P.floatApply
import all Lanius.Mini.Compiler.P.guardAnd
import all Lanius.Mini.Compiler.P.hostRandomCode
import all Lanius.Mini.Compiler.P.imageLimit
import all Lanius.Mini.Compiler.P.importOk
import all Lanius.Mini.Compiler.P.importsOk
import all Lanius.Mini.Compiler.P.indexOf
import all Lanius.Mini.Compiler.P.iteThen
import all Lanius.Mini.Compiler.P.killShared
import all Lanius.Mini.Compiler.P.larger
import all Lanius.Mini.Compiler.P.leftTrue
import all Lanius.Mini.Compiler.P.loadAtBytes
import all Lanius.Mini.Compiler.P.longer
import all Lanius.Mini.Compiler.P.lowerAddress
import all Lanius.Mini.Compiler.P.lowerApply
import all Lanius.Mini.Compiler.P.lowerBody
import all Lanius.Mini.Compiler.P.lowerCallSig
import all Lanius.Mini.Compiler.P.lowerLoadType
import all Lanius.Mini.Compiler.P.lowerLocal
import all Lanius.Mini.Compiler.P.lowerReturn
import all Lanius.Mini.Compiler.P.lowerSetCallArgs
import all Lanius.Mini.Compiler.P.lowerSetValues
import all Lanius.Mini.Compiler.P.lowerShift
import all Lanius.Mini.Compiler.P.lowerSlice
import all Lanius.Mini.Compiler.P.lowerTagged
import all Lanius.Mini.Compiler.P.matchDst
import all Lanius.Mini.Compiler.P.matchVariants
import all Lanius.Mini.Compiler.P.moduleExports
import all Lanius.Mini.Compiler.P.moduleFirsts
import all Lanius.Mini.Compiler.P.modulesOk
import all Lanius.Mini.Compiler.P.optimizeIte
import all Lanius.Mini.Compiler.P.optimizeLeft
import all Lanius.Mini.Compiler.P.optimizeNeg
import all Lanius.Mini.Compiler.P.packRound
import all Lanius.Mini.Compiler.P.render
import all Lanius.Mini.Compiler.P.repeatType
import all Lanius.Mini.Compiler.P.shortCircuit
import all Lanius.Mini.Compiler.P.withBudget
import all Lanius.Mini.Compiler.P.funcNeeds
import all Lanius.Mini.Compiler.P.sintToUint
import all Lanius.Mini.Compiler.P.storeArray
import all Lanius.Mini.Compiler.P.arrayCallSig
import all Lanius.Mini.Compiler.P.bindingBytes
import all Lanius.Mini.Compiler.P.needRound
import all Lanius.Mini.Compiler.P.needsAfter
import all Lanius.Mini.Compiler.P.storeEvalWord
import all Lanius.Mini.Compiler.P.storeType
import all Lanius.Mini.Compiler.P.storeWordElement
import all Lanius.Mini.Compiler.P.structFields
import all Lanius.Mini.Compiler.P.substAll
import all Lanius.Mini.Compiler.P.usizeWidth
import all Lanius.Mini.Compiler.P.widthOf
import all Lanius.Mini.Compiler.P.wordElement
import all Lanius.Mini.Compiler.P.wordStride
import all Lanius.Mini.Compiler.P.wordWidth
import all Lanius.Mini.Compiler.Types
public import Lanius.Mini.Compiler.P.loadAtBytes

@[expose] public section
/-! Stack layout arithmetic. An activation whose return address is at `top`
has rbp at `top - 8`; slot `k` is the four bytes `8 * k + 16` below `top`.
Every stack address the compiled code touches is `top - d` for a small depth
`d`, so separation facts reduce to arithmetic on depths. -/

namespace Lanius.Mini
open Lanius.X86.Machine

private theorem bmod32_self {d : Int} (lower : -(2^31 : Int) ≤ d) (upper : d < 2^31) :
    d.bmod (2^32) = d := by
  rw [Int.bmod_eq_emod]
  have := Int.emod_nonneg d (show (2^32 : Int) ≠ 0 by decide)
  have := Int.emod_lt_of_pos d (show (0 : Int) < 2^32 by decide)
  split <;> omega

private theorem bmod64_self {d : Int} (lower : -(2^63 : Int) ≤ d) (upper : d < 2^63) :
    d.bmod (2^64) = d := by
  rw [Int.bmod_eq_emod]
  have := Int.emod_nonneg d (show (2^64 : Int) ≠ 0 by decide)
  have := Int.emod_lt_of_pos d (show (0 : Int) < 2^64 by decide)
  split <;> omega

/-- Slots this close to rbp have 32-bit displacements. -/
def slotLimit : Nat := 2 ^ 27

theorem slotAddress_eq (rbp : BitVec 64) {slot : Nat} (bound : slot < slotLimit) :
    frameSlotAddress rbp slot = rbp - BitVec.ofNat 64 ((slot + 1) * 8) := by
  unfold frameSlotAddress frameDisplacement slotLimit at *
  have lower : -(2^31 : Int) ≤ -Int.ofNat ((slot + 1) * 8) := by simp only [Int.ofNat_eq_natCast]; omega
  have upper : -Int.ofNat ((slot + 1) * 8) < (2^31 : Int) := by simp only [Int.ofNat_eq_natCast]; omega
  have extended : (BitVec.ofInt 32 (-Int.ofNat ((slot + 1) * 8))).signExtend 64 =
      BitVec.ofInt 64 (-Int.ofNat ((slot + 1) * 8)) := by
    apply BitVec.eq_of_toInt_eq
    rw [BitVec.toInt_signExtend, BitVec.toInt_ofInt, BitVec.toInt_ofInt]
    simp only [Nat.min_eq_right (by decide : 32 ≤ 64), bmod32_self lower upper,
      bmod64_self (d := -Int.ofNat ((slot + 1) * 8)) (by omega) (by omega)]
  rw [extended, BitVec.ofInt_neg, Int.ofNat_eq_natCast, BitVec.ofInt_natCast, BitVec.sub_eq_add_neg]

/-- Byte `lane` of slot `slot`. -/
theorem slot_lane (top : BitVec 64) {slot : Nat} (bound : slot < slotLimit) (lane : Nat) (small : lane < 8) :
    frameSlotAddress (top - 8) slot + BitVec.ofNat 64 lane = top - BitVec.ofNat 64 (8 * slot + 16 - lane) := by
  rw [slotAddress_eq _ bound]
  unfold slotLimit at bound
  bv_omega

theorem slot_eq (top : BitVec 64) {slot : Nat} (bound : slot < slotLimit) :
    frameSlotAddress (top - 8) slot = top - BitVec.ofNat 64 (8 * slot + 16) := by
  simpa using slot_lane top bound 0 (by decide)

theorem depth_lane (top : BitVec 64) (d lane : Nat) (small : lane ≤ d) :
    top - BitVec.ofNat 64 d + BitVec.ofNat 64 lane = top - BitVec.ofNat 64 (d - lane) := by
  bv_omega

theorem depth_ne (top : BitVec 64) {d e : Nat} (different : d ≠ e) (dBound : d < 2 ^ 64) (eBound : e < 2 ^ 64) :
    top - BitVec.ofNat 64 d ≠ top - BitVec.ofNat 64 e := by
  bv_omega

/-- `address` is one of the `window` bytes just below `top`. -/
def Below (top : BitVec 64) (window : Nat) (address : BitVec 64) : Prop :=
  0 < (top - address).toNat ∧ (top - address).toNat ≤ window

theorem below_depth (top : BitVec 64) {window d : Nat} (positive : 0 < d) (within : d ≤ window)
    (bound : d < 2 ^ 64) : Below top window (top - BitVec.ofNat 64 d) := by
  unfold Below
  constructor <;> bv_omega

/-- Addresses at or above `top - e` are not below it. -/
theorem not_below_above (top : BitVec 64) {window d e : Nat} (above : d ≤ e) (bound : e + window < 2 ^ 64) :
    ¬Below (top - BitVec.ofNat 64 e) window (top - BitVec.ofNat 64 d) := by
  unfold Below
  intro ⟨positive, within⟩
  bv_omega

/-- The return address and whatever is above it are not below `top`. -/
theorem not_below_return (top : BitVec 64) {window lane : Nat} (small : lane < 8) (bound : window + 8 < 2 ^ 64) :
    ¬Below top window (top + BitVec.ofNat 64 lane) := by
  unfold Below
  intro ⟨positive, within⟩
  bv_omega

/-- A window `e` bytes down inside a bigger one. -/
theorem Below.shift {top address : BitVec 64} {window e : Nat}
    (below : Below (top - BitVec.ofNat 64 e) window address) (bound : e + window < 2 ^ 64) :
    Below top (e + window) address := by
  unfold Below at *
  obtain ⟨positive, within⟩ := below
  constructor <;> bv_omega

theorem Below.mono {top address : BitVec 64} {window window' : Nat} (below : Below top window address)
    (larger : window ≤ window') : Below top window' address :=
  ⟨below.1, Nat.le_trans below.2 larger⟩

theorem ne_of_below {region : BitVec 64 → Prop} {a b : BitVec 64} (outside : ¬region a) (inside : region b) :
    a ≠ b := by
  rintro rfl
  exact outside inside

theorem frameBytes_slots (slots : Nat) : 8 * slots ≤ frameBytes slots := by
  unfold frameBytes; omega

theorem frameBytes_mul (slots : Nat) : frameBytes slots = frameBytes slots / 8 * 8 := by
  unfold frameBytes; omega

theorem frameBytes_le (slots : Nat) : frameBytes slots ≤ 8 * slots + 8 := by
  unfold frameBytes; omega

/-! Stores and the bytes they leave alone. -/

theorem write32_outside {memory : Memory} {address other : BitVec 64} {value : BitVec 32}
    (apart : ∀ lane : Fin 4, other ≠ address + BitVec.ofNat 64 lane.val) :
    write32 memory address value other = memory other := by
  apply write32_frame
  refine ⟨?_, ?_, ?_, ?_⟩
  · simpa using apart ⟨0, by decide⟩
  · simpa using apart ⟨1, by decide⟩
  · simpa using apart ⟨2, by decide⟩
  · simpa using apart ⟨3, by decide⟩

theorem read32_write64_frame (memory : Memory) (address other : BitVec 64) (value : BitVec 64)
    (disjoint : ∀ i : Fin 4, ∀ j : Fin 8, other + BitVec.ofNat 64 i.val ≠ address + BitVec.ofNat 64 j.val) :
    read32 (write64 memory address value) other = read32 memory other := by
  apply read32_congr
  intro lane
  exact write64_frame _ _ _ _ (disjoint lane)

end Lanius.Mini
