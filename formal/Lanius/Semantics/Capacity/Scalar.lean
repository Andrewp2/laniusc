import Lanius.Semantics.Capacity.Value

namespace Lanius.Semantics.Capacity

open Lanius.Core

theorem integerIndex (config : Config) (entry : Value) :
    Semantics.integerIndex (value config entry) = Semantics.integerIndex entry := by cases entry <;> rfl

theorem scalarEqual (config : Config) (left right : Value) :
    Semantics.scalarEqual (value config left) (value config right) = Semantics.scalarEqual left right := by
  cases left <;> cases right <;> rfl

theorem unary (config : Config) (target : Target) (op : UnaryOp) (entry : Value) :
    evalUnaryValue target op (value config entry) = (evalUnaryValue target op entry).map (value config) := by
  cases op <;> cases entry <;> rfl

theorem cast (config : Config) (target : Target) (destination : ScalarTy) (entry : Value) :
    evalScalarCast target destination (value config entry) = (evalScalarCast target destination entry).map (value config) := by
  cases destination <;> cases entry <;> rfl

private theorem signed (config : Config) (target : Target) (op : BinaryOp) (type : SignedIntTy) (left right : Int) :
    (evalSignedBinary target op type left right).map (value config) = evalSignedBinary target op type left right := by
  cases op <;> simp only [evalSignedBinary]
  all_goals repeat first | rfl | split

private theorem unsigned (config : Config) (target : Target) (op : BinaryOp) (type : UnsignedIntTy) (left right : Nat) :
    (evalUnsignedBinary target op type left right).map (value config) = evalUnsignedBinary target op type left right := by
  cases op <;> simp only [evalUnsignedBinary]
  all_goals repeat first | rfl | split

private theorem float32 (config : Config) (op : BinaryOp) (left right : UInt32) :
    (evalF32Binary op left right).map (value config) = evalF32Binary op left right := by cases op <;> rfl

private theorem float64 (config : Config) (op : BinaryOp) (left right : UInt64) :
    (evalF64Binary op left right).map (value config) = evalF64Binary op left right := by cases op <;> rfl

private theorem character (config : Config) (op : BinaryOp) (left right : UInt32) :
    (evalCharBinary op left right).map (value config) = evalCharBinary op left right := by
  cases op <;> simp only [evalCharBinary]
  all_goals repeat first | rfl | split

private theorem binary_result (config : Config) (target : Target) (op : BinaryOp) (left right : Value) :
    (evalBinaryValue target op left right).map (value config) = evalBinaryValue target op left right := by
  unfold evalBinaryValue
  split
  all_goals repeat first
    | solve | simp only [signed, unsigned, float32, float64, character]
    | rfl
    | split

theorem binary (config : Config) (target : Target) (op : BinaryOp) (left right : Value) :
    evalBinaryValue target op (value config left) (value config right) =
      (evalBinaryValue target op left right).map (value config) := by
  rw [binary_result]
  cases left <;> cases right <;> first | rfl | cases op <;> rfl

theorem assignment (config : Config) (target : Target) (op : AssignOp) (current : Option Value) (right : Value) :
    evalAssignValue target op (current.map (value config)) (value config right) =
      (evalAssignValue target op current right).map (value config) := by
  simp only [evalAssignValue]
  cases assignOpBinary? op with
  | none => rfl
  | some op => cases current <;> simp only [Option.map, binary] <;> rfl

theorem unary_plain (computed : evalUnaryValue target op input = .ok result) : plain result = true := by
  cases op <;> cases input <;> simp only [evalUnaryValue] at computed
  all_goals repeat first | contradiction | split at computed
  all_goals cases computed <;> rfl

theorem cast_plain (computed : evalScalarCast target type input = .ok result) : plain result = true := by
  cases type <;> cases input <;> simp only [evalScalarCast] at computed
  all_goals repeat first | contradiction | split at computed
  all_goals cases computed <;> rfl

private theorem signed_plain (computed : evalSignedBinary target op type left right = .ok result) : plain result = true := by
  cases op <;> simp only [evalSignedBinary] at computed
  all_goals repeat first | contradiction | split at computed
  all_goals cases computed <;> rfl

private theorem unsigned_plain (computed : evalUnsignedBinary target op type left right = .ok result) : plain result = true := by
  cases op <;> simp only [evalUnsignedBinary] at computed
  all_goals repeat first | contradiction | split at computed
  all_goals cases computed <;> rfl

private theorem float32_plain (computed : evalF32Binary op left right = .ok result) : plain result = true := by
  cases op <;> simp only [evalF32Binary] at computed
  all_goals repeat first | contradiction | split at computed
  all_goals cases computed <;> rfl

private theorem float64_plain (computed : evalF64Binary op left right = .ok result) : plain result = true := by
  cases op <;> simp only [evalF64Binary] at computed
  all_goals repeat first | contradiction | split at computed
  all_goals cases computed <;> rfl

private theorem character_plain (computed : evalCharBinary op left right = .ok result) : plain result = true := by
  cases op <;> simp only [evalCharBinary] at computed
  all_goals repeat first | contradiction | split at computed
  all_goals cases computed <;> rfl

theorem binary_plain (computed : evalBinaryValue target op left right = .ok result) : plain result = true := by
  unfold evalBinaryValue at computed
  split at computed
  case h_11 =>
    split at computed
    · exact signed_plain computed
    · contradiction
  case h_12 =>
    split at computed
    · exact unsigned_plain computed
    · contradiction
  case h_13 => exact float32_plain computed
  case h_14 => exact float64_plain computed
  case h_15 => exact character_plain computed
  case h_3 => split at computed <;> cases computed <;> rfl
  case h_4 => split at computed <;> cases computed <;> rfl
  all_goals cases computed <;> rfl

theorem assignment_closed (config : Config) (rightClosed : closed config right = true)
    (computed : evalAssignValue target op current right = .ok result) : closed config result = true := by
  unfold evalAssignValue at computed
  cases which : assignOpBinary? op with
  | none => simp only [which, Except.ok.injEq] at computed; cases computed; exact rightClosed
  | some operation =>
    cases current <;> simp only [which] at computed
    · contradiction
    · exact plain_closed config result (binary_plain computed)

end Lanius.Semantics.Capacity
