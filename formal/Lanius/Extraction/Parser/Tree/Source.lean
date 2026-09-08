import Lanius.Extraction.Parser.Derivation.Source

namespace Lanius.Extraction.ParserTreeSource

open Lanius.Core Lanius.Extraction.CoreSynthesis.Program

/-- Global coordinates come from current source lookup, not a historical
    standalone artifact. Local coordinates describe the checked lexical scopes. -/
structure Symbols where
  visit : Lanius.FunctionId
  reader : Lanius.FunctionId
  result : Lanius.FunctionId
  resultType : Lanius.TypeId
  statusBase : Lanius.ConstantId
  childState : Lanius.ConstantId
deriving Repr

private def i32 := Ty.scalar (.signed .i32)
private def number (n : Nat) : Expr := .value (.signed .i32 (Int.ofNat n))
private def returned (value : Expr) : Stmt := .sequence (.returnValue (some value)) .skip
private def guard (condition : Expr) (failure : Expr) : Stmt :=
  .ifThenElse condition (returned failure) .skip

def resultBody (typeId : Lanius.TypeId) : Stmt :=
  returned (.structValue typeId [.local 0, .local 1, .local 2])

def resultParameters : List (Lanius.VarId × Ty) := [(0, i32), (1, i32), (2, i32)]

def visitParameters : List (Lanius.VarId × Ty) :=
  [(0, .slice i32), (1, i32), (2, i32), (3, i32), (4, i32),
    (5, .slice i32), (6, i32), (7, .slice i32), (8, i32), (9, i32), (10, i32), (11, i32)]

def resultCall (symbols : Symbols) (status : Nat) (nodes words : Expr) : Expr :=
  .call symbols.result [.constant (symbols.statusBase + status), nodes, words]

def childSlot : Expr :=
  .binary .add (.binary .add (.local 10) (number 4)) (.binary .multiply (.local 15) (number 3))

def childPayload : Expr := .index (.local 5) (.binary .add (.local 16) (number 1))

def recursiveCall (symbols : Symbols) : Expr :=
  .call symbols.visit [.local 0, .local 1, .local 2, .local 3, childPayload,
    .local 5, .local 6, .local 7, .local 8, .local 14, .local 13,
    .binary .subtract (.local 11) (number 1)]

def childResult (symbols : Symbols) : Stmt :=
  .sequence (guard (.binary .notEqual (.field (.local 17) 0)
      (.constant symbols.statusBase)) (.local 17))
      (.sequence (.expression (.assign .set (.index (.local 5) (.binary .add (.local 16) (number 1)))
          (.binary .subtract (.field (.local 17) 1) (number 1))))
        (.sequence (.expression (.assign .set (.local 14) (.field (.local 17) 1)))
          (.sequence (.expression (.assign .set (.local 13) (.field (.local 17) 2))) .skip)))

def childExpansion (symbols : Symbols) : Stmt :=
  .letLocal 17 (.structure symbols.resultType) (recursiveCall symbols) (childResult symbols)

def childIteration (symbols : Symbols) : Stmt :=
  .letLocal 16 i32 childSlot
    (.sequence (.ifThenElse (.binary .equal (.index (.local 5) (.local 16))
      (.constant symbols.childState)) (childExpansion symbols) .skip)
      (.sequence (.expression (.assign .add (.local 15) (number 1))) .skip))

def visitExit (symbols : Symbols) : Stmt :=
  .sequence (guard (.binary .greaterEqual (.local 14) (.local 8))
      (resultCall symbols 2 (.local 14) (.local 13)))
    (.sequence (.expression (.assign .set (.index (.local 7) (.local 14)) (.local 10)))
      (returned (resultCall symbols 0 (.binary .add (.local 14) (number 1)) (.local 13))))

def visitChildren (symbols : Symbols) : Stmt :=
  .letLocal 13 i32
    (.binary .add (.binary .add (.local 10) (number 4)) (.binary .multiply (.local 12) (number 3)))
    (.letLocal 14 i32 (.local 9) (.letLocal 15 i32 (number 0)
      (.sequence (.whileLoop (.binary .notEqual (.local 15) (.local 12)) (childIteration symbols))
        (visitExit symbols))))

def visitBody (symbols : Symbols) : Stmt :=
  .sequence (guard (.binary .lessEqual (.local 11) (number 0))
      (resultCall symbols 3 (.local 9) (.local 10)))
    (.sequence (guard (.binary .greaterEqual (.local 9) (.local 8))
      (resultCall symbols 2 (.local 9) (.local 10)))
      (.letLocal 12 i32 (.call symbols.reader
        [.local 0, .local 1, .local 2, .local 3, .local 4, .local 5, .local 6, .local 10])
        (.sequence (guard (.binary .equal (.local 12) (.unary .negate (number 2)))
          (resultCall symbols 2 (.local 9) (.local 10)))
          (.sequence (guard (.binary .lessEqual (.local 12) (.unary .negate (number 1)))
            (resultCall symbols 1 (.local 9) (.local 10))) (visitChildren symbols)))))

def constantValue (program : Program) (id : Lanius.ConstantId) (value : Int) : Prop :=
  program.constant? id = some { id := id, type := i32, value := .signed .i32 value }

def checkConstantValue? (program : Program) (id : Lanius.ConstantId) (value : Int) :
    Option (Lanius.Core.Equality.Evidence (program.constant? id)
      (some { id := id, type := i32, value := .signed .i32 value })) :=
  match program.constant? id with
  | some ⟨actualId, .scalar (.signed .i32), .signed .i32 actualValue⟩ =>
    if same : actualId = id ∧ actualValue = value then
      some ⟨by rcases same with ⟨rfl, rfl⟩; rfl⟩
    else none
  | _ => none

/-- Exact source interface for recursive materialization, including every
    failure guard and the constructor which determines returned field order. -/
structure CheckedVisit {artifacts : List Artifact} (program : CheckedProgram artifacts) where
  source : CheckedSourceFunction program ["verified", "parse_tree"] "visit"
  reader : ParserDerivation.CheckedReader program
  constructor : CheckedSourceFunction program ["verified", "parse_tree"] "result"
  symbols : Symbols
  identities : symbols.visit = source.function.id ∧ symbols.reader = reader.source.function.id ∧
    symbols.result = constructor.function.id
  signature : source.function.parameters = visitParameters ∧
    source.function.returnType = .structure symbols.resultType ∧ source.function.external = none
  bodyExact : source.function.body = some (visitBody symbols)
  constructorSignature : constructor.function.parameters = resultParameters ∧
    constructor.function.returnType = .structure symbols.resultType ∧ constructor.function.external = none
  constructorBody : constructor.function.body = some (resultBody symbols.resultType)
  statuses : constantValue program.core symbols.statusBase 0 ∧
    constantValue program.core (symbols.statusBase + 1) 1 ∧
    constantValue program.core (symbols.statusBase + 2) 2 ∧
    constantValue program.core (symbols.statusBase + 3) 3
  childTag : constantValue program.core symbols.childState 2

def checkVisit? {artifacts : List Artifact} (program : CheckedProgram artifacts)
    (reader : ParserDerivation.CheckedReader program) : Option (CheckedVisit program) := do
  let source ← checkSourceFunction? program ["verified", "parse_tree"] "visit"
  let constructor ← checkSourceFunction? program ["verified", "parse_tree"] "result"
  match returnType : source.function.returnType, bodyPresent : source.function.body with
  | .structure typeId, some body =>
    match body with
    | .sequence (.ifThenElse _ (.sequence (.returnValue (some (.call _ [.constant depthLimit, _, _]))) .skip) .skip) _ => do
      let symbols : Symbols := ⟨source.function.id, reader.source.function.id, constructor.function.id,
        typeId, depthLimit - 3, reader.stores.locals.selector + 3⟩
      if shape : source.function.parameters = visitParameters ∧ source.function.external = none ∧
          constructor.function.parameters = resultParameters ∧ constructor.function.returnType = .structure typeId ∧
          constructor.function.external = none then
        let bodyEq ← Lanius.Core.Equality.statement? body (visitBody symbols)
        match constructorPresent : constructor.function.body with
        | none => none
        | some constructorBody => do
          let constructorEq ← Lanius.Core.Equality.statement? constructorBody (resultBody typeId)
          let success ← checkConstantValue? program.core symbols.statusBase 0
          let badInput ← checkConstantValue? program.core (symbols.statusBase + 1) 1
          let full ← checkConstantValue? program.core (symbols.statusBase + 2) 2
          let depth ← checkConstantValue? program.core (symbols.statusBase + 3) 3
          let child ← checkConstantValue? program.core symbols.childState 2
          pure ⟨source, reader, constructor, symbols, ⟨rfl, rfl, rfl⟩,
            ⟨shape.1, returnType, shape.2.1⟩, bodyPresent.trans (congrArg some bodyEq.equal),
            ⟨shape.2.2.1, shape.2.2.2.1, shape.2.2.2.2⟩,
            constructorPresent.trans (congrArg some constructorEq.equal),
            ⟨success.equal, badInput.equal, full.equal, depth.equal⟩, child.equal⟩
      else none
    | _ => none
  | _, _ => none

end Lanius.Extraction.ParserTreeSource
