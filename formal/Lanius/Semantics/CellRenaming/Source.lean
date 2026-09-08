import Lanius.Semantics.CellRenaming.Syntax
import Lanius.Semantics.CellRenaming.Literal

namespace Lanius.Semantics.CellRenaming.Source
open Lanius.Core

/- Check every embedded expression value. Patterns are unchanged by cell
renaming and their matcher cannot observe cell identities. -/
mutual
  def expression : Expr → Bool
    | .value entry => Typing.Value.isLiteral entry
    | .local _ | .constant _ => true
    | .cast _ value | .unary _ value | .arrayToSlice _ value | .field value _
    | .dereference value | .intrinsic _ value | .i32ArrayDataPtr value
    | .i32SliceDataPtr value | .stringDataPtr value => expression value
    | .binary _ left right | .index left right | .i32SliceFromRawParts left right
    | .alloc left right | .loadByte left right => expression left && expression right
    | .array _ values | .structValue _ values | .enumValue _ _ values => expressions values
    | .matchValue value branches => expression value && arms branches
    | .assign _ target value => place target && expression value
    | .borrow _ target => place target
    | .call _ values => expressions values
    | .realloc pointer oldSize newSize alignment =>
        expression pointer && expression oldSize && expression newSize && expression alignment
    | .dealloc pointer size alignment | .storeByte pointer size alignment =>
        expression pointer && expression size && expression alignment
  def expressions : List Expr → Bool
    | [] => true
    | first :: rest => expression first && expressions rest
  def place : Place → Bool
    | .local _ => true
    | .field base _ => place base
    | .index base index => place base && expression index
  def arms : List (Pattern × Expr) → Bool
    | [] => true
    | (_, value) :: rest => expression value && arms rest
end

def optional : Option Expr → Bool
  | none => true
  | some value => expression value

def statement : Stmt → Bool
  | .skip | .breakLoop | .continueLoop => true
  | .expression value => expression value
  | .sequence first second => statement first && statement second
  | .letLocal _ _ value body => expression value && statement body
  | .letUninitialized _ _ body => statement body
  | .ifThenElse condition yes no => expression condition && statement yes && statement no
  | .whileLoop condition body => expression condition && statement body
  | .forValues _ values body => expression values && statement body
  | .forRange _ start stop _ body => expression start && optional stop && statement body
  | .returnValue value => optional value

mutual
  theorem expression_fixed (rename : CellId → CellId) (input : Expr)
      (checked : expression input = true) : CellRenaming.expression rename input = input := by
    cases input <;> simp only [expression, Bool.and_eq_true] at checked <;>
      simp_all [CellRenaming.expression, expression_fixed, expressions_fixed, place_fixed,
        arms_fixed, literal_fixed]
  theorem expressions_fixed (rename : CellId → CellId) (input : List Expr)
      (checked : expressions input = true) : CellRenaming.expressions rename input = input := by
    cases input <;> simp only [expressions, Bool.and_eq_true] at checked <;>
      simp_all [CellRenaming.expressions, expression_fixed, expressions_fixed]
  theorem place_fixed (rename : CellId → CellId) (input : Place)
      (checked : place input = true) : CellRenaming.place rename input = input := by
    cases input <;> simp only [place, Bool.and_eq_true] at checked <;>
      simp_all [CellRenaming.place, place_fixed, expression_fixed]
  theorem arms_fixed (rename : CellId → CellId) (input : List (Pattern × Expr))
      (checked : arms input = true) : CellRenaming.arms rename input = input := by
    cases input with
    | nil => rfl
    | cons first rest =>
        obtain ⟨pattern, body⟩ := first
        simp only [arms, Bool.and_eq_true] at checked
        simp_all [CellRenaming.arms, expression_fixed, arms_fixed]
end

theorem optional_fixed (rename : CellId → CellId) (input : Option Expr)
    (checked : optional input = true) : input.map (CellRenaming.expression rename) = input := by
  cases input <;> simp_all [optional, expression_fixed]

theorem statement_fixed (rename : CellId → CellId) (input : Stmt)
    (checked : statement input = true) : CellRenaming.statement rename input = input := by
  induction input <;> simp only [statement, Bool.and_eq_true] at checked <;>
    simp_all [CellRenaming.statement, expression_fixed, optional_fixed]

end Lanius.Semantics.CellRenaming.Source
