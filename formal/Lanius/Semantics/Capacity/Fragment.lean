import Lanius.Semantics.Capacity.Value

namespace Lanius.Semantics.Capacity.Fragment
open Lanius.Core

/-! Checked syntax for capacity-insensitive computations. In particular,
iteration over implicit slice length and operations synchronizing native
views are excluded. Explicit indexed loops and fresh borrowed views remain
available. This checker is not by itself an execution theorem. -/
mutual
  def expression (allowed : FunctionId → Bool) : Expr → Bool
    | .value entry => plain entry
    | .local _ | .constant _ => true
    | .cast _ operand | .unary _ operand | .field operand _ | .stringDataPtr operand => expression allowed operand
    | .binary _ left right | .index left right | .i32SliceFromRawParts left right =>
        expression allowed left && expression allowed right
    | .array _ entries | .structValue _ entries | .enumValue _ _ entries => expressions allowed entries
    | .assign _ target entry => place allowed target && expression allowed entry
    | .call id entries => allowed id && expressions allowed entries
    | _ => false
  def expressions (allowed : FunctionId → Bool) : List Expr → Bool
    | [] => true
    | first :: rest => expression allowed first && expressions allowed rest
  def place (allowed : FunctionId → Bool) : Place → Bool
    | .local _ => true
    | .field base _ => place allowed base
    | .index base index => place allowed base && expression allowed index
end

def optional (allowed : FunctionId → Bool) : Option Expr → Bool
  | none => true
  | some entry => expression allowed entry

def statement (allowed : FunctionId → Bool) : Stmt → Bool
  | .skip | .breakLoop | .continueLoop => true
  | .expression entry => expression allowed entry
  | .sequence first second => statement allowed first && statement allowed second
  | .letLocal _ _ entry body => expression allowed entry && statement allowed body
  | .letUninitialized _ _ body => statement allowed body
  | .ifThenElse condition yes no => expression allowed condition && statement allowed yes && statement allowed no
  | .whileLoop condition body => expression allowed condition && statement allowed body
  | .forRange _ start stop _ body => expression allowed start && optional allowed stop && statement allowed body
  | .returnValue entry => optional allowed entry
  | .forValues .. => false

structure Checked (program : Program) (allowed : FunctionId → Bool) : Prop where
  constant : ∀ id declaration, program.constant? id = some declaration → plain declaration.value = true
  function : ∀ id declaration, allowed id = true → program.function? id = some declaration →
    ∃ body, declaration.body = some body ∧ statement allowed body = true

def check (program : Program) (allowed : FunctionId → Bool) : Bool :=
  program.constants.all (fun declaration => plain declaration.value) &&
  program.functions.all (fun declaration => !allowed declaration.id || match declaration.body with
    | none => false
    | some body => statement allowed body)

theorem checked (accepted : check program allowed = true) : Checked program allowed := by
  have parts : program.constants.all (fun declaration => plain declaration.value) = true ∧
      program.functions.all (fun declaration => !allowed declaration.id || match declaration.body with
        | none => false
        | some body => statement allowed body) = true := by
    simpa only [check, Bool.and_eq_true] using accepted
  constructor
  · intro id declaration found
    exact List.all_eq_true.mp parts.1 declaration (List.mem_of_find?_eq_some found)
  · intro id declaration included found
    have same : declaration.id = id := by simpa using List.find?_some found
    have accepted := List.all_eq_true.mp parts.2 declaration (List.mem_of_find?_eq_some found)
    simp only [same, included, Bool.not_true, Bool.false_or] at accepted
    cases hasBody : declaration.body with
    | none => simp [hasBody] at accepted
    | some body => exact ⟨body, rfl, by simpa only [hasBody] using accepted⟩

end Lanius.Semantics.Capacity.Fragment
