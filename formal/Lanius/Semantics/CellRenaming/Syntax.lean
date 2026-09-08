import Lanius.Semantics.CellRenaming.Value

namespace Lanius.Semantics.CellRenaming
open Lanius.Core

/- Only embedded runtime values change. Global symbols, types and patterns
are unchanged; pattern matching observes no cell identity. -/
mutual
  def expression (rename : CellId → CellId) : Expr → Expr
    | .value v => .value (value rename v)
    | .local id => .local id
    | .cast t v => .cast t (expression rename v)
    | .unary op v => .unary op (expression rename v)
    | .binary op left right => .binary op (expression rename left) (expression rename right)
    | .array t vs => .array t (expressions rename vs)
    | .arrayToSlice t v => .arrayToSlice t (expression rename v)
    | .index base index => .index (expression rename base) (expression rename index)
    | .structValue id vs => .structValue id (expressions rename vs)
    | .field base field => .field (expression rename base) field
    | .enumValue id variant vs => .enumValue id variant (expressions rename vs)
    | .matchValue v branches => .matchValue (expression rename v) (arms rename branches)
    | .assign op target v => .assign op (place rename target) (expression rename v)
    | .borrow t target => .borrow t (place rename target)
    | .dereference v => .dereference (expression rename v)
    | .constant id => .constant id
    | .call id vs => .call id (expressions rename vs)
    | .intrinsic op v => .intrinsic op (expression rename v)
    | .i32ArrayDataPtr v => .i32ArrayDataPtr (expression rename v)
    | .i32SliceFromRawParts pointer length => .i32SliceFromRawParts (expression rename pointer) (expression rename length)
    | .i32SliceDataPtr v => .i32SliceDataPtr (expression rename v)
    | .stringDataPtr v => .stringDataPtr (expression rename v)
    | .alloc size alignment => .alloc (expression rename size) (expression rename alignment)
    | .realloc pointer oldSize newSize alignment => .realloc (expression rename pointer) (expression rename oldSize) (expression rename newSize) (expression rename alignment)
    | .dealloc pointer size alignment => .dealloc (expression rename pointer) (expression rename size) (expression rename alignment)
    | .loadByte pointer offset => .loadByte (expression rename pointer) (expression rename offset)
    | .storeByte pointer offset v => .storeByte (expression rename pointer) (expression rename offset) (expression rename v)
  def expressions (rename : CellId → CellId) : List Expr → List Expr
    | [] => []
    | e :: rest => expression rename e :: expressions rename rest
  def place (rename : CellId → CellId) : Place → Place
    | .local id => .local id
    | .field base field => .field (place rename base) field
    | .index base index => .index (place rename base) (expression rename index)
  def arms (rename : CellId → CellId) : List (Pattern × Expr) → List (Pattern × Expr)
    | [] => []
    | (p, e) :: rest => (p, expression rename e) :: arms rename rest
end

def statement (rename : CellId → CellId) : Stmt → Stmt
  | .skip => .skip
  | .expression e => .expression (expression rename e)
  | .sequence first second => .sequence (statement rename first) (statement rename second)
  | .letLocal id t e body => .letLocal id t (expression rename e) (statement rename body)
  | .letUninitialized id t body => .letUninitialized id t (statement rename body)
  | .ifThenElse condition yes no => .ifThenElse (expression rename condition) (statement rename yes) (statement rename no)
  | .whileLoop condition body => .whileLoop (expression rename condition) (statement rename body)
  | .forValues id iterable body => .forValues id (expression rename iterable) (statement rename body)
  | .forRange id start stop inclusive body => .forRange id (expression rename start)
      (stop.map (expression rename)) inclusive (statement rename body)
  | .returnValue v => .returnValue (v.map (expression rename))
  | .breakLoop => .breakLoop
  | .continueLoop => .continueLoop

end Lanius.Semantics.CellRenaming

