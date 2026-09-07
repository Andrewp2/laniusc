import Lanius.Extraction.Source.Statement

namespace Lanius.Extraction.Input

open Lanius.Core Lanius.Extraction.Source

structure UnpackLocals where
  packed : VarId
  output : VarId
  total : VarId
  cursor : VarId
  length : VarId

def UnpackLocals.assignment (locals : UnpackLocals) : Expr :=
  .assign .set
    (.index (.local locals.output) (.binary .add (.local locals.total) (.local locals.cursor)))
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

def checkUnpackLoop? : (statement : Stmt) → Option (CheckedStatement UnpackLocals.loop statement)
  | .whileLoop (.binary .notEqual (.local cursor) (.local length))
      (.sequence (.expression (.assign .set
        (.index (.local output) (.binary .add (.local total) (.local writeCursor)))
        (.binary .bitAnd
          (.binary .shiftRight
            (.index (.local packed) (.binary .divide (.local readCursor) (.value (.signed .i32 4))))
            (.binary .multiply
              (.binary .remainder (.local laneCursor) (.value (.signed .i32 4)))
              (.value (.signed .i32 8)))) (.value (.signed .i32 255)))))
        (.sequence (.expression (.assign .add (.local incrementCursor)
          (.value (.signed .i32 1)))) .skip)) =>
      if same : writeCursor = cursor ∧ readCursor = cursor ∧ laneCursor = cursor ∧
          incrementCursor = cursor then
        some ⟨⟨packed, output, total, cursor, length⟩, by
          rcases same with ⟨rfl, rfl, rfl, rfl⟩
          rfl⟩
      else none
  | _ => none

def findUnpackLoop? := findStatement? UnpackLocals.loop checkUnpackLoop?

end Lanius.Extraction.Input
