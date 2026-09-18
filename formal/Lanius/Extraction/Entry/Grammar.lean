import Lanius.Extraction.Entry.Decode
import Lanius.Extraction.Source.Statement

namespace Lanius.Extraction.Entry.Grammar

open Lanius.Core Lanius.Semantics Lanius.Extraction.Source

structure Locals where
  source : Lanius.VarId
  destination : Lanius.VarId
  cursor : Lanius.VarId
  word : Lanius.VarId
  count : Int

def Locals.body (locals : Locals) (function : Lanius.FunctionId) : Stmt :=
  .letLocal locals.word (.scalar (.signed .i32))
    (.index (.local locals.source) (.local locals.cursor))
    (.sequence (.expression (.assign .set
      (.index (.local locals.destination) (.local locals.cursor))
      (Hex.wordExpression function locals.word)))
      (.sequence (.expression (.assign .add (.local locals.cursor)
        (.value (.signed .i32 1)))) .skip))

def Locals.loop (locals : Locals) (function : Lanius.FunctionId) : Stmt :=
  .whileLoop (.binary .notEqual (.local locals.cursor) (.value (.signed .i32 locals.count)))
    (locals.body function)

/-- Recover local identities, but accept only equality of the complete loop:
all four calls, masks, shifts, store, and increment are checked together. -/
def checkLoop? (function : Lanius.FunctionId) (statement : Stmt) :
    Option (CheckedStatement (fun locals : Locals => locals.loop function) statement) :=
  match shape : statement with
  | .whileLoop (.binary .notEqual (.local cursor) (.value (.signed .i32 count)))
      (.letLocal word _ (.index (.local source) _)
        (.sequence (.expression (.assign .set (.index (.local destination) _) _)) _)) =>
      let locals : Locals := ⟨source, destination, cursor, word, count⟩
      (Lanius.Core.Equality.statement? statement (locals.loop function)).map
        (fun equality => ⟨locals, shape.symm.trans equality.equal⟩)
  | _ => none

def findLoop? (function : Lanius.FunctionId) :=
  findStatement? (fun locals : Locals => locals.loop function) (checkLoop? function)

structure CursorStage where
  locals : Locals
  continuation : Stmt

def CursorStage.statement (stage : CursorStage) (function : Lanius.FunctionId) : Stmt :=
  .letLocal stage.locals.cursor (.scalar (.signed .i32)) (.value (.signed .i32 0))
    (.sequence (stage.locals.loop function) stage.continuation)

def checkCursor? (function : Lanius.FunctionId) (statement : Stmt) :
    Option (CheckedStatement (fun stage : CursorStage => stage.statement function) statement) :=
  match shape : statement with
  | .letLocal _ _ _ (.sequence loop continuation) => do
      let checked ← checkLoop? function loop
      let stage : CursorStage := ⟨checked.locals, continuation⟩
      let equality ← Lanius.Core.Equality.statement? statement (stage.statement function)
      pure ⟨stage, shape.symm.trans equality.equal⟩
  | _ => none

def findCursor? (function : Lanius.FunctionId) :=
  findStatement? (fun stage : CursorStage => stage.statement function) (checkCursor? function)

structure SetupStage where
  text : Lanius.VarId
  cursor : CursorStage

def SetupStage.statement (stage : SetupStage) (function : Lanius.FunctionId) : Stmt :=
  .letLocal stage.cursor.locals.source (.slice (.scalar (.signed .i32)))
    (.i32SliceFromRawParts (.stringDataPtr (.local stage.text))
      (.value (.signed .i32 stage.cursor.locals.count))) (stage.cursor.statement function)

def checkSetup? (function : Lanius.FunctionId) (statement : Stmt) :
    Option (CheckedStatement (fun stage : SetupStage => stage.statement function) statement) :=
  match shape : statement with
  | .letLocal _ _ (.i32SliceFromRawParts (.stringDataPtr (.local text)) _) rest => do
      let cursor ← checkCursor? function rest
      let stage : SetupStage := ⟨text, cursor.locals⟩
      let equality ← Lanius.Core.Equality.statement? statement (stage.statement function)
      pure ⟨stage, shape.symm.trans equality.equal⟩
  | _ => none

def findSetup? (function : Lanius.FunctionId) :=
  findStatement? (fun stage : SetupStage => stage.statement function) (checkSetup? function)

end Lanius.Extraction.Entry.Grammar
