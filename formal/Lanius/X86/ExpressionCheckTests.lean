import Lanius.X86.ExpressionCheck

namespace Lanius.X86.ExpressionCheckTests

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.ExpressionCheck

private def two : BitVec 32 := BitVec.ofNat 32 2
private def three : BitVec 32 := BitVec.ofNat 32 3
private def four : BitVec 32 := BitVec.ofNat 32 4

private def literalTwo : Core.Expr := .value (.signed .i32 2)
private def literalThree : Core.Expr := .value (.signed .i32 3)
private def literalFour : Core.Expr := .value (.signed .i32 4)
private def addTwoThree : Core.Expr := .binary .add literalTwo literalThree
private def multiplyTwoThree : Core.Expr := .binary .multiply literalTwo literalThree
private def nestedAdd : Core.Expr := .binary .add addTwoThree literalFour
private def divideTwoThree : Core.Expr := .binary .divide literalTwo literalThree
private def trueLiteral : Core.Expr := .value (.boolean true)
private def boolAdd : Core.Expr := .binary .add trueLiteral trueLiteral
private def trueBytes := immediateBytes .w32 ScalarValidator.resultRegister (BitVec.ofNat 32 1) 0
private def falseBytes := immediateBytes .w32 ScalarValidator.resultRegister (BitVec.ofNat 32 0) 0

#eval (checkBody? literalTwo
    (immediateBytes .w32 ScalarValidator.resultRegister two 0)).isSome
#eval (checkBody? addTwoThree
    (ScalarValidator.binaryLiteralBodyBytes .add two three)).isSome
#eval (checkBody? multiplyTwoThree
    (immediateBytes .w32 ScalarValidator.resultRegister two 0 ++ frameStoreBytes 0 ++
      immediateBytes .w32 ScalarValidator.resultRegister three 0 ++ frameMultiplyBytes 0)).isSome
#eval (checkBody? nestedAdd
    ((immediateBytes .w32 ScalarValidator.resultRegister two 0) ++
      frameStoreBytes 0 ++
      (immediateBytes .w32 ScalarValidator.resultRegister three 0) ++
      frameAluBytes 0 .add ++
      frameStoreBytes 1 ++
      (immediateBytes .w32 ScalarValidator.resultRegister four 0) ++
      frameAluBytes 1 .add)).isSome
#eval (checkBody? divideTwoThree []).isSome
#eval (checkBody? trueLiteral
    (immediateBytes .w32 ScalarValidator.resultRegister (BitVec.ofNat 32 1) 0)).isSome

example : (checkBody? literalTwo
    (immediateBytes .w32 ScalarValidator.resultRegister two 0)).isSome := by
  decide

example : (checkBody? addTwoThree
    (ScalarValidator.binaryLiteralBodyBytes .add two three)).isSome := by
  decide

example : (checkBody? multiplyTwoThree
    (immediateBytes .w32 ScalarValidator.resultRegister two 0 ++ frameStoreBytes 0 ++
      immediateBytes .w32 ScalarValidator.resultRegister three 0 ++ frameMultiplyBytes 0)).isSome := by
  decide

example : (checkBody? nestedAdd
    ((immediateBytes .w32 ScalarValidator.resultRegister two 0) ++
      frameStoreBytes 0 ++
      (immediateBytes .w32 ScalarValidator.resultRegister three 0) ++
      frameAluBytes 0 .add ++
      frameStoreBytes 1 ++
      (immediateBytes .w32 ScalarValidator.resultRegister four 0) ++
      frameAluBytes 1 .add)).isSome := by
  decide

example : (checkBody? divideTwoThree []).isNone := by
  decide

example : (checkBody? trueLiteral
    (immediateBytes .w32 ScalarValidator.resultRegister (BitVec.ofNat 32 1) 0)).isSome := by
  decide

example : (checkShape? boolAdd).isNone := by
  decide

example : (checkBody? addTwoThree
    (ScalarValidator.binaryLiteralBodyBytes .add two three |>.set 0 0)).isNone := by
  decide

example {source : Core.Expr} {shape : Shape source} {base upper : Nat}
    {remainder : List UInt8} {before after : Machine.State}
    (result : RecursiveResult shape base upper remainder before after) :
    ∀ address bytes, CodeAt before.memory address bytes →
      (∀ index, index < bytes.length → ∀ slot,
        base ≤ slot → slot < base + shape.allocations → ∀ lane : Fin 4,
          address + BitVec.ofNat 64 index ≠
            frameSlotAddress (before.registers rbpRegister) slot +
              BitVec.ofNat 64 lane.val) →
      CodeAt after.memory address bytes :=
  result.preserveCodeAt

example : (checkBody? (.unary .negate literalTwo)
    (immediateBytes .w32 ScalarValidator.resultRegister two 0 ++ unaryBytes .negate)).isSome := by
  decide

example : (checkBody? (.unary .positive literalTwo)
    (immediateBytes .w32 ScalarValidator.resultRegister two 0)).isSome := by
  decide

example : (checkBody? (.unary .logicalNot trueLiteral)
    (immediateBytes .w32 ScalarValidator.resultRegister (BitVec.ofNat 32 1) 0 ++
      unaryBytes .logicalNot)).isSome := by
  decide

example : (checkShape? (.unary .negate trueLiteral)).isNone := by
  decide

example : Shape.allocations
    (Shape.binary .add (.alu .add) literalTwo literalThree rfl
      (Shape.lit (.i32 two) (.signed .i32 2) (by
        simp [LiteralReturn.Literal.value, two]))
      (Shape.lit (.i32 three) (.signed .i32 3) (by
        simp [LiteralReturn.Literal.value, three]))) = 1 := by
  rfl

example {before : Machine.State} {bytes : List UInt8}
    (invariant : FrameCodeInvariant before 0 4 bytes) :
    ∀ left right, 1 ≤ left → left < 3 → 1 ≤ right → right < 3 →
      left ≠ right → ∀ i j : Fin 4,
        frameSlotAddress (before.registers rbpRegister) left +
            BitVec.ofNat 64 i.val ≠
          frameSlotAddress (before.registers rbpRegister) right +
            BitVec.ofNat 64 j.val := by
  have restricted : FrameCodeInvariant before 1 3 bytes :=
    FrameCodeInvariant.restrict invariant (by omega) (by omega)
  exact restricted.slotsSeparated

example {memory : Memory} {address : Address} {suffix : List UInt8}
    (loaded : CodeAt memory address
      (conditionalBytes trueBytes falseBytes ++ conditionalBytes falseBytes trueBytes ++ suffix)) :
    CodeAt memory (address + BitVec.ofNat 64 (conditionalPrefix trueBytes).length)
        (trueBytes ++ jumpBytes (BitVec.ofNat 32 falseBytes.length) ++ falseBytes ++
          conditionalBytes falseBytes trueBytes ++ suffix) ∧
      CodeAt memory (address + BitVec.ofNat 64 (conditionalPrefix trueBytes).length +
        (BitVec.ofNat 32 (trueBytes.length + 5)).signExtend 64)
        (falseBytes ++ conditionalBytes falseBytes trueBytes ++ suffix) := by
  exact conditional_code_targets_suffix (by decide) (by decide) loaded

example {memory : Memory} {address : Address} {suffix : List UInt8}
    (loaded : CodeAt memory address
      (conditionalBytes falseBytes trueBytes ++ conditionalBytes trueBytes falseBytes ++ suffix)) :
    CodeAt memory (address + BitVec.ofNat 64 (conditionalPrefix falseBytes).length)
        (falseBytes ++ jumpBytes (BitVec.ofNat 32 trueBytes.length) ++ trueBytes ++
          conditionalBytes trueBytes falseBytes ++ suffix) ∧
      CodeAt memory (address + BitVec.ofNat 64 (conditionalPrefix falseBytes).length +
        (BitVec.ofNat 32 (falseBytes.length + 5)).signExtend 64)
        (trueBytes ++ conditionalBytes trueBytes falseBytes ++ suffix) := by
  exact conditional_code_targets_suffix (by decide) (by decide) loaded

end Lanius.X86.ExpressionCheckTests
