import SelfCore
import Lanius.Core.Bindings
import Lanius.Semantics.CallProof
import Lanius.Semantics.PureProof
import Lanius.Semantics.SourceValue
import Lanius.Semantics.LocalPair
import Lanius.Semantics.ScalarAssignment
import Lanius.Semantics.LoopRun
import Lanius.Typing

namespace IRReturnsProof
open Lanius Lanius.Core Lanius.Memory Lanius.Semantics Lanius.Typing

private def shapeSource := Extracted.«ir::body_tree».Functions.«shape».core
private def nodeSource := Extracted.«ir::body_tree».Functions.«node».core
private def kindSource := Extracted.«ir::body_tree».Functions.«kind».core
private def childSource := Extracted.«ir::body_tree».Functions.«child».core
private def returnSource := Extracted.«ir::body_tree».Functions.«definitely_returns».core
private def eventType := ((shapeSource.parameters[0]?).getD (0, .unit)).2
private def statementKind := source_value Extracted.«ir::body_tree».Types.«NodeKind».«StatementNode» []
private def invalidKind := source_value Extracted.«ir::body_tree».Types.«NodeKind».«InvalidNode» []

inductive Tag | skip | expression | sequence | letValue | letNone | branch | loop | returnVoid | returnValue
  deriving DecidableEq
def Tag.arity : Tag → Nat
  | .skip | .returnVoid => 0 | .expression | .letNone | .returnValue => 1
  | .sequence | .letValue | .loop => 2 | .branch => 3
def Tag.event (payload : Value) : Tag → Value
  | .skip => source_value Extracted.«ir::body_events».Types.«Event».«StatementSkip» []
  | .expression => source_value Extracted.«ir::body_events».Types.«Event».«StatementExpression» []
  | .sequence => source_value Extracted.«ir::body_events».Types.«Event».«StatementSequence» []
  | .letValue => source_value Extracted.«ir::body_events».Types.«Event».«StatementLet» [payload]
  | .letNone => source_value Extracted.«ir::body_events».Types.«Event».«StatementLetUninitialized» [payload]
  | .branch => source_value Extracted.«ir::body_events».Types.«Event».«StatementIf» []
  | .loop => source_value Extracted.«ir::body_events».Types.«Event».«StatementWhile» []
  | .returnVoid => source_value Extracted.«ir::body_events».Types.«Event».«StatementReturnVoid» []
  | .returnValue => source_value Extracted.«ir::body_events».Types.«Event».«StatementReturnValue» []
def Tag.rule : Tag → Value
  | .sequence | .letNone => source_value Extracted.«ir::body_tree».Types.«ChildRule».«Statements» []
  | .letValue | .branch | .loop => source_value Extracted.«ir::body_tree».Types.«ChildRule».«ExpressionThenStatements» []
  | .expression | .returnValue => source_value Extracted.«ir::body_tree».Types.«ChildRule».«Expressions» []
  | _ => source_value Extracted.«ir::body_tree».Types.«ChildRule».«NoChildren» []
def shapeValue (tag : Tag) : Value := source_value Extracted.«ir::body_tree».Types.«Shape».mk
  [statementKind, .signed .i32 tag.arity, tag.rule]

@[core_pure_rule] theorem actualNode (kind rule : Value) (arity : Int) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call nodeSource.id
      ([kind, .signed .i32 arity, rule].map Expr.value))
      (source_value Extracted.«ir::body_tree».Types.«Shape».mk [kind, .signed .i32 arity, rule]) after ∧ PureFrame before after := by
  core_call_pure nodeSource as callee
  core_pure

@[core_pure_rule] theorem actualShape (tag : Tag) (payload : Value) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (.call shapeSource.id [.value (tag.event payload)])
      (shapeValue tag) after ∧ PureFrame before after := by
  cases tag <;> dsimp only [Tag.event, Tag.arity, Tag.rule, shapeValue]
  all_goals (core_call_pure shapeSource as callee; core_pure)

structure View where
  count : Nat
  fits : count < 2 ^ 31
  events : Nat
  ends : Nat
  annotations : Value := .unit
  annotated : Bool := false
def View.value (view : View) : Value := source_value Extracted.«ir::body_tree».Types.«Tree».mk
  [.rawSlice eventType view.events view.count, view.annotations, .boolean view.annotated,
    .rawSlice (.scalar (.signed .i32)) view.ends view.count, .signed .i32 view.count]
def View.endRead (view : View) (heap : Heap) (index finish : Nat) : Prop :=
  readRawSliceIndex extractedProgram { heap := heap } (.scalar (.signed .i32)) view.ends view.count index =
    .ok (.signed .i32 finish)
/-- Physical adjacent child intervals, not a supplied successful walker. -/
structure Node (view : View) (heap : Heap) (index finish : Nat) (tag : Tag) where
  payload : Value
  bounds : index < finish ∧ finish ≤ view.count
  read : readRawSliceIndex extractedProgram { heap := heap } eventType view.events view.count index =
    .ok (tag.event payload)
  endpoint : view.endRead heap index finish
  child : Nat → Nat
  childBounds : ∀ ordinal, ordinal < tag.arity → index < child ordinal ∧ child ordinal < finish
  first : 0 < tag.arity → child 0 = index + 1
  next : ∀ ordinal, ordinal + 1 < tag.arity → view.endRead heap (child ordinal) (child (ordinal + 1))
  last : 0 < tag.arity → view.endRead heap (child (tag.arity - 1)) finish
  leaf : tag.arity = 0 → finish = index + 1
private theorem Node.inside (node : Node view heap index finish tag) : index < view.count := by
  have bounds := node.bounds; omega
/-- Each statement child has the required tag and a finite strict subtree;
    expression spans and declaration payloads are opaque to this pass. -/
inductive Native (view : View) (heap : Heap) : Stmt → Nat → Nat → Prop where
  | skip (node : Node view heap index finish .skip) : Native view heap .skip index finish
  | expression (node : Node view heap index finish .expression) : Native view heap (.expression value) index finish
  | sequence (node : Node view heap index finish .sequence)
      (left : Native view heap first (node.child 0) (node.child 1))
      (right : Native view heap second (node.child 1) finish) : Native view heap (.sequence first second) index finish
  | letLocal (node : Node view heap index finish .letValue)
      (body : Native view heap rest (node.child 1) finish) : Native view heap (.letLocal localId type initial rest) index finish
  | letNone (node : Node view heap index finish .letNone)
      (body : Native view heap rest (node.child 0) finish) : Native view heap (.letUninitialized localId type rest) index finish
  | branch (node : Node view heap index finish .branch)
      (yes : Native view heap first (node.child 1) (node.child 2))
      (no : Native view heap second (node.child 2) finish) : Native view heap (.ifThenElse condition first second) index finish
  | loop (node : Node view heap index finish .loop)
      (body : Native view heap rest (node.child 1) finish) : Native view heap (.whileLoop condition rest) index finish
  | returnVoid (node : Node view heap index finish .returnVoid) : Native view heap (.returnValue none) index finish
  | returnValue (node : Node view heap index finish .returnValue) : Native view heap (.returnValue (some value)) index finish

def kindCall (view : View) (index : Int) : Expr := .call kindSource.id [.value view.value, .value (.signed .i32 index)]
def childCall (view : View) (index ordinal : Int) : Expr :=
  .call childSource.id ([view.value, .signed .i32 index, .signed .i32 ordinal].map Expr.value)
def returnCall (view : View) (index : Int) : Expr := .call returnSource.id [.value view.value, .value (.signed .i32 index)]

@[core_pure_rule] theorem actualKind (node : Node view heap index finish tag) (sameHeap : before.heap = heap) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (kindCall view index) statementKind after ∧ PureFrame before after := by
  have inside := node.inside
  core_call_pure kindSource as callee
  core_facts [node]
  core_pure

@[core_pure_rule] theorem kindRejects (view : View) (index : Int) (bad : index < 0 ∨ (view.count : Int) ≤ index)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (kindCall view index) invalidKind after ∧ PureFrame before after := by
  core_call_pure kindSource as callee
  core_pure

theorem childRejectsParent (view : View) (index ordinal : Int) (bad : index < 0 ∨ (view.count : Int) ≤ index)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (childCall view index ordinal) (.signed .i32 (-1)) after ∧ PureFrame before after := by
  core_call_pure childSource as callee
  core_pure

private def cursorId := childSource.bindingId 3
private def counterId := childSource.bindingId 4
private def walk : Stmt := match childSource.body.getD .skip with
  | .sequence _ (.letLocal _ _ _ (.letLocal _ _ _ (.sequence _ (.letLocal _ _ _ body)))) => body
  | _ => .skip
private def loop : Expr × Stmt := match walk with
  | .letLocal _ _ _ (.letLocal _ _ _ (.sequence (.whileLoop guard body) _)) => (guard, body)
  | _ => (.value (.boolean false), .skip)
private def tail : Stmt := match walk with
  | .letLocal _ _ _ (.letLocal _ _ _ (.sequence _ rest)) => rest
  | _ => .skip
private structure Walking (base current : State) (node : Node view heap index finish tag) (ordinal : Nat) : Prop
    extends LocalPair base current cursorId counterId (.signed .i32 (node.child ordinal)) (.signed .i32 ordinal) where
  heap : current.heap = base.heap
  world : current.world = base.world
  views : current.i32ArrayViews = base.i32ArrayViews

private theorem walkLoop (node : Node view heap index finish tag) (sameHeap : base.heap = heap) (ordinal : Nat) (valid : ordinal < tag.arity)
    (formed : base.CellsWellFormed)
    (treeFound : base.local? (childSource.argumentId 0) = some view.value)
    (ordinalFound : base.local? (childSource.argumentId 2) = some (.signed .i32 ordinal))
    (endsFound : base.local? (childSource.bindingId 2) = some (.rawSlice (.scalar (.signed .i32)) view.ends view.count))
    (remaining : Nat) (frame : Walking base before node current) (left : current + remaining = ordinal) :
    ∃ after, RunsStmt extractedProgram before (.whileLoop loop.1 loop.2) .next after ∧ Walking base after node ordinal := by
  induction remaining generalizing before current with
  | zero =>
      have same : current = ordinal := by omega
      subst current
      core_facts [frame]
      have condition : RunsExpr extractedProgram before loop.1 (.boolean false) before := by core_run
      exact ⟨before, .whileFalse condition, frame⟩
  | succ remaining ih =>
      have inside := node.childBounds current (by omega)
      have countBound := node.bounds.2
      have nextRead : readRawSliceIndex extractedProgram before (.scalar (.signed .i32)) view.ends view.count
          (node.child current) = .ok (.signed .i32 (node.child (current + 1))) := by
        simpa only [View.endRead, readRawSliceIndex, frame.heap, sameHeap] using node.next current (by omega)
      core_facts [frame]
      have condition : RunsExpr extractedProgram before loop.1 (.boolean true) before := by core_run
      have right : RunsExpr extractedProgram before
          (.index (.local (childSource.bindingId 2)) (.local cursorId)) (.signed .i32 (node.child (current + 1))) before := by core_run
      obtain ⟨middle, assignRun, assigned, effect⟩ := RunsExpr.assignI32 (op := .set)
        (replacement := (node.child (current + 1) : Int)) frame.toLocalPair.firstCell frame.first right rfl
      have firstPair := frame.toLocalPair.assignFirst formed assigned
      have small : current + 1 < 2 ^ 31 := by cases tag <;> simp [Tag.arity] at valid <;> omega
      obtain ⟨after, increment, nextPair, heap, world, views⟩ := firstPair.incrementSecond (program := extractedProgram) formed small
      have step : RunsStmt extractedProgram before loop.2 .next after := by core_stmt
      have nextFrame : Walking base after node (current + 1) :=
        ⟨nextPair, heap.trans (effect.heap.trans frame.heap), world.trans (effect.world.trans frame.world),
          views.trans (effect.views.trans frame.views)⟩
      obtain ⟨final, rest, finalFrame⟩ := ih nextFrame (by omega)
      exact ⟨final, .whileStep condition step (Or.inl rfl) rest, finalFrame⟩

private theorem walkScope (node : Node view heap index finish tag) (sameHeap : base.heap = heap) (ordinal : Nat) (valid : ordinal < tag.arity)
    (formed : base.CellsWellFormed)
    (treeFound : base.local? (childSource.argumentId 0) = some view.value)
    (indexFound : base.local? (childSource.argumentId 1) = some (.signed .i32 index))
    (ordinalFound : base.local? (childSource.argumentId 2) = some (.signed .i32 ordinal))
    (endsFound : base.local? (childSource.bindingId 2) = some (.rawSlice (.scalar (.signed .i32)) view.ends view.count)) :
    ∃ after, RunsStmt extractedProgram base walk (.returned (some (.signed .i32 (node.child ordinal)))) after ∧ PureFrame base after := by
  have first := node.first (by omega)
  have initial : RunsExpr extractedProgram base
      (.binary .add (.local (childSource.argumentId 1)) (.value (.signed .i32 1))) (.signed .i32 (node.child 0)) base := by
    have add := eval_i32_addNat extractedProgram.target index 1 (by
      have fits := view.fits; have bound := node.childBounds 0 (by omega); have endBound := node.bounds.2; omega)
    rw [first]; core_run
  let ready := (base.bindLocal cursorId (.signed .i32 (node.child 0))).bindLocal counterId (.signed .i32 0)
  have pair : Walking base ready node 0 := ⟨LocalPair.start formed (by decide), rfl, rfl, rfl⟩
  obtain ⟨completed, loopRun, frame⟩ := walkLoop node sameHeap ordinal valid formed treeFound ordinalFound endsFound ordinal pair (by omega)
  have childBounds := node.childBounds ordinal valid
  have countBound := node.bounds.2
  core_facts [frame]
  have finishRun : RunsStmt extractedProgram completed tail (.returned (some (.signed .i32 (node.child ordinal)))) completed := by core_stmt
  have bodyRun : RunsStmt extractedProgram ready (.sequence (.whileLoop loop.1 loop.2) tail)
      (.returned (some (.signed .i32 (node.child ordinal)))) completed := by core_stmt
  refine ⟨restoreLocals base (restoreLocals (base.bindLocal cursorId (.signed .i32 (node.child 0))) completed), ?_,
    ⟨formed, frame.cells.restoreLocals.restoreLocals, rfl, frame.heap, frame.world, frame.views⟩⟩
  exact RunsStmt.letLocal initial (RunsStmt.letLocal (by core_run) bodyRun)

theorem actualChild (node : Node view heap index finish tag) (sameHeap : before.heap = heap) (ordinal : Int) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (childCall view index ordinal)
      (.signed .i32 (if 0 ≤ ordinal ∧ ordinal < tag.arity then node.child ordinal.toNat else -1)) after ∧ PureFrame before after := by
  have inside := node.inside
  by_cases valid : 0 ≤ ordinal ∧ ordinal < tag.arity
  · have natural : (ordinal.toNat : Int) = ordinal := by omega
    simp only [if_pos valid]
    core_call_pure childSource as callee
    core_facts [node]
    apply RunsStmt.guardPureFalse
    · core_run
    apply RunsStmt.letPure
    · core_run
    · core_formed
    apply RunsStmt.letFramedPure
    · core_pure_expr
    intro middle frame
    apply RunsStmt.guardPureFalse
    · core_run
    apply RunsStmt.letPure
    · core_run
    · core_formed
    apply walkScope node (by core_contract) ordinal.toNat (by omega)
    all_goals first | core_formed | core_local | (rw [natural]; core_local)
  · simp only [if_neg valid]
    core_call_pure childSource as callee
    core_facts [node]
    core_pure

def result : Stmt → Bool
  | .returnValue _ => true
  | .sequence first second => result first || result second
  | .letLocal _ _ _ body | .letUninitialized _ _ body => result body
  | .ifThenElse _ yes no => result yes && result no
  | _ => false
theorem resultSpec (stmt : Stmt) : result stmt = true ↔ DefinitelyReturns stmt := by
  induction stmt <;> simp_all [result] <;> first | (constructor <;> intro h) | intro h
  all_goals solve
    | exact .returnValue
    | cases h
    | exact .letLocal h
    | exact .letUninitialized h
    | exact .ifThenElse h.1 h.2
    | (rcases h with h | h; exact .sequenceLeft h; exact .sequenceRight h)
    | (cases h <;> simp_all)

@[core_pure_rule] theorem childAt (node : Node view heap index finish tag) (ordinal : Nat)
    (valid : ordinal < tag.arity) (sameHeap : before.heap = heap) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (childCall view index ordinal) (.signed .i32 (node.child ordinal)) after ∧ PureFrame before after := by
  simpa only [if_pos (show 0 ≤ (ordinal : Int) ∧ (ordinal : Int) < tag.arity by omega), Int.toNat_natCast]
    using actualChild node sameHeap ordinal formed

theorem childProgress (node : Node view heap index finish tag) (ordinal : Nat)
    (valid : ordinal < tag.arity) :
    index < node.child ordinal ∧ node.child ordinal < finish ∧
      view.count - node.child ordinal < view.count - index := by
  have childBound := node.childBounds ordinal valid
  have endBound := node.bounds.2
  omega

theorem resultFalseSpec (stmt : Stmt) : result stmt = false ↔ ¬ DefinitelyReturns stmt := by
  have spec := resultSpec stmt
  cases answer : result stmt <;> simp_all

theorem actualReturns (native : Native view heap stmt index finish) (sameHeap : before.heap = heap) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (returnCall view index) (.boolean (result stmt)) after ∧ PureFrame before after := by
  induction native generalizing before
  case' skip index finish top => skip
  case' expression index finish value top => skip
  case' sequence index finish first second top left right leftIH rightIH => skip
  case' letLocal index finish rest localId type initial top body bodyIH => skip
  case' letNone index finish rest localId type top body bodyIH => skip
  case' branch index finish first second condition top yes no yesIH noIH => skip
  case' loop index finish rest condition top body bodyIH => skip
  case' returnVoid index finish top => skip
  case' returnValue index finish value top => skip
  all_goals
    simp only [result]
    core_call_pure returnSource as callee
    have kind := actualKind top (show callee.heap = heap from sameHeap) (by core_formed)
    have read := top.read
    apply RunsStmt.guardFramedFalse
    · core_pure_guard
    intro current frame
    core_pure

theorem returnsRejects (view : View) (index : Int) (bad : index < 0 ∨ (view.count : Int) ≤ index)
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before (returnCall view index) (.boolean false) after ∧ PureFrame before after := by
  core_call_pure returnSource as callee
  core_pure

end IRReturnsProof
