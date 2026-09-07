import Lanius.Extraction.CanonicalTokens.Kind.Call
import Lanius.Extraction.CanonicalTokens.Trivia
import Lanius.Extraction.Source.Statement

namespace Lanius.Extraction.CanonicalTokens.Compaction

open Lanius.Core

def literal (value : Int) : Expr := .value (.signed .i32 value)
def add (left right : Expr) : Expr := .binary .add left right
def row (index : Expr) : Expr := .binary .multiply index (literal 3)
def read (index : Expr) : Expr := .index (.local 1) index
def store (index value : Expr) : Stmt := .expression (.assign .set (.index (.local 1) index) value)
def increment (id : VarId) : Stmt := .expression (.assign .add (.local id) (literal 1))
def statements (items : List Stmt) : Stmt := items.foldr .sequence .skip
def local32 (id : VarId) (value : Expr) (rest : Stmt) : Stmt := .letLocal id (.scalar (.signed .i32)) value rest

def rowStores (kind : FunctionId) (rest : Stmt) : Stmt :=
  .sequence (store (.local 9) (.call kind [.local 0, .local 6, .local 7, .local 8]))
    (.sequence (store (add (.local 9) (literal 1)) (.local 7))
      (.sequence (store (add (.local 9) (literal 2)) (.local 8)) rest))

def keptBody (kind : FunctionId) : Stmt :=
  local32 7 (read (add (.local 5) (literal 1)))
    (local32 8 (read (add (.local 5) (literal 2)))
      (local32 9 (row (.local 4)) (rowStores kind (statements [increment 4]))))

def filterBranch (trivia kind : FunctionId) : Stmt :=
  .ifThenElse (.unary .logicalNot (.call trivia [.local 6])) (keptBody kind) .skip

def inputBody (trivia kind : FunctionId) : Stmt :=
  local32 5 (row (.local 3)) (local32 6 (read (.local 5)) (statements [
    filterBranch trivia kind,
    increment 3]))

def inputLoop (trivia kind : FunctionId) : Stmt :=
  .whileLoop (.binary .less (.local 3) (.local 2)) (inputBody trivia kind)

structure RangeTokens where
  range : ConstantId
  assign : ConstantId
  inclusive : ConstantId

def rangeCondition (tokens : RangeTokens) : Expr :=
  .binary .logicalAnd
    (.binary .logicalAnd
      (.binary .equal (read (.local 11)) (.constant tokens.range))
      (.binary .equal (read (.local 12)) (.constant tokens.assign)))
    (.binary .equal (read (add (.local 12) (literal 1))) (read (add (.local 11) (literal 2))))

def rangeMark (tokens : RangeTokens) : Stmt :=
  .ifThenElse (rangeCondition tokens)
    (statements [store (.local 11) (.constant tokens.inclusive)]) .skip

def rangeBody (tokens : RangeTokens) : Stmt :=
  local32 11 (row (.local 10)) (local32 12 (add (.local 11) (literal 3))
    (statements [rangeMark tokens, increment 10]))

def rangeLoop (tokens : RangeTokens) : Stmt :=
  .whileLoop (.binary .less (add (.local 10) (literal 1)) (.local 4)) (rangeBody tokens)

def finish (tokens : RangeTokens) : Stmt :=
  local32 10 (literal 0) (statements [rangeLoop tokens, .returnValue (some (.local 4))])

def body (trivia kind : FunctionId) (tokens : RangeTokens) : Stmt :=
  local32 3 (literal 0) (local32 4 (literal 0) (.sequence (inputLoop trivia kind) (finish tokens)))

def sourceFunction (id trivia kind : FunctionId) (tokens : RangeTokens) : Function := {
  id
  parameters := [(0, .slice (.scalar (.signed .i32))), (1, .slice (.scalar (.signed .i32))),
    (2, .scalar (.signed .i32))]
  returnType := .scalar (.signed .i32)
  body := some (body trivia kind tokens)
}

private def checkRangeMark? (statement : Stmt) :
    Option (Lanius.Extraction.Source.CheckedStatement rangeMark statement) := do
  let .ifThenElse (.binary .logicalAnd (.binary .logicalAnd
      (.binary .equal _ (.constant range)) (.binary .equal _ (.constant assign))) _)
      (.sequence (.expression (.assign .set _ (.constant inclusive))) _) _ := statement | none
  let tokens : RangeTokens := ⟨range, assign, inclusive⟩
  let same ← Equality.statement? statement (rangeMark tokens)
  pure ⟨tokens, same.equal⟩

structure CheckedSource (program : Program) (functionId triviaId kindId keywordId matcher : FunctionId) where
  trivia : Trivia.Checked program triviaId
  kind : Kind.Checked program kindId keywordId matcher
  tokens : RangeTokens
  rangeFound : Trivia.ConstantAt program tokens.range 182
  assignFound : Trivia.ConstantAt program tokens.assign 8
  inclusiveFound : Trivia.ConstantAt program tokens.inclusive 189
  found : program.function? functionId = some (sourceFunction functionId triviaId kindId tokens)

private def checkConstant? (program : Program) (id : ConstantId) (value : Int) :
    Option (PLift (Trivia.ConstantAt program id value)) := do
  match found : program.constant? id with
  | none => none
  | some constant =>
      let same ← Equality.constant? constant { id, type := .scalar (.signed .i32), value := .signed .i32 value }
      pure ⟨found.trans (congrArg some same.equal)⟩

def checkSource? (program : Program) (functionId : FunctionId)
    {triviaId kindId keywordId matcher : FunctionId}
    (trivia : Trivia.Checked program triviaId) (kind : Kind.Checked program kindId keywordId matcher) :
    Option (CheckedSource program functionId triviaId kindId keywordId matcher) := do
  match found : program.function? functionId with
  | none => none
  | some function =>
      let statement ← function.body
      let marker ← Lanius.Extraction.Source.findStatement? rangeMark checkRangeMark? statement
      let same ← Equality.function? function (sourceFunction functionId triviaId kindId marker.locals)
      let rangeFound ← checkConstant? program marker.locals.range 182
      let assignFound ← checkConstant? program marker.locals.assign 8
      let inclusiveFound ← checkConstant? program marker.locals.inclusive 189
      pure ⟨trivia, kind, marker.locals, rangeFound.down, assignFound.down, inclusiveFound.down,
        found.trans (congrArg some same.equal)⟩

end Lanius.Extraction.CanonicalTokens.Compaction
