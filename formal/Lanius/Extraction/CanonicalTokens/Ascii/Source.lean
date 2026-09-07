import Lanius.Extraction.Source.Statement
import Lanius.Extraction.Input.Buffer
import Lanius.Core.Equality

namespace Lanius.Extraction.CanonicalTokens.Ascii

open Lanius.Core Lanius.Extraction.Source

structure Locals where
  source : VarId
  start : VarId
  packed : VarId
  cursor : VarId
  length : VarId
  expected : VarId

def Locals.byte (locals : Locals) : Expr :=
  Input.packedByteExpression (.local locals.packed) (.local locals.cursor)

def Locals.different (locals : Locals) : Expr :=
  .binary .notEqual
    (.index (.local locals.source) (.binary .add (.local locals.start) (.local locals.cursor)))
    (.local locals.expected)

def Locals.continuation (locals : Locals) : Stmt :=
  .sequence (.ifThenElse locals.different
      (.sequence (.returnValue (some (.value (.boolean false)))) .skip) .skip)
      (.sequence (.expression (.assign .add (.local locals.cursor) (.value (.signed .i32 1)))) .skip)

def Locals.body (locals : Locals) : Stmt :=
  .letLocal locals.expected (.scalar (.signed .i32)) locals.byte locals.continuation

def Locals.loop (locals : Locals) : Stmt :=
  .whileLoop (.binary .notEqual (.local locals.cursor) (.local locals.length)) locals.body

def Locals.finish (locals : Locals) : Stmt :=
  .sequence locals.loop (.sequence (.returnValue (some (.value (.boolean true)))) .skip)

def sourceLocals : Locals := ⟨0, 1, 4, 5, 3, 6⟩

def wordCount : Expr :=
  .binary .divide (.binary .add (.local 3) (.value (.signed .i32 3))) (.value (.signed .i32 4))

def wordView : Expr :=
  .i32SliceFromRawParts (.stringDataPtr (.local 2)) wordCount

/-- Exact body of the source helper, including pointer conversion and both
local initializers. Its local IDs are checked, not inferred from a loop alone. -/
def sourceBody : Stmt :=
  .letLocal 4 (.slice (.scalar (.signed .i32))) wordView
    (.letLocal 5 (.scalar (.signed .i32)) (.value (.signed .i32 0)) sourceLocals.finish)

def checkBody? (body : Stmt) : Option (Equality.Evidence body sourceBody) :=
  Equality.statement? body sourceBody

def sourceFunction (id : FunctionId) : Function := {
  id
  parameters := [(0, .slice (.scalar (.signed .i32))), (1, .scalar (.signed .i32)),
    (2, .scalar .string), (3, .scalar (.signed .i32))]
  returnType := .scalar .bool
  body := some sourceBody
}

def checkFunction? (function : Function) :
    Option (Equality.Evidence function (sourceFunction function.id)) :=
  Equality.function? function (sourceFunction function.id)

/-- Recover candidate local IDs, then check the entire loop with equality
evidence. A changed byte expression, return, increment, or local reference
cannot be accepted merely because its outer shape resembles the matcher. -/
def checkLoop? (statement : Stmt) : Option (CheckedStatement Locals.loop statement) := do
  let .whileLoop (.binary .notEqual (.local cursor) (.local length))
      (.letLocal expected _
        (.binary .bitAnd (.binary .shiftRight (.index (.local packed) _) _) _)
        (.sequence (.ifThenElse
          (.binary .notEqual (.index (.local source) (.binary .add (.local start) _)) _) _ _) _)) := statement
    | none
  let locals : Locals := ⟨source, start, packed, cursor, length, expected⟩
  let some exactSource := Equality.statement? statement locals.loop | none
  pure ⟨locals, exactSource.equal⟩

def findLoop? := findStatement? Locals.loop checkLoop?

end Lanius.Extraction.CanonicalTokens.Ascii
