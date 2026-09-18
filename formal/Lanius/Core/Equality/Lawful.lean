import Lanius.Core

namespace Lanius.Core

/-!
The nested AST uses total Boolean equality in Core. These theorems establish
its meaning for every value, not just the source artifacts checked today.
Lists, match arms, float bit patterns, and all constructor fields participate.
-/

mutual
  theorem Value.beq_eq_true (a b : Value) : Value.beq a b = true ↔ a = b := by
    cases a <;> cases b <;>
      simp [Value.beq, Bool.and_eq_true, and_assoc]
    case array.array xs ys => exact Value.beqList_eq_true xs ys
    case structure.structure ai xs bi ys => simp [Value.beqList_eq_true xs ys]
    case enumeration.enumeration ai av xs bi bv ys => simp [Value.beqList_eq_true xs ys]
  termination_by sizeOf a

  theorem Value.beqList_eq_true (a b : List Value) : Value.beqList a b = true ↔ a = b := by
    cases a <;> cases b <;> simp [Value.beqList]
    case cons.cons x xs y ys => rw [Value.beq_eq_true x y, Value.beqList_eq_true xs ys]
  termination_by sizeOf a
end

instance : LawfulBEq Value where
  eq_of_beq {a b} h := (Value.beq_eq_true a b).mp h
  rfl {a} := (Value.beq_eq_true a a).mpr rfl

mutual
  theorem Pattern.beq_eq_true (a b : Pattern) : Pattern.beq a b = true ↔ a = b := by
    cases a <;> cases b <;> simp [Pattern.beq, Bool.and_eq_true, and_assoc, Value.beq_eq_true]
    case enumVariant.enumVariant a0 a1 a2 b0 b1 b2 =>
      simp [Pattern.beqList_eq_true a2 b2]
  termination_by sizeOf a

  theorem Pattern.beqList_eq_true (a b : List Pattern) : Pattern.beqList a b = true ↔ a = b := by
    cases a <;> cases b <;> simp [Pattern.beqList]
    case cons.cons x xs y ys => rw [Pattern.beq_eq_true x y, Pattern.beqList_eq_true xs ys]
  termination_by sizeOf a
end

instance : LawfulBEq Pattern where
  eq_of_beq {a b} h := (Pattern.beq_eq_true a b).mp h
  rfl {a} := (Pattern.beq_eq_true a a).mpr rfl

mutual
  theorem Expr.beq_eq_true (a b : Expr) : Expr.beq a b = true ↔ a = b := by
    cases a <;> cases b <;> simp [Expr.beq, Bool.and_eq_true, and_assoc, Value.beq_eq_true]
    case cast.cast a0 a1 b0 b1 =>
      simp [Expr.beq_eq_true a1 b1]
    case unary.unary a0 a1 b0 b1 =>
      simp [Expr.beq_eq_true a1 b1]
    case binary.binary a0 a1 a2 b0 b1 b2 =>
      simp [Expr.beq_eq_true a1 b1, Expr.beq_eq_true a2 b2]
    case array.array a0 a1 b0 b1 =>
      simp [Expr.beqList_eq_true a1 b1]
    case arrayToSlice.arrayToSlice a0 a1 b0 b1 =>
      simp [Expr.beq_eq_true a1 b1]
    case index.index a0 a1 b0 b1 =>
      simp [Expr.beq_eq_true a0 b0, Expr.beq_eq_true a1 b1]
    case structValue.structValue a0 a1 b0 b1 =>
      simp [Expr.beqList_eq_true a1 b1]
    case field.field a0 a1 b0 b1 =>
      simp [Expr.beq_eq_true a0 b0]
    case enumValue.enumValue a0 a1 a2 b0 b1 b2 =>
      simp [Expr.beqList_eq_true a2 b2]
    case matchValue.matchValue a0 a1 b0 b1 =>
      simp [Expr.beq_eq_true a0 b0, Expr.beqArms_eq_true a1 b1]
    case assign.assign a0 a1 a2 b0 b1 b2 =>
      simp [Place.beq_eq_true a1 b1, Expr.beq_eq_true a2 b2]
    case borrow.borrow a0 a1 b0 b1 =>
      simp [Place.beq_eq_true a1 b1]
    case dereference.dereference a0 b0 =>
      simp [Expr.beq_eq_true a0 b0]
    case call.call a0 a1 b0 b1 =>
      simp [Expr.beqList_eq_true a1 b1]
    case intrinsic.intrinsic a0 a1 b0 b1 =>
      simp [Expr.beq_eq_true a1 b1]
    case i32ArrayDataPtr.i32ArrayDataPtr a0 b0 =>
      simp [Expr.beq_eq_true a0 b0]
    case i32SliceFromRawParts.i32SliceFromRawParts a0 a1 b0 b1 =>
      simp [Expr.beq_eq_true a0 b0, Expr.beq_eq_true a1 b1]
    case i32SliceDataPtr.i32SliceDataPtr a0 b0 =>
      simp [Expr.beq_eq_true a0 b0]
    case stringDataPtr.stringDataPtr a0 b0 =>
      simp [Expr.beq_eq_true a0 b0]
    case alloc.alloc a0 a1 b0 b1 =>
      simp [Expr.beq_eq_true a0 b0, Expr.beq_eq_true a1 b1]
    case realloc.realloc a0 a1 a2 a3 b0 b1 b2 b3 =>
      simp [Expr.beq_eq_true a0 b0, Expr.beq_eq_true a1 b1, Expr.beq_eq_true a2 b2, Expr.beq_eq_true a3 b3]
    case dealloc.dealloc a0 a1 a2 b0 b1 b2 =>
      simp [Expr.beq_eq_true a0 b0, Expr.beq_eq_true a1 b1, Expr.beq_eq_true a2 b2]
    case loadByte.loadByte a0 a1 b0 b1 =>
      simp [Expr.beq_eq_true a0 b0, Expr.beq_eq_true a1 b1]
    case storeByte.storeByte a0 a1 a2 b0 b1 b2 =>
      simp [Expr.beq_eq_true a0 b0, Expr.beq_eq_true a1 b1, Expr.beq_eq_true a2 b2]
  termination_by sizeOf a
  theorem Place.beq_eq_true (a b : Place) : Place.beq a b = true ↔ a = b := by
    cases a <;> cases b <;> simp [Place.beq, Bool.and_eq_true]
    case field.field a0 a1 b0 b1 =>
      simp [Place.beq_eq_true a0 b0]
    case index.index a0 a1 b0 b1 =>
      simp [Place.beq_eq_true a0 b0, Expr.beq_eq_true a1 b1]
  termination_by sizeOf a

  theorem Expr.beqList_eq_true (a b : List Expr) : Expr.beqList a b = true ↔ a = b := by
    cases a <;> cases b <;> simp [Expr.beqList]
    case cons.cons x xs y ys => rw [Expr.beq_eq_true x y, Expr.beqList_eq_true xs ys]
  termination_by sizeOf a

  theorem Expr.beqArms_eq_true (a b : List (Pattern × Expr)) : Expr.beqArms a b = true ↔ a = b := by
    cases a with
    | nil => cases b <;> simp [Expr.beqArms]
    | cons x xs =>
      cases b with
      | nil => simp [Expr.beqArms]
      | cons y ys =>
        rcases x with ⟨ap, ae⟩
        rcases y with ⟨bp, be⟩
        simp [Expr.beqArms, Pattern.beq_eq_true, Expr.beq_eq_true ae be, Expr.beqArms_eq_true xs ys, and_assoc]
  termination_by sizeOf a
end

instance : LawfulBEq Expr where
  eq_of_beq {a b} h := (Expr.beq_eq_true a b).mp h
  rfl {a} := (Expr.beq_eq_true a a).mpr rfl

instance : LawfulBEq Place where
  eq_of_beq {a b} h := (Place.beq_eq_true a b).mp h
  rfl {a} := (Place.beq_eq_true a a).mpr rfl

deriving instance ReflBEq, LawfulBEq for Stmt
deriving instance ReflBEq, LawfulBEq for Function
deriving instance ReflBEq, LawfulBEq for Constant
deriving instance ReflBEq, LawfulBEq for Program

end Lanius.Core
