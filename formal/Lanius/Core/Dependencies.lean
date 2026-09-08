import Lanius.Core

namespace Lanius.Core.Dependencies

/-! Static call closure. Core calls name functions directly; values and
patterns contain no function references. Every nested expression is checked. -/
mutual
  def expression (allowed : FunctionId → Bool) : Expr → Bool
    | .value _ | .local _ | .constant _ => true
    | .cast _ value | .unary _ value | .arrayToSlice _ value | .field value _
    | .dereference value | .intrinsic _ value | .i32ArrayDataPtr value
    | .i32SliceDataPtr value | .stringDataPtr value => expression allowed value
    | .binary _ left right | .index left right | .i32SliceFromRawParts left right
    | .alloc left right | .loadByte left right => expression allowed left && expression allowed right
    | .array _ values | .structValue _ values | .enumValue _ _ values => expressions allowed values
    | .matchValue value branches => expression allowed value && arms allowed branches
    | .assign _ target value => place allowed target && expression allowed value
    | .borrow _ target => place allowed target
    | .call id values => allowed id && expressions allowed values
    | .realloc pointer oldSize newSize alignment =>
        expression allowed pointer && expression allowed oldSize && expression allowed newSize && expression allowed alignment
    | .dealloc pointer size alignment | .storeByte pointer size alignment =>
        expression allowed pointer && expression allowed size && expression allowed alignment
  def expressions (allowed : FunctionId → Bool) : List Expr → Bool
    | [] => true
    | first :: rest => expression allowed first && expressions allowed rest
  def place (allowed : FunctionId → Bool) : Place → Bool
    | .local _ => true
    | .field base _ => place allowed base
    | .index base index => place allowed base && expression allowed index
  def arms (allowed : FunctionId → Bool) : List (Pattern × Expr) → Bool
    | [] => true
    | (_, value) :: rest => expression allowed value && arms allowed rest
end

def optional (allowed : FunctionId → Bool) : Option Expr → Bool
  | none => true
  | some value => expression allowed value

def statement (allowed : FunctionId → Bool) : Stmt → Bool
  | .skip | .breakLoop | .continueLoop => true
  | .expression value => expression allowed value
  | .sequence first second => statement allowed first && statement allowed second
  | .letLocal _ _ value body => expression allowed value && statement allowed body
  | .letUninitialized _ _ body => statement allowed body
  | .ifThenElse condition yes no => expression allowed condition && statement allowed yes && statement allowed no
  | .whileLoop condition body => expression allowed condition && statement allowed body
  | .forValues _ values body => expression allowed values && statement allowed body
  | .forRange _ start stop _ body => expression allowed start && optional allowed stop && statement allowed body
  | .returnValue value => optional allowed value

def body (allowed : FunctionId → Bool) : Option Stmt → Bool
  | none => true
  | some value => statement allowed value

/-- Omitted functions need not be closed: their bodies cannot be reached. -/
def closed (program : Program) (allowed : FunctionId → Bool) : Bool :=
  program.functions.all fun function => !allowed function.id || body allowed function.body

def restrict (program : Program) (allowed : FunctionId → Bool) : Program :=
  { program with functions := program.functions.filter (fun function => allowed function.id) }

end Lanius.Core.Dependencies
