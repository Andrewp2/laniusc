import Lanius.Core.Relocation.Program
import Lanius.Core.Relocation.Permutation
import Lanius.Semantics.Relocation.State
import Lanius.Semantics.Relocation.Pattern
import Lanius.Semantics.Relocation.Access
import Lanius.Semantics.Relocation.Views
import Lanius.Semantics.Relocation.Outcome
import Lanius.Semantics.Relocation.Execution.Arguments
import Lanius.Semantics.Relocation.Execution.Match
import Lanius.Semantics.Relocation.Execution.Statement
import Lanius.Semantics.Relocation.Execution.Iteration
import Lanius.Semantics.Relocation.Execution

open Lanius Lanius.Core Lanius.Core.Relocation

private def symbols : Symbols := ⟨rotateTypes 1 3, (10 + ·), (20 + ·)⟩
private def inverse : Symbols := ⟨rotateTypes 3 1, id, id⟩

example : ([0, 1, 2, 3, 4].map symbols.typeId) = [1, 2, 3, 0, 4] := by decide
example : Function.Injective symbols.typeId := rotateTypes_injective 1 3

-- Includes a pre-existing caller value outside the module's original type
-- interval. A plain offset cannot be inverted on every such caller state.
private def caller : Semantics.State := {
  cells := [⟨0, some (.structure 3 [.signed .i32 42])⟩]
  locals := [(7, 0)]
  nextCell := 1
}

example : Semantics.Relocation.state inverse (Semantics.Relocation.state symbols caller) = caller :=
  Semantics.Relocation.state_leftInverse inverse symbols (rotateTypes_inverse 1 3) caller

private def original : Program := {
  functions := [⟨0, [(4, .scalar (.signed .i32))], .structure 0,
    some (.returnValue (some (.structValue 0 [
      .binary .add (.constant 0) (.local 4)]))), none⟩]
  constants := [⟨0, .scalar (.signed .i32), .signed .i32 7⟩]
  structures := [⟨0, [.scalar (.signed .i32)]⟩]
}

private def linked : Program := {
  functions := ⟨0, [], .unit, some .skip, none⟩ :: original.functions.map (function symbols)
  constants := ⟨0, .scalar (.signed .i32), .signed .i32 99⟩ :: original.constants.map (constant symbols)
  structures := [⟨1, [.scalar (.signed .i32)]⟩]
}

example : (checkProgram? symbols original linked).isSome = true := by native_decide

private def wrongConstant : Program := { linked with
  constants := [⟨20, .scalar (.signed .i32), .signed .i32 8⟩] }

example : (checkProgram? symbols original wrongConstant).isSome = false := by decide

private def wrongReference : Program := { linked with
  functions := [⟨10, [(4, .scalar (.signed .i32))], .structure 1,
    some (.returnValue (some (.structValue 1 [
      .binary .add (.constant 0) (.local 4)]))), none⟩] }

example : (checkProgram? symbols original wrongReference).isSome = false := by native_decide
example : (checkProgram? symbols original { linked with functions := [] }).isSome = false := by decide
example : (checkProgram? symbols original { linked with target := ⟨.bits32⟩ }).isSome = false := by decide

example : (Equality.value? (.structure 1 [.signed .i32 4]) (.structure 2 [.signed .i32 4])).isSome = false := by decide
example : (Equality.expression? (.call 10 [.constant 20]) (.call 11 [.constant 20])).isSome = false := by native_decide

#print axioms checkProgram?
#print axioms Semantics.Relocation.state_leftInverse
#print axioms Semantics.Relocation.state_wellFormed
#print axioms Semantics.Relocation.readCellProjection
#print axioms rotateTypes_inverse

-- Nested enum matching must preserve both the successful payload bindings and
-- rejection of a distinct type, including a caller type outside this module.
private def nestedPattern : Pattern := .enumVariant 0 2 [
  .enumVariant 2 1 [.bind 8, .literal (.signed .i32 42)]]
private def nestedValue : Value := .enumeration 0 2 [
  .enumeration 2 1 [.structure 3 [.signed .i32 7], .signed .i32 42]]

example : (Semantics.matchPattern nestedPattern nestedValue ==
    some [(8, .structure 3 [.signed .i32 7])]) = true := by native_decide

example : (Semantics.matchPattern (pattern symbols nestedPattern) (value symbols nestedValue) ==
    some [(8, .structure 0 [.signed .i32 7])]) = true := by native_decide

example : (Semantics.matchPattern (pattern symbols (.enumVariant 0 2 []))
    (value symbols (.enumeration 3 2 []))).isNone = true := by native_decide

private def nestedArray : Value := .structure 0 [.array [.structure 3 [], .signed .i32 42]]

example : (match Semantics.replaceProjectedValue (value symbols nestedArray) [.field 0, .index 1]
    (value symbols (.structure 2 [])) with
    | .ok result => result == .structure 1 [.array [.structure 0 [], .structure 3 []]]
    | .error _ => false) = true := by native_decide

example : (match Semantics.replaceProjectedValue (value symbols nestedArray) [.field 0, .index 2]
    .unit with
    | .error .arrayBounds => true
    | _ => false) = true := by native_decide

#print axioms Semantics.Relocation.binary
#print axioms Semantics.Relocation.assignment
#print axioms Semantics.Relocation.replaceProjectedValue
#print axioms Semantics.Relocation.writeResolvedPlace
#print axioms Semantics.Relocation.bindParameters
#print axioms Semantics.Relocation.matchPattern
#print axioms Semantics.Relocation.expressionPlace
#print axioms Semantics.Relocation.sliceValues
#print axioms Semantics.Relocation.syncToHeap
#print axioms Semantics.Relocation.syncFromHeap
#print axioms Semantics.Relocation.outcome_leftInverse
#print axioms Semantics.Relocation.mapRawI32Slice
#print axioms Semantics.Relocation.Execution.expressions
#print axioms Semantics.Relocation.Execution.arms
#print axioms Semantics.Relocation.Execution.statement
#print axioms Semantics.Relocation.Execution.forValues
#print axioms Semantics.Relocation.Execution.forRange
#print axioms Semantics.Relocation.Execution.atFuel
#print axioms Semantics.Relocation.Execution.evaluates
#print axioms Semantics.Relocation.Execution.executes
#print axioms Semantics.Relocation.Execution.checkInternal?

example : (Semantics.Relocation.Execution.checkInternal? original).isSome = true := by decide
example : (Semantics.Relocation.Execution.checkInternal? { original with
    functions := [⟨0, [], .unit, none, some (.opaque 0)⟩] }).isSome = false := by decide

example : [0, 1, 2, 3, 4].map (permuteTypes [(0, 3), (1, 4)]) = [3, 4, 2, 0, 1] := by decide
example : permuteTypes [(1, 4), (0, 3)] (permuteTypes [(0, 3), (1, 4)] 1) = 1 := by decide
#print axioms permuteTypes_inverse

private def callObservation : Semantics.Outcome Value → Option (Value × Option Value)
  | .done result after => some (result, after.local? 7)
  | _ => none

-- Exercises the assembled evaluator: argument evaluation, constant lookup,
-- arithmetic, structure construction, return, and restoration of caller locals.
example : (callObservation (Semantics.evalExpr 30 original caller
    (.call 0 [.value (.signed .i32 42)])) ==
      some (.structure 0 [.signed .i32 49], some (.structure 3 [.signed .i32 42]))) = true := by native_decide

example : (callObservation (Semantics.evalExpr 30 linked (Semantics.Relocation.state symbols caller)
    (expression symbols (.call 0 [.value (.signed .i32 42)]))) ==
      some (.structure 1 [.signed .i32 49], some (.structure 0 [.signed .i32 42]))) = true := by native_decide
