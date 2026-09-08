import Lanius.Extraction.Parser.Tree.Source
import Lanius.Extraction.Source.Projection

namespace Lanius.Extraction.ParserTreeSource

open Lanius.Core Lanius.Extraction.Source Lanius.Extraction.CoreSynthesis.Program

def materializeParameters (parsedType : Lanius.TypeId) : List (Lanius.VarId × Ty) :=
  let i32 := Ty.scalar (.signed .i32)
  [(0, .structure parsedType), (1, .slice i32), (2, i32), (3, i32), (4, .slice i32),
    (5, i32), (6, .slice i32), (7, i32), (8, i32)]

def materializeBody (symbols : Symbols) (status stateCount rootState : Lanius.FunctionId)
    (parseSuccess : Lanius.ConstantId) : Stmt :=
  let zero := Expr.value (.signed .i32 0)
  let negativeOne := Expr.unary .negate (.value (.signed .i32 1))
  let invalid := Expr.binary .logicalOr
    (.binary .logicalOr (.binary .notEqual (.call status [.local 0]) (.constant parseSuccess))
      (.binary .lessEqual (.local 5) negativeOne))
    (.binary .lessEqual (.local 7) negativeOne)
  .sequence (.ifThenElse invalid
    (.sequence (.returnValue (some (resultCall symbols 1 zero zero))) .skip) .skip)
    (.sequence (.returnValue (some (.call symbols.visit
      [.local 1, .local 2, .local 3, .call stateCount [.local 0], .call rootState [.local 0],
        .local 4, .local 5, .local 6, .local 7, zero, zero, .local 8]))) .skip)

/-- Check the public wrapper and its real parser accessor callees, including
    their shared result type and the parser success constant. -/
structure CheckedMaterialize (visit : CheckedVisit program) where
  source : CheckedSourceFunction program ["verified", "parse_tree"] "materialize"
  parsedType : Lanius.TypeId
  status : CheckedProjection program ["verified", "parser"] "parse_status" parsedType 0
  stateCount : CheckedProjection program ["verified", "parser"] "parse_state_count" parsedType 1
  rootState : CheckedProjection program ["verified", "parser"] "parse_root_state" parsedType 2
  parseSuccess : Lanius.ConstantId
  success : constantValue program.core parseSuccess 0
  signature : source.function.parameters = materializeParameters parsedType ∧
    source.function.returnType = .structure visit.symbols.resultType ∧ source.function.external = none
  body : source.function.body = some (materializeBody visit.symbols status.source.function.id
    stateCount.source.function.id rootState.source.function.id parseSuccess)

def checkMaterialize? (visit : CheckedVisit program) : Option (CheckedMaterialize visit) := do
  let source ← checkSourceFunction? program ["verified", "parse_tree"] "materialize"
  match source.function.parameters, present : source.function.body with
  | (_, .structure parsedType) :: _, some body => do
    match body with
    | .sequence (.ifThenElse (.binary .logicalOr
        (.binary .logicalOr (.binary .notEqual _ (.constant parseSuccess)) _) _) _ _) _ => do
      let status ← checkProjection? program ["verified", "parser"] "parse_status" parsedType 0
      let stateCount ← checkProjection? program ["verified", "parser"] "parse_state_count" parsedType 1
      let rootState ← checkProjection? program ["verified", "parser"] "parse_root_state" parsedType 2
      let success ← checkConstantValue? program.core parseSuccess 0
      if signature : source.function.parameters = materializeParameters parsedType ∧
          source.function.returnType = .structure visit.symbols.resultType ∧ source.function.external = none then
        let exactBody ← Lanius.Core.Equality.statement? body (materializeBody visit.symbols status.source.function.id
          stateCount.source.function.id rootState.source.function.id parseSuccess)
        pure ⟨source, parsedType, status, stateCount, rootState, parseSuccess, success.equal,
          signature, present.trans (congrArg some exactBody.equal)⟩
      else none
    | _ => none
  | _, _ => none

end Lanius.Extraction.ParserTreeSource
