import Lanius.Semantics.CellRenaming.State

namespace Lanius.Semantics.CellRenaming

open Lanius.Core

theorem scalarEqual (rename : CellId → CellId) (left right : Value) :
    Semantics.scalarEqual (value rename left) (value rename right) =
      Semantics.scalarEqual left right := by
  cases left <;> cases right <;> rfl

theorem integerIndex (rename : CellId → CellId) (v : Value) :
    Semantics.integerIndex (value rename v) = Semantics.integerIndex v := by
  cases v <;> rfl

theorem unary (rename : CellId → CellId) (target : Target) (op : UnaryOp) (v : Value) :
    evalUnaryValue target op (value rename v) =
      (evalUnaryValue target op v).map (value rename) := by
  cases op <;> cases v <;> rfl

theorem cast (rename : CellId → CellId) (target : Target) (destination : ScalarTy) (v : Value) :
    evalScalarCast target destination (value rename v) =
      (evalScalarCast target destination v).map (value rename) := by
  cases destination <;> cases v <;> rfl

private theorem signed (rename : CellId → CellId) (target : Target)
    (op : BinaryOp) (type : SignedIntTy) (left right : Int) :
    (evalSignedBinary target op type left right).map (value rename) =
      evalSignedBinary target op type left right := by
  cases op <;> simp only [evalSignedBinary]
  all_goals repeat first | rfl | split

private theorem unsigned (rename : CellId → CellId) (target : Target)
    (op : BinaryOp) (type : UnsignedIntTy) (left right : Nat) :
    (evalUnsignedBinary target op type left right).map (value rename) =
      evalUnsignedBinary target op type left right := by
  cases op <;> simp only [evalUnsignedBinary]
  all_goals repeat first | rfl | split

private theorem float32 (rename : CellId → CellId) (op : BinaryOp) (left right : UInt32) :
    (evalF32Binary op left right).map (value rename) = evalF32Binary op left right := by
  cases op <;> rfl

private theorem float64 (rename : CellId → CellId) (op : BinaryOp) (left right : UInt64) :
    (evalF64Binary op left right).map (value rename) = evalF64Binary op left right := by
  cases op <;> rfl

private theorem character (rename : CellId → CellId) (op : BinaryOp) (left right : UInt32) :
    (evalCharBinary op left right).map (value rename) = evalCharBinary op left right := by
  cases op <;> simp only [evalCharBinary]
  all_goals repeat first | rfl | split

private theorem binary_result (rename : CellId → CellId) (target : Target)
    (op : BinaryOp) (left right : Value) :
    (evalBinaryValue target op left right).map (value rename) =
      evalBinaryValue target op left right := by
  unfold evalBinaryValue
  split
  all_goals repeat first
    | solve | simp only [signed, unsigned, float32, float64, character]
    | rfl
    | split

theorem binary (rename : CellId → CellId) (target : Target)
    (op : BinaryOp) (left right : Value) :
    evalBinaryValue target op (value rename left) (value rename right) =
      (evalBinaryValue target op left right).map (value rename) := by
  rw [binary_result]
  cases left <;> cases right <;> first | rfl | cases op <;> rfl

theorem assignment (rename : CellId → CellId) (target : Target)
    (op : AssignOp) (current : Option Value) (right : Value) :
    evalAssignValue target op (current.map (value rename))
        (value rename right) =
      (evalAssignValue target op current right).map (value rename) := by
  simp only [evalAssignValue]
  cases assignOpBinary? op with
  | none => rfl
  | some op => cases current <;> simp only [Option.map, binary] <;> rfl

end Lanius.Semantics.CellRenaming
