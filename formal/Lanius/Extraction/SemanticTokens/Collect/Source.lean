import Lanius.Extraction.Source.Statement
import Lanius.Extraction.Parser.Tree.Source

namespace Lanius.Extraction.SemanticTokens.Collect

open Lanius Lanius.Core Lanius.Extraction.Source Lanius.Extraction.CoreSynthesis.Program

structure Symbols where
  childToken : ConstantId
  childState : ConstantId

abbrev i32 : Ty := .scalar (.signed .i32)
abbrev number (n : Nat) : Expr := .value (.signed .i32 n)
abbrev negative (n : Nat) : Expr := .unary .negate (number n)
abbrev read (id : VarId) : Expr := .local id
abbrev binary (op : BinaryOp) (left right : Expr) : Expr := .binary op left right
abbrev atIndex (id : VarId) (index : Expr) : Expr := .index (read id) index
abbrev negate (condition : Expr) : Expr := .unary .logicalNot condition

def returned (value : Expr) : Stmt := .sequence (.returnValue (some value)) .skip
def reject (condition : Expr) (code : Nat := 1) : Stmt :=
  .ifThenElse condition (returned (negative code)) .skip
def increment (id : VarId) (amount : Nat) : Stmt :=
  .expression (.assign .add (.local id) (number amount))
def declare (id : VarId) (value : Expr) (body : Stmt) : Stmt := .letLocal id i32 value body

def inputGuard : Expr :=
  binary .logicalOr (binary .logicalOr (binary .logicalOr (binary .logicalOr
    (binary .lessEqual (read 1) (number 16)) (binary .lessEqual (read 3) (negative 1)))
    (binary .greaterEqual (read 3) (number 1073741824)))
    (binary .lessEqual (read 7) (negative 1))) (binary .lessEqual (read 5) (negative 1))

def capacityGuard : Expr :=
  binary .logicalOr (binary .lessEqual (read 9) (negative 1))
    (negate (binary .lessEqual (read 3) (binary .divide (read 9) (number 2))))

def grammarGuard : Expr :=
  binary .logicalOr (binary .logicalOr (binary .logicalOr (binary .logicalOr
    (binary .lessEqual (read 10) (number 0)) (binary .greaterEqual (read 10) (number 32769)))
    (binary .lessEqual (read 11) (negative 1))) (negate (binary .lessEqual (read 11) (read 1))))
    (negate (binary .lessEqual (read 10) (binary .subtract (read 1) (read 11))))

def initializeBody : Stmt :=
  .sequence (.expression (.assign .set (.index (.local 8) (read 12)) (negative 1)))
    (.sequence (increment 12 1) .skip)

def initializeCondition : Expr := binary .notEqual (read 12) (binary .multiply (read 3) (number 2))
def initializeLoop : Stmt := .whileLoop initializeCondition initializeBody

def splitGuard : Expr :=
  binary .logicalOr (binary .notEqual (read 21) (atIndex 0 (number 5)))
    (binary .notEqual (read 22) (atIndex 0 (number 6)))

def splitAdvance : Stmt := .sequence (reject splitGuard) (.sequence (increment 16 1) .skip)

def tokenAdvance : Stmt :=
  .ifThenElse (binary .equal (binary .remainder (read 16) (number 2)) (number 1)) splitAdvance
    (.sequence (.ifThenElse (binary .equal (read 21) (read 22))
      (.sequence (increment 16 2) .skip) splitAdvance) .skip)

def tokenBody : Stmt :=
  declare 20 (atIndex 4 (binary .add (read 18) (number 2)))
    (.sequence (reject (binary .logicalOr (binary .logicalOr (binary .logicalOr
      (binary .greaterEqual (read 19) (read 3))
      (binary .notEqual (read 19) (binary .divide (read 16) (number 2))))
      (binary .lessEqual (read 20) (negative 1))) (binary .greaterEqual (read 20) (read 10))))
      (declare 21 (atIndex 2 (read 19))
        (declare 22 (atIndex 0 (binary .add (read 11) (read 20)))
          (declare 23 (binary .add (binary .multiply (read 19) (number 2))
            (binary .remainder (read 16) (number 2)))
            (.sequence (reject (binary .notEqual (atIndex 8 (read 23)) (negative 1)))
              (.sequence (.expression (.assign .set (.index (.local 8) (read 23)) (read 20)))
                (.sequence tokenAdvance .skip)))))))

def recordGuard (id : VarId) : Expr :=
  binary .logicalOr (binary .logicalOr (binary .lessEqual (read id) (negative 1))
    (negate (binary .lessEqual (read id) (read 5))))
    (binary .lessEqual (binary .subtract (read 5) (read id)) (number 3))

def nodeChildBody (symbols : Symbols) : Stmt :=
  .sequence (reject (binary .logicalOr
    (binary .notEqual (atIndex 4 (read 18)) (.constant symbols.childState))
    (binary .greaterEqual (read 19) (read 13))))
    (declare 20 (atIndex 6 (read 19))
      (.sequence (reject (recordGuard 20))
        (.sequence (reject (binary .logicalOr (binary .logicalOr
          (binary .notEqual (atIndex 4 (binary .add (read 20) (number 1))) (read 16))
          (negate (binary .lessEqual (read 16) (atIndex 4 (binary .add (read 20) (number 2))))))
          (negate (binary .lessEqual (atIndex 4 (binary .add (read 20) (number 2)))
            (binary .multiply (read 3) (number 2))))))
          (.sequence (.expression (.assign .set (.local 16) (atIndex 4 (binary .add (read 20) (number 2))))) .skip))))

def childBody (symbols : Symbols) : Stmt :=
  declare 18 (binary .add (binary .add (read 14) (number 4)) (binary .multiply (read 17) (number 3)))
    (declare 19 (atIndex 4 (binary .add (read 18) (number 1)))
      (.sequence (reject (binary .lessEqual (read 19) (negative 1)))
        (.sequence (.ifThenElse (binary .equal (atIndex 4 (read 18)) (.constant symbols.childToken))
          tokenBody (nodeChildBody symbols)) (.sequence (increment 17 1) .skip))))

def nodeBody (symbols : Symbols) : Stmt :=
  declare 14 (atIndex 6 (read 13))
    (.sequence (reject (recordGuard 14))
      (declare 15 (atIndex 4 (binary .add (read 14) (number 3)))
        (declare 16 (atIndex 4 (binary .add (read 14) (number 1)))
          (.sequence (reject (binary .logicalOr (binary .logicalOr (binary .logicalOr
            (binary .lessEqual (read 15) (negative 1))
            (negate (binary .lessEqual (read 15)
              (binary .divide (binary .subtract (binary .subtract (read 5) (read 14)) (number 4)) (number 3)))))
            (binary .lessEqual (read 16) (negative 1)))
            (negate (binary .lessEqual (read 16) (binary .multiply (read 3) (number 2))))))
            (declare 17 (number 0)
              (.sequence (.whileLoop (binary .notEqual (read 17) (read 15)) (childBody symbols))
                (.sequence (reject (binary .notEqual (read 16) (atIndex 4 (binary .add (read 14) (number 2)))))
                  (.sequence (increment 13 1) .skip))))))))

def validateBody : Stmt :=
  declare 24 (atIndex 8 (binary .multiply (read 12) (number 2)))
    (declare 25 (atIndex 8 (binary .add (binary .multiply (read 12) (number 2)) (number 1)))
      (.sequence (reject (binary .lessEqual (read 24) (negative 1)))
        (.sequence (.ifThenElse (binary .equal (read 25) (negative 1))
          (.sequence (reject (binary .notEqual (atIndex 0 (binary .add (read 11) (read 24))) (atIndex 2 (read 12)))) .skip)
          (.sequence (reject (binary .logicalOr (binary .logicalOr
            (binary .notEqual (atIndex 2 (read 12)) (atIndex 0 (number 5)))
            (binary .notEqual (atIndex 0 (binary .add (read 11) (read 24))) (atIndex 0 (number 6))))
            (binary .notEqual (atIndex 0 (binary .add (read 11) (read 25))) (atIndex 0 (number 6))))) .skip))
          (.sequence (increment 12 1) .skip))))

def afterInitialization (symbols : Symbols) : Stmt :=
  declare 13 (number 0)
    (.sequence (.whileLoop (binary .notEqual (read 13) (read 7)) (nodeBody symbols))
      (.sequence (.expression (.assign .set (.local 12) (number 0)))
        (.sequence (.whileLoop (binary .notEqual (read 12) (read 3)) validateBody) (returned (number 0)))))

def body (symbols : Symbols) : Stmt :=
  .sequence (reject inputGuard)
    (.sequence (reject capacityGuard 2)
      (declare 10 (atIndex 0 (number 1)) (declare 11 (atIndex 0 (number 7))
        (.sequence (reject grammarGuard)
          (declare 12 (number 0) (.sequence initializeLoop (afterInitialization symbols)))))))

def parameters : List (VarId × Ty) :=
  [(0, .slice i32), (1, i32), (2, .slice i32), (3, i32), (4, .slice i32),
    (5, i32), (6, .slice i32), (7, i32), (8, .slice i32), (9, i32)]

/-- Recover the two global tags from a candidate child loop, then authenticate
its full body. The complete function is checked independently below. -/
def checkChildBody? (statement : Stmt) : Option (CheckedStatement childBody statement) := do
  let .letLocal _ _ _ (.letLocal _ _ _ (.sequence _
      (.sequence (.ifThenElse (.binary .equal _ (.constant childToken)) _
        (.sequence (.ifThenElse (.binary .logicalOr (.binary .notEqual _ (.constant childState)) _) _ _) _)) _))) := statement
    | none
  let symbols : Symbols := ⟨childToken, childState⟩
  let equal ← Core.Equality.statement? statement (childBody symbols)
  pure ⟨symbols, equal.equal⟩

def checkBody? (actual : Stmt) : Option (CheckedStatement body actual) := do
  let found ← findStatement? childBody checkChildBody? actual
  let equal ← Core.Equality.statement? actual (body found.locals)
  pure ⟨found.locals, equal.equal⟩

structure CheckedCollect {artifacts : List Artifact} (program : CheckedProgram artifacts) where
  source : CheckedSourceFunction program ["verified", "semantic_tokens"] "collect"
  symbols : Symbols
  signature : source.function.parameters = parameters ∧ source.function.returnType = i32 ∧ source.function.external = none
  bodyExact : source.function.body = some (body symbols)
  tokenTag : ParserTreeSource.constantValue program.core symbols.childToken 1
  stateTag : ParserTreeSource.constantValue program.core symbols.childState 2

def checkCollect? {artifacts : List Artifact} (program : CheckedProgram artifacts) : Option (CheckedCollect program) := do
  let source ← checkSourceFunction? program ["verified", "semantic_tokens"] "collect"
  match present : source.function.body with
  | none => none
  | some actual => do
    let found ← checkBody? actual
    if signature : source.function.parameters = parameters ∧ source.function.returnType = i32 ∧ source.function.external = none then
      let token ← ParserTreeSource.checkConstantValue? program.core found.locals.childToken 1
      let state ← ParserTreeSource.checkConstantValue? program.core found.locals.childState 2
      pure ⟨source, found.locals, signature, present.trans (congrArg some found.exactSource), token.equal, state.equal⟩
    else none

end Lanius.Extraction.SemanticTokens.Collect
