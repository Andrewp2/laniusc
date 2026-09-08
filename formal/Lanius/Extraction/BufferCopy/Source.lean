import Lanius.Extraction.Source.Statement

namespace Lanius.Extraction.BufferCopy

open Lanius.Core Lanius.Extraction.Source

inductive Scale where
  | plain
  | triple
deriving DecidableEq

def Scale.factor : Scale → Nat
  | .plain => 1
  | .triple => 3

def Scale.expression (scale : Scale) (id : VarId) : Expr :=
  match scale with
  | .plain => .local id
  | .triple => .binary .multiply (.local id) (.value (.signed .i32 3))

structure Locals where
  source : VarId
  destination : VarId
  cursor : VarId
  count : VarId
  readScale : Scale
  countScale : Scale

def Locals.body (locals : Locals) : Stmt :=
  .sequence (.expression (.assign .set
    (.index (.local locals.destination) (.local locals.cursor))
    (.index (.local locals.source) (locals.readScale.expression locals.cursor))))
    (.sequence (.expression (.assign .add (.local locals.cursor)
      (.value (.signed .i32 1)))) .skip)

def Locals.loop (locals : Locals) : Stmt :=
  .whileLoop (.binary .notEqual (.local locals.cursor)
    (locals.countScale.expression locals.count)) locals.body

private structure ScaledLocal (expression : Expr) where
  id : VarId
  scale : Scale
  exactSource : expression = scale.expression id

private def scaledLocal? : (expression : Expr) → Option (ScaledLocal expression)
  | .local id => some ⟨id, .plain, rfl⟩
  | .binary .multiply (.local id) (.value (.signed .i32 3)) => some ⟨id, .triple, rfl⟩
  | _ => none

/-- Recover bindings, then check the entire loop, including cursor identities
and the increment. A near-match cannot acquire a correctness theorem. -/
def checkLoop? : (statement : Stmt) → Option (CheckedStatement Locals.loop statement)
  | .whileLoop (.binary .notEqual (.local cursor) limit)
      (.sequence (.expression (.assign .set (.index (.local destination) (.local writeCursor))
        (.index (.local source) readIndex)))
        (.sequence (.expression (.assign .add (.local incrementCursor)
          (.value (.signed .i32 1)))) .skip)) => do
      let count ← scaledLocal? limit
      let read ← scaledLocal? readIndex
      if same : writeCursor = cursor ∧ incrementCursor = cursor ∧ read.id = cursor then
        some ⟨⟨source, destination, cursor, count.id, read.scale, count.scale⟩, by
          rcases count with ⟨countId, countScale, countExact⟩
          rcases read with ⟨readId, readScale, readExact⟩
          dsimp at same ⊢
          rcases same with ⟨rfl, rfl, readCursor⟩
          rw [countExact, readExact, readCursor]
          rfl⟩
      else none
  | _ => none

def findLoop? := findStatement? Locals.loop checkLoop?

end Lanius.Extraction.BufferCopy
