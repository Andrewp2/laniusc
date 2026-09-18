import Lanius.Extraction.Source.Statement
import Lanius.Core.Equality

namespace Lanius.Extraction.Input

open Lanius.Core Lanius.Extraction.Source

structure UnpackLocals where
  packed : VarId
  output : VarId
  total : Option VarId
  cursor : VarId
  length : VarId

def UnpackLocals.index (locals : UnpackLocals) : Expr :=
  match locals.total with
  | none => .local locals.cursor
  | some total => .binary .add (.local total) (.local locals.cursor)

def UnpackLocals.stableLocals (locals : UnpackLocals) : List VarId :=
  [locals.output, locals.packed, locals.length] ++ locals.total.toList

def UnpackLocals.assignment (locals : UnpackLocals) : Expr :=
  .assign .set
    (.index (.local locals.output) locals.index)
    (.binary .bitAnd
      (.binary .shiftRight
        (.index (.local locals.packed)
          (.binary .divide (.local locals.cursor) (.value (.signed .i32 4))))
        (.binary .multiply
          (.binary .remainder (.local locals.cursor) (.value (.signed .i32 4)))
          (.value (.signed .i32 8))))
      (.value (.signed .i32 255)))

def UnpackLocals.body (locals : UnpackLocals) : Stmt :=
  .sequence (.expression locals.assignment)
    (.sequence (.expression (.assign .add (.local locals.cursor)
      (.value (.signed .i32 1)))) .skip)

def UnpackLocals.loop (locals : UnpackLocals) : Stmt :=
  .whileLoop (.binary .notEqual (.local locals.cursor) (.local locals.length)) locals.body

private def unpackCandidate? : Stmt → Option UnpackLocals
  | .whileLoop (.binary .notEqual (.local cursor) (.local length))
      (.sequence (.expression (.assign .set
        (.index (.local output) position)
        (.binary .bitAnd
          (.binary .shiftRight
            (.index (.local packed) (.binary .divide (.local readCursor) (.value (.signed .i32 4))))
            (.binary .multiply
              (.binary .remainder (.local laneCursor) (.value (.signed .i32 4)))
              (.value (.signed .i32 8)))) (.value (.signed .i32 255)))))
        (.sequence (.expression (.assign .add (.local incrementCursor)
          (.value (.signed .i32 1)))) .skip)) =>
      if readCursor = cursor ∧ laneCursor = cursor ∧ incrementCursor = cursor then
        match position with
        | .local writeCursor =>
            if writeCursor = cursor then some ⟨packed, output, none, cursor, length⟩ else none
        | .binary .add (.local total) (.local writeCursor) =>
            if writeCursor = cursor then some ⟨packed, output, some total, cursor, length⟩ else none
        | _ => none
      else none
  | _ => none

def checkUnpackLoop? (statement : Stmt) : Option (CheckedStatement UnpackLocals.loop statement) := do
  let locals ← unpackCandidate? statement
  let checked ← Equality.statement? statement locals.loop
  pure ⟨locals, checked.equal⟩

def findUnpackLoop? := findStatement? UnpackLocals.loop checkUnpackLoop?

end Lanius.Extraction.Input
