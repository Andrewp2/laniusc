import Lanius.Extraction.OutputPacking.Read

namespace Lanius.Extraction.OutputPacking

open Lanius Lanius.Core Lanius.Semantics

def nibbleAt (word : BitVec 32) (lane : Fin 8) : BitVec 4 :=
  word.extractLsb' (lane.val * 4) 4

theorem nibbleAt_shift_mask (word : BitVec 32) (lane : Fin 8) :
    word.sshiftRight (lane.val * 4) &&& 15 = (nibbleAt word lane).setWidth 32 := by
  apply BitVec.eq_of_getLsbD_eq
  intro bit
  have mask : (15 : BitVec 32) = (BitVec.allOnes 4).setWidth 32 := rfl
  rw [mask]
  simp only [BitVec.getLsbD_and, BitVec.getLsbD_setWidth,
    BitVec.getLsbD_allOnes, BitVec.getLsbD_sshiftRight, nibbleAt, BitVec.getLsbD_extractLsb']
  by_cases inside : bit < 4
  · have total : lane.val * 4 + bit < 32 := by omega
    simp only [inside, total, show bit < 32 by omega, show ¬ 32 ≤ bit by omega]
    simp
  · simp [inside]

theorem nibbleAt_toInt (word : BitVec 32) (lane : Fin 8) :
    ((nibbleAt word lane).setWidth 32).toInt = (nibbleAt word lane).toNat := by
  rw [BitVec.toInt_setWidth]
  have bound := (nibbleAt word lane).isLt
  apply Int.bmod_eq_of_le <;> omega

theorem readNibbleExpression (word : BitVec 32) (lane : Fin 8)
    (target : program.target = .x86_64)
    (read : StableExpr readFuel program state wordExpr (.signed .i32 word.toInt) state)
    (shift : StableExpr shiftFuel program state shiftExpr (.signed .i32 (lane.val * 4 : Nat)) state)
    (mask : StableExpr maskFuel program state maskExpr (.signed .i32 15) state) :
    StableExpr (max (max readFuel shiftFuel + 1) maskFuel + 1) program state
      (.binary .bitAnd (.binary .shiftRight wordExpr shiftExpr) maskExpr)
      (.signed .i32 (nibbleAt word lane).toNat) state := by
  have shifted := evalSignedBinary_shiftRight_i32_x86_word word.toInt lane.val lane.isLt
  rw [Nat.mul_comm 4 lane.val] at shifted
  rw [← BitVec.toInt_sshiftRight, wrapSigned_bmod, ← BitVec.toInt_ofInt,
    BitVec.ofInt_toInt] at shifted
  have shiftOp : evalBinaryValue program.target .shiftRight
      (.signed .i32 word.toInt) (.signed .i32 (lane.val * 4 : Nat)) =
      .ok (.signed .i32 (word.sshiftRight (lane.val * 4)).toInt) := by
    simpa only [evalBinaryValue, target, BEq.rfl, ↓reduceIte, Int.ofNat_eq_natCast] using shifted
  apply StableExpr.binary (StableExpr.binary read shift (by decide) shiftOp) mask (by decide)
  simpa only [evalBinaryValue, target, BEq.rfl, ↓reduceIte,
    show (15 : BitVec 32).toInt = 15 by decide, nibbleAt_shift_mask, nibbleAt_toInt] using
    evalSignedBinary_i32_and (word.sshiftRight (lane.val * 4)) 15

end Lanius.Extraction.OutputPacking
