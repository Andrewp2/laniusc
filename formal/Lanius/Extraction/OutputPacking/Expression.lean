import Lanius.Extraction.OutputPacking.Byte
import Lanius.Semantics.Bitwise
import Lanius.Semantics.Stable

namespace Lanius.Extraction.OutputPacking

open Lanius Lanius.Core Lanius.Semantics

/-- The packed-byte writer's update expression, before the store. Operands
    remain ordinary Core expressions; no typing derivation is reconstructed. -/
def byteExpression (word mask byte shift : Expr) : Expr :=
  .binary .bitOr
    (.binary .bitAnd word
      (.binary .bitXor mask (.unary .negate (.value (.signed .i32 1)))))
    (.binary .shiftLeft byte shift)

/-- A compositional arithmetic rule, not a contract for the entire writer.
    The caller must establish the operand reads and the subsequent store. -/
theorem byteExpression_evaluates
    (word : BitVec 32) (lane : Fin 4) (byte : BitVec 8)
    {program : Program} {state : State} {wordExpr maskExpr byteExpr shiftExpr : Expr}
    (target : program.target = .x86_64)
    (wordRun : StableExpr 2 program state wordExpr (.signed .i32 word.toInt) state)
    (maskRun : StableExpr 2 program state maskExpr
      (.signed .i32 ((255 : BitVec 32) <<< (lane.val * 8)).toInt) state)
    (byteRun : StableExpr 2 program state byteExpr
      (.signed .i32 (byte.setWidth 32).toInt) state)
    (shiftRun : StableExpr 2 program state shiftExpr (.signed .i32 (Int.ofNat (lane.val * 8))) state) :
    StableExpr 5 program state (byteExpression wordExpr maskExpr byteExpr shiftExpr)
      (.signed .i32 (replaceByte word lane byte).toInt) state := by
  have ones : StableExpr 2 program state (.unary .negate (.value (.signed .i32 1)))
      (.signed .i32 (-1)) state := by
    exact StableExpr.unary StableExpr.value (by
      simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits])
  have inverse := StableExpr.binary maskRun ones (by decide :
      BinaryOp.bitXor ≠ .logicalAnd ∧ BinaryOp.bitXor ≠ .logicalOr)
    (by simpa only [evalBinaryValue, target, BEq.rfl, ↓reduceIte,
        show (-1 : BitVec 32).toInt = -1 by decide] using
      evalSignedBinary_i32_xor ((255 : BitVec 32) <<< (lane.val * 8)) (-1))
  have cleared := StableExpr.binary wordRun inverse (by decide :
      BinaryOp.bitAnd ≠ .logicalAnd ∧ BinaryOp.bitAnd ≠ .logicalOr)
    (by simpa only [evalBinaryValue, target, BEq.rfl, ↓reduceIte] using
      evalSignedBinary_i32_and word (((255 : BitVec 32) <<< (lane.val * 8)) ^^^ (-1)))
  have shifted := StableExpr.binary byteRun shiftRun (by decide :
      BinaryOp.shiftLeft ≠ .logicalAnd ∧ BinaryOp.shiftLeft ≠ .logicalOr)
    (by simpa only [evalBinaryValue, target, BEq.rfl, ↓reduceIte,
        Int.ofNat_eq_natCast] using
      evalSignedBinary_i32_shiftLeft (byte.setWidth 32) (lane.val * 8) (by omega))
  exact StableExpr.binary cleared shifted (by decide) (by
    simpa only [evalBinaryValue, target, replaceByte, BEq.rfl, ↓reduceIte] using
      evalSignedBinary_i32_or (word &&& (((255 : BitVec 32) <<< (lane.val * 8)) ^^^ (-1)))
        (byte.setWidth 32 <<< (lane.val * 8)))

end Lanius.Extraction.OutputPacking
