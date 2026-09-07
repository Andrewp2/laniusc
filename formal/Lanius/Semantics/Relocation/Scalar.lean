import Lanius.Semantics.Relocation.State

namespace Lanius.Semantics.Relocation

open Lanius.Core

theorem scalarEqual (symbols : Core.Relocation.Symbols) (left right : Value) :
    Semantics.scalarEqual (Core.Relocation.value symbols left) (Core.Relocation.value symbols right) =
      Semantics.scalarEqual left right := by
  cases left <;> cases right <;> rfl

theorem integerIndex (symbols : Core.Relocation.Symbols) (v : Value) :
    Semantics.integerIndex (Core.Relocation.value symbols v) = Semantics.integerIndex v := by
  cases v <;> rfl

theorem unary (symbols : Core.Relocation.Symbols) (target : Target) (op : UnaryOp) (v : Value) :
    evalUnaryValue target op (Core.Relocation.value symbols v) =
      (evalUnaryValue target op v).map (Core.Relocation.value symbols) := by
  cases op <;> cases v <;> rfl

theorem cast (symbols : Core.Relocation.Symbols) (target : Target) (destination : ScalarTy) (v : Value) :
    evalScalarCast target destination (Core.Relocation.value symbols v) =
      (evalScalarCast target destination v).map (Core.Relocation.value symbols) := by
  cases destination <;> cases v <;> rfl

private theorem signed (symbols : Core.Relocation.Symbols) (target : Target)
    (op : BinaryOp) (type : SignedIntTy) (left right : Int) :
    (evalSignedBinary target op type left right).map (Core.Relocation.value symbols) =
      evalSignedBinary target op type left right := by
  cases op <;> simp only [evalSignedBinary]
  all_goals repeat first | rfl | split

private theorem unsigned (symbols : Core.Relocation.Symbols) (target : Target)
    (op : BinaryOp) (type : UnsignedIntTy) (left right : Nat) :
    (evalUnsignedBinary target op type left right).map (Core.Relocation.value symbols) =
      evalUnsignedBinary target op type left right := by
  cases op <;> simp only [evalUnsignedBinary]
  all_goals repeat first | rfl | split

private theorem float32 (symbols : Core.Relocation.Symbols) (op : BinaryOp) (left right : UInt32) :
    (evalF32Binary op left right).map (Core.Relocation.value symbols) = evalF32Binary op left right := by
  cases op <;> rfl

private theorem float64 (symbols : Core.Relocation.Symbols) (op : BinaryOp) (left right : UInt64) :
    (evalF64Binary op left right).map (Core.Relocation.value symbols) = evalF64Binary op left right := by
  cases op <;> rfl

private theorem character (symbols : Core.Relocation.Symbols) (op : BinaryOp) (left right : UInt32) :
    (evalCharBinary op left right).map (Core.Relocation.value symbols) = evalCharBinary op left right := by
  cases op <;> simp only [evalCharBinary]
  all_goals repeat first | rfl | split

private theorem binary_result (symbols : Core.Relocation.Symbols) (target : Target)
    (op : BinaryOp) (left right : Value) :
    (evalBinaryValue target op left right).map (Core.Relocation.value symbols) =
      evalBinaryValue target op left right := by
  unfold evalBinaryValue
  split
  all_goals repeat first
    | solve | simp only [signed, unsigned, float32, float64, character]
    | rfl
    | split

theorem binary (symbols : Core.Relocation.Symbols) (target : Target)
    (op : BinaryOp) (left right : Value) :
    evalBinaryValue target op (Core.Relocation.value symbols left) (Core.Relocation.value symbols right) =
      (evalBinaryValue target op left right).map (Core.Relocation.value symbols) := by
  rw [binary_result]
  cases left <;> cases right <;> first | rfl | cases op <;> rfl

theorem assignment (symbols : Core.Relocation.Symbols) (target : Target)
    (op : AssignOp) (current : Option Value) (right : Value) :
    evalAssignValue target op (current.map (Core.Relocation.value symbols))
        (Core.Relocation.value symbols right) =
      (evalAssignValue target op current right).map (Core.Relocation.value symbols) := by
  simp only [evalAssignValue]
  cases assignOpBinary? op with
  | none => rfl
  | some op => cases current <;> simp only [Option.map, binary] <;> rfl

end Lanius.Semantics.Relocation
