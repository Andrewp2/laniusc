import Lanius.Extraction.CoreSynthesis.Program
import Lanius.FunctionalViewCoreStatefulReification
import Lanius.Semantics
import Lanius.Extraction.Source.Statement
import Lanius.Core.Equality

namespace Lanius.Extraction.ParserDerivation

open Lanius.Core Lanius.FunctionalView.Core
open Lanius.Extraction.CoreSynthesis.Program

structure ChildStores where
  output : Lanius.VarId
  slot : Lanius.VarId
  tag : Lanius.VarId
  payload : Lanius.VarId
  workspace : Lanius.VarId
  base : Lanius.VarId
  current : Lanius.VarId
  accessor : Lanius.FunctionId
  selector : Lanius.ConstantId
  rest : Stmt

def ChildStores.store (stores : ChildStores) (offset : Nat) : Stmt :=
  let index := if offset = 0 then Expr.local stores.slot else
    .binary .add (.local stores.slot) (.value (.signed .i32 (Int.ofNat offset)))
  let right := if offset = 0 then Expr.local stores.tag else
    if offset = 1 then .local stores.payload else
      .call stores.accessor [.local stores.workspace, .local stores.base,
        .local stores.current, .constant stores.selector]
  .expression (.assign .set (.index (.local stores.output) index) right)

def ChildStores.fragment (stores : ChildStores) : Stmt :=
  .sequence (stores.store 0) (.sequence (stores.store 1) (stores.store 2))

def ChildStores.body (stores : ChildStores) : Stmt :=
  .sequence (stores.store 0) (.sequence (stores.store 1)
    (.sequence (stores.store 2) stores.rest))

/-- Recognize the actual three-store source region and retain exact equality,
    including shared output/slot locals and the untouched continuation. -/
def checkChildStores? : (statement : Stmt) →
    Option (Lanius.Extraction.Source.CheckedStatement ChildStores.body statement)
  | .sequence (.expression (.assign .set (.index (.local output) (.local slot)) (.local tag)))
      (.sequence (.expression (.assign .set (.index (.local output1)
        (.binary .add (.local slot1) (.value (.signed .i32 1)))) (.local payload)))
        (.sequence (.expression (.assign .set (.index (.local output2)
          (.binary .add (.local slot2) (.value (.signed .i32 2))))
          (.call accessor [.local workspace, .local base, .local current, .constant selector]))) rest)) =>
    if same : output1 = output ∧ output2 = output ∧ slot1 = slot ∧ slot2 = slot then
      some ⟨⟨output, slot, tag, payload, workspace, base, current, accessor, selector, rest⟩, by
        rcases same with ⟨rfl, rfl, rfl, rfl⟩
        rfl⟩
    else none
  | _ => none

def findChildStores? := Lanius.Extraction.Source.findStatement? ChildStores.body checkChildStores?

structure CheckedCursorTail (stores : ChildStores) where
  previous : Lanius.VarId
  remaining : Lanius.VarId
  exactTail : stores.rest =
    .sequence (.expression (.assign .set (.local stores.current) (.local previous)))
      (.sequence (.expression (.assign .subtract (.local remaining)
        (.value (.signed .i32 1)))) .skip)

def checkCursorTail? (stores : ChildStores) : Option (CheckedCursorTail stores) :=
  match tailEq : stores.rest with
  | .sequence (.expression (.assign .set (.local current) (.local previous)))
      (.sequence (.expression (.assign .subtract (.local remaining)
        (.value (.signed .i32 1)))) .skip) =>
    if same : current = stores.current then
      some ⟨previous, remaining, by simpa only [same] using tailEq⟩
    else none
  | _ => none

/-- The complete inspected iteration, parameterized by its recovered locals
    and the contiguous parser field-selector block. -/
def iterationBody (stores : ChildStores) (tail : CheckedCursorTail stores)
    (production origin outputOffset tokenCount : Lanius.VarId)
    (fieldBase : Lanius.ConstantId) : Stmt :=
  let i32 := Ty.scalar (.signed .i32)
  let one := Expr.value (.signed .i32 1)
  let negativeOne := Expr.unary .negate one
  let reject := Stmt.sequence (.returnValue (some negativeOne)) .skip
  let guard := fun condition => Stmt.ifThenElse condition reject .skip
  let readField := fun field => Expr.call stores.accessor
    [.local stores.workspace, .local stores.base, .local stores.current, .constant (fieldBase + field)]
  let mismatch := fun field localId => Expr.binary .notEqual (readField field) (.local localId)
  let metadata := Expr.binary .logicalOr
    (.binary .logicalOr (mismatch 1 tail.remaining) (mismatch 0 production)) (mismatch 2 origin)
  let predecessor := Expr.binary .logicalOr
    (.binary .logicalOr (.binary .lessEqual (.local tail.previous) negativeOne)
      (.binary .greaterEqual (.local tail.previous) (.local stores.current)))
    (.binary .lessEqual (.local stores.payload) negativeOne)
  let childBranch := Stmt.ifThenElse (.binary .equal (.local stores.tag) (.constant (fieldBase + 10)))
    (.sequence (guard (.binary .greaterEqual (.local stores.payload) (.local tokenCount))) .skip)
    (.sequence (guard (.binary .logicalOr
      (.binary .notEqual (.local stores.tag) (.constant (fieldBase + 11)))
      (.binary .greaterEqual (.local stores.payload) (.local stores.current)))) .skip)
  let slotValue := Expr.binary .add (.binary .add (.local outputOffset) (.value (.signed .i32 4)))
    (.binary .multiply (.binary .subtract (.local tail.remaining) one) (.value (.signed .i32 3)))
  .sequence (guard metadata)
    (.letLocal tail.previous i32 (readField 5)
      (.letLocal stores.tag i32 (readField 6)
        (.letLocal stores.payload i32 (readField 7)
          (.sequence (guard predecessor) (.sequence childBranch
            (.letLocal stores.slot i32 slotValue stores.body))))))

def readerLoop (stores : ChildStores) (tail : CheckedCursorTail stores)
    (production origin outputOffset tokenCount : Lanius.VarId) (fieldBase : Lanius.ConstantId) : Stmt :=
  .whileLoop (.binary .notEqual (.local tail.remaining) (.value (.signed .i32 0)))
    (iterationBody stores tail production origin outputOffset tokenCount fieldBase)

def readerExitCondition (stores : ChildStores) (production origin : Lanius.VarId)
    (fieldBase : Lanius.ConstantId) : Expr :=
  let readField := fun field => Expr.call stores.accessor
    [.local stores.workspace, .local stores.base, .local stores.current, .constant (fieldBase + field)]
  let mismatch := fun field expected => Expr.binary .notEqual (readField field) expected
  .binary .logicalOr
    (.binary .logicalOr
      (.binary .logicalOr
        (.binary .logicalOr (mismatch 1 (.value (.signed .i32 0))) (mismatch 0 (.local production)))
        (mismatch 2 (.local origin)))
      (mismatch 6 (.constant (fieldBase + 9))))
    (mismatch 5 (.unary .negate (.value (.signed .i32 1))))

def readerExit (stores : ChildStores) (production origin count : Lanius.VarId)
    (fieldBase : Lanius.ConstantId) : Stmt :=
  .sequence (.ifThenElse (readerExitCondition stores production origin fieldBase)
    (.sequence (.returnValue (some (.unary .negate (.value (.signed .i32 1))))) .skip) .skip)
    (.sequence (.returnValue (some (.local count))) .skip)

def readerWalk (stores : ChildStores) (tail : CheckedCursorTail stores)
    (production origin outputOffset tokenCount count stateId : Lanius.VarId)
    (fieldBase : Lanius.ConstantId) : Stmt :=
  .letLocal stores.current (.scalar (.signed .i32)) (.local stateId)
    (.letLocal tail.remaining (.scalar (.signed .i32)) (.local count)
      (.sequence (readerLoop stores tail production origin outputOffset tokenCount fieldBase)
        (readerExit stores production origin count fieldBase)))

def readerHeader (stores : ChildStores)
    (production origin outputOffset count stateId : Lanius.VarId)
    (fieldBase : Lanius.ConstantId) (rest : Stmt) : Stmt :=
  let index := fun offset : Nat => if offset = 0 then Expr.local outputOffset else
    .binary .add (.local outputOffset) (.value (.signed .i32 (Int.ofNat offset)))
  let right := fun offset : Nat => if offset = 0 then Expr.local production else
    if offset = 1 then .local origin else if offset = 2 then
      .call stores.accessor [.local stores.workspace, .local stores.base, .local stateId,
        .constant (fieldBase + 3)] else .local count
  let store := fun offset => Stmt.expression (.assign .set (.index (.local stores.output) (index offset)) (right offset))
  .sequence (store 0) (.sequence (store 1) (.sequence (store 2) (.sequence (store 3) rest)))

def rangeCondition (value limit : Lanius.VarId) : Expr :=
  .binary .logicalOr
    (.binary .lessEqual (.local value) (.unary .negate (.value (.signed .i32 1))))
    (.unary .logicalNot (.binary .lessEqual (.local value) (.local limit)))

def capacityCondition (capacity offset count : Lanius.VarId) : Expr :=
  .binary .logicalOr
    (.binary .lessEqual (.binary .subtract (.local capacity) (.local offset)) (.value (.signed .i32 3)))
    (.unary .logicalNot (.binary .lessEqual (.local count)
      (.binary .divide
        (.binary .subtract (.binary .subtract (.local capacity) (.local offset)) (.value (.signed .i32 4)))
        (.value (.signed .i32 3)))))

def readerRoots (stores : ChildStores) (tail : CheckedCursorTail stores)
    (production origin outputOffset tokenCount count stateId : Lanius.VarId)
    (fieldBase : Lanius.ConstantId) : Stmt :=
  let readField := fun selector => Expr.call stores.accessor
    [.local stores.workspace, .local stores.base, .local stateId, .constant selector]
  .letLocal production (.scalar (.signed .i32)) (readField fieldBase)
    (.letLocal origin (.scalar (.signed .i32)) (readField (fieldBase + 2))
      (readerHeader stores production origin outputOffset count stateId fieldBase
        (readerWalk stores tail production origin outputOffset tokenCount count stateId fieldBase)))

def readerCount (stores : ChildStores) (tail : CheckedCursorTail stores)
    (production origin outputOffset tokenCount count stateId stateCount capacity : Lanius.VarId)
    (fieldBase : Lanius.ConstantId) : Stmt :=
  let reject := fun n => Stmt.sequence
    (.returnValue (some (.unary .negate (.value (.signed .i32 n))))) .skip
  .letLocal count (.scalar (.signed .i32))
    (.call stores.accessor [.local stores.workspace, .local stores.base, .local stateId, .constant (fieldBase + 1)])
    (.sequence (.ifThenElse (rangeCondition count stateCount) (reject 1) .skip)
      (.sequence (.ifThenElse (rangeCondition outputOffset capacity) (reject 2) .skip)
        (.sequence (.ifThenElse (capacityCondition capacity outputOffset count) (reject 2) .skip)
          (readerRoots stores tail production origin outputOffset tokenCount count stateId fieldBase))))

def inputCondition (token workspace count state : Lanius.VarId) : Expr :=
  let negative := fun localId => Expr.binary .lessEqual (.local localId)
    (.unary .negate (.value (.signed .i32 1)))
  .binary .logicalOr
    (.binary .logicalOr
      (.binary .logicalOr
        (.binary .logicalOr
          (.binary .logicalOr (negative token)
            (.binary .greaterEqual (.local token) (.value (.signed .i32 536870912))))
          (negative workspace)) (negative count)) (negative state))
    (.binary .greaterEqual (.local state) (.local count))

def workspaceCondition (base capacity count : Lanius.VarId) (stateWordsSelector : Lanius.ConstantId) : Expr :=
  .binary .logicalOr
    (.unary .logicalNot (.binary .lessEqual (.local base) (.local capacity)))
    (.unary .logicalNot (.binary .lessEqual (.local count)
      (.binary .divide (.binary .subtract (.local capacity) (.local base)) (.constant stateWordsSelector))))

def readerEntry (stores : ChildStores) (tail : CheckedCursorTail stores)
    (production origin outputOffset tokenCount count stateId stateCount capacity workspaceLength : Lanius.VarId)
    (fieldBase : Lanius.ConstantId) : Stmt :=
  let reject := Stmt.sequence (.returnValue (some (.unary .negate (.value (.signed .i32 1))))) .skip
  .sequence (.ifThenElse (inputCondition tokenCount workspaceLength stateCount stateId) reject .skip)
    (.letLocal stores.base (.scalar (.signed .i32))
      (.binary .multiply
        (.binary .add (.binary .multiply (.local tokenCount) (.value (.signed .i32 2)))
          (.value (.signed .i32 1))) (.constant (fieldBase - 4)))
      (.sequence (.ifThenElse (workspaceCondition stores.base workspaceLength stateCount (fieldBase - 1)) reject .skip)
        (readerCount stores tail production origin outputOffset tokenCount count stateId stateCount capacity fieldBase)))

def readerParameters : List (Lanius.VarId × Ty) :=
  let i32 := Ty.scalar (.signed .i32)
  [(0, .slice i32), (1, i32), (2, i32), (3, i32), (4, i32),
   (5, .slice i32), (6, i32), (7, i32)]

/-- The inspected locals whose scopes must not shadow each other. Internal
    names may vary; only the public parameter and metadata coordinates are fixed. -/
def readerLocals (stores : ChildStores) (tail : CheckedCursorTail stores) : List Lanius.VarId :=
  [stores.base, 9, 10, 11, stores.current, tail.remaining, tail.previous,
    stores.tag, stores.payload, stores.slot, 0, 1, 2, 3, 4, 5, 6, 7]

/-- The current source reader, with its body and exact stateful lowering
    retained for execution proofs. No standalone historical artifact is used. -/
structure CheckedReader {artifacts : List Artifact} (program : CheckedProgram artifacts) where
  source : CheckedSourceFunction program ["verified", "parser"] "copy_derivation"
  parameters : source.function.parameters = readerParameters
  returnType : source.function.returnType = .scalar (.signed .i32)
  internal : source.function.external = none
  body : Stmt
  bodyPresent : source.function.body = some body
  stores : Lanius.Extraction.Source.LocatedStatement ChildStores.body body
  cursorTail : CheckedCursorTail stores.locals
  bufferParameters : stores.locals.workspace = 0 ∧ stores.locals.output = 5
  namesDistinct : (readerLocals stores.locals cursorTail).Nodup
  bodyExact : body = readerEntry stores.locals cursorTail 10 11 7 2 9 4 3 6 1 (stores.locals.selector - 8)
  accessor : CheckedSourceFunction program ["verified", "parser"] "state_value"
  accessorIdentity : stores.locals.accessor = accessor.function.id
  selectorValue : program.core.constant? stores.locals.selector = some {
    id := stores.locals.selector, type := .scalar (.signed .i32), value := .signed .i32 8 }
  view : Stateful.Reification.ReifiedCommand program.core source.function.returnType
    (Lanius.Typing.parameterContext source.function.parameters) false
    (identityLayout (arity := 8)) 8 body

def checkReader? {artifacts : List Artifact} (program : CheckedProgram artifacts) :
    Option (CheckedReader program) := do
  let source ← checkSourceFunction? program ["verified", "parser"] "copy_derivation"
  if signature : source.function.parameters = readerParameters ∧
      source.function.returnType = .scalar (.signed .i32) ∧
      source.function.external = none then
    match bodyPresent : source.function.body with
    | none => none
    | some body => do
      let accessor ← checkSourceFunction? program ["verified", "parser"] "state_value"
      let stores ← Lanius.Extraction.Source.findStatement? ChildStores.body (fun statement => do
        let candidate ← checkChildStores? statement
        if candidate.locals.accessor != accessor.function.id then none else
          match program.core.constant? candidate.locals.selector with
          | some ⟨_, .scalar (.signed .i32), .signed .i32 8⟩ => some candidate
          | _ => none) body
      let cursorTail ← checkCursorTail? stores.locals
      let expectedBody := readerEntry stores.locals cursorTail 10 11 7 2 9 4 3 6 1 (stores.locals.selector - 8)
      let bodyExact ← Lanius.Core.Equality.statement? body expectedBody
      match selectorFound : program.core.constant? stores.locals.selector with
      | some ⟨constantId, .scalar (.signed .i32), .signed .i32 8⟩ =>
        if identities : stores.locals.accessor = accessor.function.id ∧
            constantId = stores.locals.selector ∧
            (stores.locals.workspace = 0 ∧ stores.locals.output = 5) ∧
            (readerLocals stores.locals cursorTail).Nodup then do
          let view ← Stateful.Reification.reifyCommand? program.core source.function.returnType
            (Lanius.Typing.parameterContext source.function.parameters) false
            (identityLayout (arity := 8)) 8 body
          pure ⟨source, signature.1, signature.2.1, signature.2.2, body, bodyPresent, stores,
            cursorTail, identities.2.2.1, identities.2.2.2, bodyExact.equal, accessor, identities.1,
            by simpa only [identities.2.1] using selectorFound, view⟩
        else none
      | _ => none
  else none

/-- Discharge the slot-scope execution rule's name-separation premise from
    the actual inspected source, rather than relying on naming convention. -/
theorem CheckedReader.slot_distinct (reader : CheckedReader program)
    (localId : Lanius.VarId)
    (member : localId ∈ [reader.stores.locals.output, reader.stores.locals.workspace,
      reader.stores.locals.base, reader.stores.locals.tag, reader.stores.locals.payload,
      reader.stores.locals.current, reader.cursorTail.remaining, reader.cursorTail.previous]) :
    reader.stores.locals.slot ≠ localId := by
  have names := reader.namesDistinct
  obtain ⟨workspace, output⟩ := reader.bufferParameters
  simp only [List.mem_cons, List.not_mem_nil, or_false] at member
  rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
    simp_all [readerLocals, List.nodup_cons, ne_comm]

/-- The checked signature binds caller values to the exact locals used by
    the reified body. Slice capacities remain part of the supplied values. -/
theorem CheckedReader.bind_parameters (reader : CheckedReader program)
    (workspace workspaceLength tokenCount stateCount stateId output outputLength
      outputOffset : Value) :
    Lanius.Semantics.bindParameters reader.source.function.parameters
      [workspace, workspaceLength, tokenCount, stateCount, stateId, output,
       outputLength, outputOffset] =
      some [(0, workspace), (1, workspaceLength), (2, tokenCount), (3, stateCount),
        (4, stateId), (5, output), (6, outputLength), (7, outputOffset)] := by
  rw [reader.parameters]
  rfl

end Lanius.Extraction.ParserDerivation
