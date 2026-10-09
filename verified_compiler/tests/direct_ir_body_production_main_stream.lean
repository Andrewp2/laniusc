import verified_compiler.tests.direct_ir_body_production_main_statement
import verified_compiler.tests.direct_ir_catalog_append_contract

namespace IRBodyProductionProof

open Lanius Lanius.Core Lanius.Semantics IRShapeProof IRChildrenProof
open IREventStoreProof IREventWriteProof IRCatalogAppendProof

/-- Logical source-selected output. Signed minimum uses Integer, not a
    nonrepresentable positive i32 followed by a negation event. -/
inductive ReturnBody where
  | void
  | boolean (value : Bool)
  | integer (value : Int32)
  | negative (magnitude : Int32)

def ReturnBody.count : ReturnBody → Nat
  | .void => 1 | .negative _ => 3 | _ => 2
def ReturnBody.leaf : ReturnBody → Value
  | .boolean flag => IREventStoreProof.boolean flag
  | .integer value | .negative value => IREventStoreProof.integer value.toBitVec
  | .void => returnEvent false
def ReturnBody.event (body : ReturnBody) (index : Nat) : Value :=
  if index = 0 then returnEvent (match body with | .void => false | _ => true)
  else match body with | .negative _ => if index = 1 then negateEvent else body.leaf | _ => body.leaf
def ReturnBody.kind (_body : ReturnBody) (index : Nat) : Kind :=
  if index = 0 then .StatementNode else .ExpressionNode
def ReturnBody.arity (body : ReturnBody) (index : Nat) : Int :=
  match body with
  | .void => 0
  | .negative _ => if index ≤ 1 then 1 else 0
  | _ => if index = 0 then 1 else 0
def ReturnBody.rule (body : ReturnBody) (index : Nat) : Rule :=
  if body.arity index = 0 then .NoChildren else .Expressions
def ReturnBody.request (body : ReturnBody) (arguments : Arguments) (annotations : Nat → IRTypeRefProof.Reference) : Model := {
  arguments with
  eventCount := Int32.ofNat body.count
  previous := fun _ => ⟨0, 0, .Invalid, .unit⟩
  events := body.event
  annotations
  kinds := body.kind
  arities := body.arity
  rules := body.rule }

theorem ReturnBody.requestCount (body : ReturnBody) :
    (body.request arguments annotations).request = body.count := by
  cases body <;> rfl

/-- Actual output descriptors and signature; catalog storage is supplied by
    the maintained catalog rather than an intermediate producer state. -/
def streamRequest (output : Context state) (id : Int32) (result : IRTypeRefProof.Reference)
    (body : ReturnBody) (annotations : Nat → IRTypeRefProof.Reference) : Model :=
  body.request {
    rowsAddress := 0, rowsLength := 0, countAddress := 0, countLength := 0
    capacity := 0, id, parameters := 0, result, next := 0
    eventsAddress := output.events, eventsLength := output.capacity
    resultAddress := output.types, resultLength := output.typesLength, hasResultTypes := output.enabled
    sourceCapacity := Int32.ofNat output.capacity, eventCount := 0 } annotations

/-- The finite source grammar fixes the child chains independently of the
    validator or builder execution. -/
theorem ReturnBody.canonical (body : ReturnBody) : (body.request arguments annotations).Canonical := by
  refine ⟨fun _ => body.count, ?_, ?_⟩
  · intro index inside
    rw [body.requestCount] at inside
    simp only [Model.Node, body.requestCount]
    dsimp only [ReturnBody.request]
    cases body with
    | void =>
      have zero : index = 0 := by change index < 1 at inside; omega
      subst index
      dsimp only [ReturnBody.count, ReturnBody.arity, ReturnBody.kind, ReturnBody.rule]
      exact ⟨by decide, by decide, by decide, 1, rfl, .nil⟩
    | boolean value | integer value =>
      have choices : index = 0 ∨ index = 1 := by change index < 2 at inside; omega
      rcases choices with rfl | rfl
      all_goals dsimp only [ReturnBody.count, ReturnBody.arity, ReturnBody.kind, ReturnBody.rule]
      · exact ⟨by decide, by decide, by decide, 2, rfl,
          .cons (by decide) rfl (by decide) (by decide) .nil⟩
      · exact ⟨by decide, by decide, by decide, 2, rfl, .nil⟩
    | negative value =>
      have choices : index = 0 ∨ index = 1 ∨ index = 2 := by change index < 3 at inside; omega
      rcases choices with rfl | rfl | rfl
      all_goals dsimp only [ReturnBody.count, ReturnBody.arity, ReturnBody.kind, ReturnBody.rule]
      · exact ⟨by decide, by decide, by decide, 3, rfl,
          .cons (by decide) rfl (by decide) (by decide) .nil⟩
      · exact ⟨by decide, by decide, by decide, 3, rfl,
          .cons (by decide) rfl (by decide) (by decide) .nil⟩
      · exact ⟨by decide, by decide, by decide, 3, rfl, .nil⟩
  · rw [body.requestCount]

#print axioms ReturnBody.canonical

end IRBodyProductionProof
