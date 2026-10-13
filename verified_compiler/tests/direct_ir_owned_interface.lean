import verified_compiler.tests.direct_ir_owned_interface_scan
import verified_compiler.tests.direct_ir_owned_interface_prelude
import verified_compiler.tests.direct_ir_owned_interface_scan_effects
import verified_compiler.tests.direct_ir_owned_queries_rows
import verified_compiler.tests.direct_ir_owned_queries_fields

namespace IRBodyOwnedProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IRBodyOwnedInputs
open IRValueCatalogValid IRBodyProductionProof IRBodyProductionInputs
open IRCatalogConstructionProof IRCatalogAppendProof

/-- Complete target: finite actual Core1180 runs, including guarded failures. -/
def OwnedLoweringCorrect : Prop :=
  ∀ (raw : RawInputs) (workspace : RawWorkspace) (origin : State)
    (domain : OriginalDomain raw workspace origin) (formed : origin.CellsWellFormed),
    ∃ result after, RunsExpr extractedProgram origin (ownedCall raw.value workspace.value)
        (.signed .i32 result) after ∧ FreshCellFrame origin after ∧ after.locals = origin.locals ∧
      after.i32ArrayViews = origin.i32ArrayViews ∧ OwnedOutcome domain result after

variable {origin before after : State} {raw : RawInputs} {workspace : RawWorkspace}
  {normal : NormalTable raw.allocationTable origin.heap} {validation : OriginalValidation raw origin}
  {scan : OriginalScan raw workspace normal validation}

def loopValues (raw : RawInputs) (workspace : RawWorkspace) (rows lowered cursor : Nat) : LocalValues :=
  (((entryValues raw workspace).set (ownedSource.bindingId 14) (.signed .i32 rows)).set
    (ownedSource.bindingId 15) (.signed .i32 lowered)).set (ownedSource.bindingId 16) (.signed .i32 cursor)

private theorem negativeOne : evalUnaryValue extractedProgram.target .negate (.signed .i32 1) =
    .ok (.signed .i32 (-1)) := by
  simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]

private theorem negativeTwo : evalUnaryValue extractedProgram.target .negate (.signed .i32 2) =
    .ok (.signed .i32 (-2)) := by
  simp [evalUnaryValue, wrapSigned, signedModulus, signedSignBit, SignedIntTy.bits]

private def invalidReturn : Stmt := .returnValue (some
  (.call Extracted.«lowering::body_context».Functions.«invalid».core.id []))

private theorem actualInvalidReturn (formed : before.CellsWellFormed) :
    ∃ after, RunsStmt extractedProgram before invalidReturn
      (.returned (some (.signed .i32 (-1)))) after ∧ PureFrame before after := by
  unfold invalidReturn
  core_pure

def entryGuard : Expr := match entrySuffix with
  | .sequence (.ifThenElse condition _ _) _ => condition
  | _ => .value (.boolean false)

def entryNumericPrefix : Expr :=
  .binary .logicalOr
    (.binary .logicalOr
      (.binary .logicalOr
        (.binary .lessEqual (.local (ownedSource.bindingId 8)) (.unary .negate (.value (.signed .i32 2))))
        (.binary .lessEqual (.local (ownedSource.bindingId 9)) (.unary .negate (.value (.signed .i32 1)))))
      (.binary .lessEqual (.local (ownedSource.bindingId 10)) (.unary .negate (.value (.signed .i32 1)))))
    (.binary .lessEqual (.local (ownedSource.bindingId 11)) (.value (.signed .i32 0)))

def entryNumericBool (input : RawInputs) : Bool :=
  decide (input.owner.toInt ≤ -2) || decide (input.sourceWords.toInt ≤ -1) ||
    decide (input.tokenCount.toInt ≤ -1) || decide (input.nodeCount.toInt ≤ 0)

theorem entryGuardShape : entryGuard =
    .binary .logicalOr
      (.binary .logicalOr
        (.binary .logicalOr
          (.binary .logicalOr
            (.binary .logicalOr
              (.binary .logicalOr entryNumericPrefix
                (.unary .logicalNot
                  (.call Extracted.«lowering::allocation».Functions.«table_has_exact_rows».core.id
                    [.local (ownedSource.bindingId 2)])))
              (.binary .lessEqual (.field (.field (.local (ownedSource.argumentId 0)) 5) 1)
                (.value (.signed .i32 0))))
            (.binary .lessEqual (.field (.local (ownedSource.bindingId 4)) 1)
              (.unary .negate (.value (.signed .i32 1)))))
          (.binary .lessEqual (.local (ownedSource.bindingId 12)) (.value (.signed .i32 0))))
        (.binary .lessEqual (.field (.local (ownedSource.bindingId 6)) 2) (.value (.signed .i32 0))))
      (.binary .lessEqual (.local (ownedSource.bindingId 13)) (.value (.signed .i32 0))) := by rfl

private theorem numericGuard (env : LocalEnv origin before (entryValues raw workspace)) :
    RunsExpr extractedProgram before entryNumericPrefix (.boolean (entryNumericBool raw)) before := by
  have one := negativeOne
  have two := negativeTwo
  unfold entryNumericPrefix entryNumericBool
  core_run

def entryHeaderBool (input : RawInputs) (workspace : RawWorkspace) (header : Header) : Bool :=
  !decide (header.rows.toInt = input.allocationTable.count.toInt) ||
    decide (input.signatureCount.toInt ≤ 0) || decide (input.valueCount.toInt ≤ -1) ||
    decide (workspace.expressionCapacity.toInt ≤ 0) || decide (workspace.typeCapacity.toInt ≤ 0) ||
    decide (workspace.typeOutputCount.toInt ≤ 0)

private theorem actualEntryHeaderGuard (env : LocalEnv origin before (entryValues raw workspace))
    (geometry : HeaderGeometry raw.allocationTable before.heap)
    (native : NativeHeader raw.allocationTable before.heap) (earlyGood : ¬raw.beforeHeaderReject) :
    ∃ after, RunsExpr extractedProgram before entryGuard
        (.boolean (entryHeaderBool raw workspace native.header)) after ∧
      MemoryEffect (fun heap current => current = heap.borrowBlock geometry.block.base) before after := by
  have numericFalse : entryNumericBool raw = false := by
    simp only [entryNumericBool, Bool.or_eq_false_iff, decide_eq_false_iff_not]
    exact ⟨⟨⟨fun bad => earlyGood (Or.inl bad), fun bad => earlyGood (Or.inr (Or.inl bad))⟩,
      fun bad => earlyGood (Or.inr (Or.inr (Or.inl bad)))⟩,
      fun bad => earlyGood (Or.inr (Or.inr (Or.inr (Or.inl bad))))⟩
  have nonnegative : 0 ≤ raw.allocationTable.count.toInt := by
    have good : ¬raw.allocationTable.count.toInt ≤ -1 :=
      fun bad => earlyGood (Or.inr (Or.inr (Or.inr (Or.inr bad))))
    omega
  obtain ⟨read, queried, effect⟩ := actualExactRows geometry native nonnegative env.formed
  have called := RunsExpr.callArguments
    (.cons (.ofStable (.local (env.read (id := ownedSource.bindingId 2) (by rfl))) rfl) .nil) queried
  have numeric := numericGuard env
  rw [numericFalse] at numeric
  have negated : RunsExpr extractedProgram before
      (.unary .logicalNot (.call Extracted.«lowering::allocation».Functions.«table_has_exact_rows».core.id
        [.local (ownedSource.bindingId 2)]))
      (.boolean (!decide (native.header.rows.toInt = raw.allocationTable.count.toInt))) read :=
    RunsExpr.unary called rfl
  have start := RunsExpr.logicalOrFalse numeric negated
  have env := env.afterExpr called effect.1
  have one := negativeOne
  core_facts [raw, workspace]
  refine ⟨read, ?_, effect⟩
  rw [entryGuardShape]
  unfold entryHeaderBool
  core_env_run

private theorem actualEarlyGuard (env : LocalEnv origin before (entryValues raw workspace))
    (rejected : raw.beforeHeaderReject) :
    ∃ after, RunsExpr extractedProgram before entryGuard (.boolean true) after ∧ PureFrame before after := by
  have numeric := numericGuard env
  rw [entryGuardShape]
  iterate 5 apply RunsExpr.logicalOrTruePure
  cases truth : entryNumericBool raw with
  | true =>
      rw [truth] at numeric
      exact RunsExpr.logicalOrTruePure ⟨before, numeric, PureFrame.refl env.formed⟩
  | false =>
      rw [truth] at numeric
      have good := truth
      simp only [entryNumericBool, Bool.or_eq_false_iff, decide_eq_false_iff_not] at good
      have negative : raw.allocationTable.count.toInt ≤ -1 := by
        unfold RawInputs.beforeHeaderReject at rejected
        rcases rejected with owner | words | tokens | nodes | table
        · exact False.elim (good.1.1.1 owner)
        · exact False.elim (good.1.1.2 words)
        · exact False.elim (good.1.2 tokens)
        · exact False.elim (good.2 nodes)
        · exact table
      obtain ⟨after, run, pure⟩ := actualExactRowsNegative raw.allocationTable negative env.formed
      have called := RunsExpr.callArguments
        (.cons (.ofStable (.local (env.read (id := ownedSource.bindingId 2) (by rfl))) rfl) .nil) run
      exact RunsExpr.logicalOrFalsePure numeric ⟨after, RunsExpr.unary called rfl, pure⟩

private theorem entryHeaderFalse (descriptorGood : ¬raw.afterHeaderReject workspace)
    (exactRows : header.rows.toInt = raw.allocationTable.count.toInt) :
    entryHeaderBool raw workspace header = false := by
  simp only [entryHeaderBool, exactRows, decide_true, Bool.not_true, Bool.false_or,
    Bool.or_eq_false_iff, decide_eq_false_iff_not]
  exact ⟨⟨⟨⟨fun bad => descriptorGood (Or.inl bad),
    fun bad => descriptorGood (Or.inr (Or.inl bad))⟩,
    fun bad => descriptorGood (Or.inr (Or.inr (Or.inl bad)))⟩,
    fun bad => descriptorGood (Or.inr (Or.inr (Or.inr (Or.inl bad))))⟩,
    fun bad => descriptorGood (Or.inr (Or.inr (Or.inr (Or.inr bad))))⟩

def headerRowsSuffix : Stmt := match ownedSource.bindingStatement 14 with
  | .letLocal _ _ _ body => body | _ => .skip

theorem reachedHeaderShape : entrySuffix =
    .sequence (.ifThenElse entryGuard invalidReturn .skip) (ownedSource.bindingStatement 14) := by rfl

theorem headerRowsShape : headerRowsSuffix =
    .sequence (.ifThenElse
      (.binary .lessEqual (.local (ownedSource.bindingId 14)) (.value (.signed .i32 0))) invalidReturn .skip)
    (.sequence (.ifThenElse (.unary .logicalNot
      (.call Extracted.«lowering::value_catalog».Functions.«valid».core.id
        [.local (ownedSource.bindingId 4), .local (ownedSource.bindingId 10),
          .field (.local (ownedSource.argumentId 0)) 4])) invalidReturn .skip)
      (ownedSource.bindingStatement 15)) := by rfl

private theorem actualBorrowedHeader (geometry : HeaderGeometry table heap)
    (native : NativeHeader table heap)
    (same : before.heap = heap.borrowBlock geometry.block.base) (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::allocation».Functions.«table_header».core.id [.value table.value])
      native.header.value after ∧ PureFrame before after := by
  let currentGeometry : HeaderGeometry table before.heap := {
    geometry with
    block := { geometry.block with owned := false }
    found := by rw [same]; exact Heap.containingBlock?_borrowSelected geometry.found
    unique := by rw [same]; exact geometry.unique.borrowBlock }
  let currentHeader : NativeHeader table before.heap := {
    native with snapshot := native.snapshot.afterHeapReads (by
      intro pointer offset byte loaded
      rw [same, Heap.loadByte_borrowBlock]; exact loaded) }
  obtain ⟨after, run, effect⟩ := actualHeader currentGeometry currentHeader formed
  have heapEq : after.heap = before.heap := by
    apply effect.2.2.2.trans
    change before.heap.borrowBlock geometry.block.base = before.heap
    rw [same]; exact Heap.borrowBlock_idempotent heap geometry.block.base
  exact ⟨after, run, formed, effect.1, run.choose_spec.2, heapEq, effect.2.1, effect.2.2.1⟩

def allocationType : Ty := match ownedSource.bindingStatement 17 with
  | .letLocal _ type _ _ => type | _ => .scalar (.signed .i32)
def selectionExpr : Expr := match ownedSource.bindingStatement 17 with
  | .letLocal _ _ _ (.sequence (.ifThenElse condition _ _) _) => condition
  | _ => .value (.boolean false)
def selectedBranch : Stmt := match ownedSource.bindingStatement 17 with
  | .letLocal _ _ _ (.sequence (.ifThenElse _ branch _) _) => branch | _ => .skip
def selectedResultSuffix : Stmt := match ownedSource.bindingStatement 19 with
  | .letLocal _ _ _ body => body | _ => .skip

theorem actualIterationShape : (ownedSource.whileLoop 0).2 =
    .letLocal (ownedSource.bindingId 17) allocationType (ownedSource.bindingInitializer 17)
      (.sequence (.ifThenElse selectionExpr selectedBranch .skip)
        (.sequence (.expression (ownedSource.effectExpression 1)) .skip)) := by rfl

private theorem actualSelection (row : AllocationRow) (owner : Int32)
    (allocation : before.local? (ownedSource.bindingId 17) = some row.value)
    (ownerFound : before.local? (ownedSource.bindingId 8) = some (.signed .i32 owner.toInt))
    (formed : before.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram before selectionExpr
      (.boolean (selectedRowBool owner row)) after ∧ PureFrame before after := by
  have one := negativeOne
  have kind {state : State} (cells : state.CellsWellFormed) := actualRowHasKind (before := state) row .Function cells
  have unit {state : State} (cells : state.CellsWellFormed) := actualRowUnit (before := state) row cells
  unfold selectionExpr selectedRowBool
  core_pure_expr

private theorem actualAppend {cursor : Nat} {entries : List InsertedBody} {values : LocalValues}
    (env : LocalEnv origin before values) (facts : LoopFacts scan cursor entries before.heap)
    (views : before.i32ArrayViews = origin.i32ArrayViews) (inside : cursor < normal.count)
    (chosen : selectedRowBool raw.owner (normal.rowValue cursor) = true)
    (bounds : 0 ≤ (normal.rowValue cursor).coreId.toInt ∧
      (normal.rowValue cursor).coreId.toInt < scan.signatures.index.count.toInt)
    (present : scan.signatures.present cursor inside chosen bounds = true)
    (inputFound : values (ownedSource.argumentId 0) = some raw.value)
    (workspaceFound : values (ownedSource.argumentId 1) = some workspace.value)
    (rowFound : values (ownedSource.bindingId 17) = some (normal.rowValue cursor).value)
    (idFound : values (ownedSource.bindingId 18) = some (.signed .i32 (normal.rowValue cursor).coreId.toInt))
    (nodesFound : values (ownedSource.bindingId 11) = some (.signed .i32 raw.nodeCount.toInt)) :
    ∃ result after, RunsExpr extractedProgram before (ownedSource.bindingInitializer 19)
      (.signed .i32 result) after ∧ FreshCellFrame before after ∧
      ProducerStep scan cursor entries result after ∧ after.i32ArrayViews = origin.i32ArrayViews := by
  have formed := env.formed
  have declaration {state : State} (cells : state.CellsWellFormed) :=
    actualRowDeclaration (before := state) (normal.rowValue cursor) cells
  obtain ⟨ready, arguments, pure⟩ : ∃ ready, RunsExprs extractedProgram before
      [.local (ownedSource.argumentId 0), .local (ownedSource.argumentId 1),
        .call Extracted.«lowering::allocation».Functions.«row_declaration».core.id [.local (ownedSource.bindingId 17)],
        .local (ownedSource.bindingId 18), .local (ownedSource.bindingId 11)]
      [raw.value, workspace.value, .signed .i32 (normal.rowValue cursor).source.declaration.toInt,
        .signed .i32 (normal.rowValue cursor).coreId.toInt, .signed .i32 raw.nodeCount.toInt]
      ready ∧ PureFrame before ready := by core_pure_arguments
  have current : LoopFacts scan cursor entries ready.heap := by rw [pure.heap]; exact facts
  let producer := (scan.producers cursor inside chosen bounds present).at (after := ready)
    current.protected (fun _ covered => scan.regionProtected covered)
  have fits := current.producerFits inside producer
  obtain ⟨result, after, run, observed⟩ := actualOriginalProducer producer
    (current.catalogState.invariant pure.afterFormed (pure.views.trans (views.trans scan.invariant.noViews)))
    scan.protectedApart scan.workspaceCatalogApart scan.catalogApart fits.1 fits.2
  exact ⟨result, after, RunsExpr.callArguments arguments run, pure.cells.trans observed.1,
    current.produce inside chosen bounds present observed, observed.2.2.1.trans (pure.views.trans views)⟩

def rowValues (raw : RawInputs) (workspace : RawWorkspace) (rows lowered cursor : Nat)
    (row : AllocationRow) : LocalValues :=
  (loopValues raw workspace rows lowered cursor).set (ownedSource.bindingId 17) row.value

private def BranchPost (scan : OriginalScan raw workspace normal validation)
    (cursor : Nat) (entries appended : List InsertedBody)
    (completion : Completion) (after : State) : Prop :=
  after.i32ArrayViews = origin.i32ArrayViews ∧
    ((completion = .returned (some (.signed .i32 (-1))) ∧ SafeHeap scan after.heap ∧ ¬FullFunding scan) ∨
    (completion = .next ∧ ∃ entry : InsertedBody, appended = entries ++ [entry] ∧
      entry.sourceRow = cursor ∧ LoopFacts scan (cursor + 1) appended after.heap))

private theorem actualSelected {cursor : Nat} {entries : List InsertedBody}
    (env : LocalEnv origin before (rowValues raw workspace normal.count entries.length cursor (normal.rowValue cursor)))
    (facts : LoopFacts scan cursor entries before.heap)
    (views : before.i32ArrayViews = origin.i32ArrayViews) (inside : cursor < normal.count)
    (chosen : selectedRowBool raw.owner (normal.rowValue cursor) = true) :
    EnvStmt extractedProgram origin before selectedBranch
      (fun appended : List InsertedBody =>
        rowValues raw workspace normal.count appended.length cursor (normal.rowValue cursor))
      (BranchPost scan cursor entries) := by
  have formed := env.formed
  have coreId {state : State} (cells : state.CellsWellFormed) := actualRowCoreId (before := state) (normal.rowValue cursor) cells
  have one := negativeOne
  change EnvStmt extractedProgram origin before (ownedSource.bindingStatement 18) _ _
  refine EnvStmt.letFramed env (by rfl)
    (spec := fun value ready => value = .signed .i32 (normal.rowValue cursor).coreId.toInt ∧ PureFrame before ready)
    (insideValues := fun value appended =>
      (rowValues raw workspace normal.count appended.length cursor (normal.rowValue cursor)).set
        (ownedSource.bindingId 18) value) ?_ ?_ ?_
  · obtain ⟨ready, run, pure⟩ : ∃ ready, RunsExpr extractedProgram before (ownedSource.bindingInitializer 18)
        (.signed .i32 (normal.rowValue cursor).coreId.toInt) ready ∧ PureFrame before ready := by core_pure_expr
    exact ⟨_, ready, run, pure.cells, rfl, pure⟩
  · intro value ready bound observed
    obtain ⟨valueEq, pure⟩ := observed
    subst value
    have current : LoopFacts scan cursor entries ready.heap := by rw [pure.heap]; exact facts
    obtain ⟨queried, run, unchanged⟩ := scan.actualSignature
      (current := ready.bindLocal (ownedSource.bindingId 18) (.signed .i32 (normal.rowValue cursor).coreId.toInt))
      cursor inside chosen current.protected bound.formed
    have call : RunsExpr extractedProgram (ready.bindLocal (ownedSource.bindingId 18) (.signed .i32 (normal.rowValue cursor).coreId.toInt))
        (.call Extracted.«lowering::body_lookup».Functions.«has_function_signature».core.id
          [.field (.local (ownedSource.argumentId 0)) 5, .local (ownedSource.bindingId 18)])
        (.boolean (scan.signatureBool cursor inside chosen)) queried := by
      core_facts [raw]
      exact RunsExpr.callArguments (by core_arguments) run
    have queriedEnv := bound.afterExpr call unchanged.cells
    have queriedFacts : LoopFacts scan cursor entries queried.heap := by rw [unchanged.heap]; exact current
    have queriedViews := unchanged.views.trans (pure.views.trans views)
    cases truth : scan.signatureBool cursor inside chosen with
    | false =>
        have condition := RunsExpr.unary (operator := UnaryOp.logicalNot) call rfl
        rw [truth] at condition
        obtain ⟨after, returned, tail⟩ := actualInvalidReturn queriedEnv.formed
        apply EnvStmt.ofRun (RunsStmt.sequenceCompleted (RunsStmt.ifThenElseTrue condition returned) (by simp) _)
          (result := entries) (queriedEnv.afterStmt returned tail.cells)
        refine ⟨tail.views.trans queriedViews, Or.inl ⟨rfl, ?_, ?_⟩⟩
        · simpa only [restoreLocals_heap, tail.heap] using queriedFacts.safe
        · intro funded
          obtain ⟨bounds, present⟩ := funded.signatures cursor inside chosen
          simp only [OriginalScan.signatureBool, dif_pos bounds, present] at truth
          contradiction
    | true =>
        have condition := RunsExpr.unary (operator := UnaryOp.logicalNot) call rfl
        rw [truth] at condition
        apply EnvStmt.sequenceNext (RunsStmt.ifThenElseFalse condition (RunsStmt.skip _ _))
        have bounds : 0 ≤ (normal.rowValue cursor).coreId.toInt ∧
            (normal.rowValue cursor).coreId.toInt < scan.signatures.index.count.toInt := by
          by_cases present : 0 ≤ (normal.rowValue cursor).coreId.toInt ∧
              (normal.rowValue cursor).coreId.toInt < scan.signatures.index.count.toInt
          · exact present
          · simp only [OriginalScan.signatureBool, dif_neg present] at truth
            contradiction
        have present : scan.signatures.present cursor inside chosen bounds = true := by
          simpa only [OriginalScan.signatureBool, dif_pos bounds] using truth
        refine EnvStmt.letFramed queriedEnv (by rfl)
          (insideValues := fun value appended =>
            ((rowValues raw workspace normal.count appended.length cursor (normal.rowValue cursor)).set
              (ownedSource.bindingId 18) (.signed .i32 (normal.rowValue cursor).coreId.toInt)).set
                (ownedSource.bindingId 19) value)
          (spec := fun value after => ∃ result : Int, value = .signed .i32 result ∧
            ProducerStep scan cursor entries result after ∧ after.i32ArrayViews = origin.i32ArrayViews) ?_ ?_ ?_
        · obtain ⟨result, produced, actual, cells, transition, views⟩ := actualAppend queriedEnv queriedFacts
            queriedViews inside chosen bounds present (by rfl) (by rfl) (by rfl) (by rfl) (by rfl)
          exact ⟨_, produced, actual, cells, result, rfl, transition, views⟩
        · intro value produced resultEnv observed
          obtain ⟨result, valueEq, transition, views⟩ := observed
          subst value
          rcases transition with ⟨rfl, safe, impossible⟩ | ⟨rfl, entry, row, next⟩
          · have actual : RunsStmt extractedProgram
                (produced.bindLocal (ownedSource.bindingId 19) (.signed .i32 (-1)))
                selectedResultSuffix (.returned (some (.signed .i32 (-1))))
                (produced.bindLocal (ownedSource.bindingId 19) (.signed .i32 (-1))) := by core_stmt
            exact EnvStmt.ofRun actual (result := entries) resultEnv ⟨views, Or.inl ⟨rfl, safe, impossible⟩⟩
          · have fits : entries.length + 1 < 2 ^ 31 := by
              have := facts.ordered.countBound
              have := normal.offsetFits
              omega
            obtain ⟨counted, increment, countedEnv, effect⟩ := resultEnv.increment
              (program := extractedProgram) (id := ownedSource.bindingId 15) (index := entries.length) (by rfl) fits
            have actual : RunsStmt extractedProgram
                (produced.bindLocal (ownedSource.bindingId 19) (.signed .i32 0))
                selectedResultSuffix .next counted := by core_stmt
            apply EnvStmt.ofRun actual (result := entries ++ [entry])
            · refine Eq.mp (congrArg (LocalEnv origin counted) ?_) countedEnv
              try dsimp only [rowValues, loopValues]
              simp only [List.length_append, List.length_singleton]
              core_env_values
            · refine ⟨effect.views.trans views, Or.inr ⟨rfl, entry, rfl, row, ?_⟩⟩
              change LoopFacts scan (cursor + 1) (entries ++ [entry]) counted.heap
              rw [effect.heap]; exact next
        · try dsimp only [rowValues, loopValues]
          core_env_values
  · try dsimp only [rowValues, loopValues]
    core_env_values

private def IterationPost (scan : OriginalScan raw workspace normal validation) (cursor : Nat)
    (next : Nat × List InsertedBody) (completion : Completion) (after : State) : Prop :=
  after.i32ArrayViews = origin.i32ArrayViews ∧
    ((completion = .returned (some (.signed .i32 (-1))) ∧ SafeHeap scan after.heap ∧ ¬FullFunding scan) ∨
    (completion = .next ∧ next.1 = cursor + 1 ∧ LoopFacts scan next.1 next.2 after.heap))

private theorem actualIteration {cursor : Nat} {entries : List InsertedBody}
    (env : LocalEnv origin before (loopValues raw workspace normal.count entries.length cursor))
    (facts : LoopFacts scan cursor entries before.heap)
    (views : before.i32ArrayViews = origin.i32ArrayViews) (inside : cursor < normal.count) :
    EnvStmt extractedProgram origin before (ownedSource.whileLoop 0).2
      (fun next : Nat × List InsertedBody => loopValues raw workspace normal.count next.2.length next.1)
      (IterationPost scan cursor) := by
  let native := tableRep_native normal facts.table facts.catalogState.unique
  have locations := tableRep_locations normal facts.table facts.catalogState.unique
  have rowEq : (native.rows cursor inside).row = normal.rowValue cursor := by
    rw [normal.rowValue_inside inside]; rfl
  obtain ⟨read, run, pure⟩ := actualRow native locations inside env.formed
  rw [rowEq] at run
  have initial : RunsExpr extractedProgram before (ownedSource.bindingInitializer 17)
      (normal.rowValue cursor).value read := RunsExpr.callArguments (by core_arguments) run
  rw [actualIterationShape]
  refine EnvStmt.letFramed env (by rfl)
    (insideValues := fun value next =>
      (loopValues raw workspace normal.count next.2.length next.1).set (ownedSource.bindingId 17) value)
    (spec := fun value ready => value = (normal.rowValue cursor).value ∧ PureFrame before ready) ?_ ?_ ?_
  · exact ⟨_, read, initial, pure.cells, rfl, pure⟩
  · intro value ready bound observed
    obtain ⟨valueEq, headFrame⟩ := observed
    subst value
    obtain ⟨selected, condition, pure⟩ := actualSelection (normal.rowValue cursor) raw.owner
      (bound.read (id := ownedSource.bindingId 17) (by rfl))
      (bound.read (id := ownedSource.bindingId 8) (by rfl)) bound.formed
    have selectedEnv := bound.afterExpr condition pure.cells
    have selectedFacts : LoopFacts scan cursor entries selected.heap := by
      rw [pure.heap]
      change LoopFacts scan cursor entries ready.heap
      rw [headFrame.heap]; exact facts
    have selectedViews := pure.views.trans (headFrame.views.trans views)
    have fits : cursor + 1 < 2 ^ 31 := by have := normal.offsetFits; omega
    have branch : EnvStmt extractedProgram origin selected
        (if selectedRowBool raw.owner (normal.rowValue cursor) then selectedBranch else .skip)
        (fun appended : List InsertedBody =>
          rowValues raw workspace normal.count appended.length cursor (normal.rowValue cursor))
        (fun appended completion after => after.i32ArrayViews = origin.i32ArrayViews ∧
          ((completion = .returned (some (.signed .i32 (-1))) ∧ SafeHeap scan after.heap ∧ ¬FullFunding scan) ∨
          (completion = .next ∧ LoopFacts scan (cursor + 1) appended after.heap))) := by
      cases chosen : selectedRowBool raw.owner (normal.rowValue cursor) with
      | false =>
          exact EnvStmt.ofRun (RunsStmt.skip _ _) (result := entries) selectedEnv
            ⟨selectedViews, Or.inr ⟨rfl, selectedFacts.skip inside chosen⟩⟩
      | true =>
          apply EnvStmt.mono (actualSelected selectedEnv selectedFacts selectedViews inside chosen)
          intro appended completion after finalEnv ⟨views, outcome⟩
          refine ⟨views, ?_⟩
          rcases outcome with failure | ⟨rfl, entry, rfl, row, next⟩
          · exact Or.inl failure
          · exact Or.inr ⟨rfl, next⟩
    apply EnvStmt.sequence (EnvStmt.branch condition branch)
    intro appended completion after afterEnv ⟨views, outcome⟩
    rcases outcome with ⟨rfl, safe, impossible⟩ | ⟨rfl, next⟩
    · exact ⟨(cursor, appended), rfl, views, Or.inl ⟨rfl, safe, impossible⟩⟩
    · obtain ⟨advanced, increment, advancedEnv, effect⟩ := afterEnv.increment
        (program := extractedProgram) (id := ownedSource.bindingId 16) (index := cursor) (by rfl) fits
      apply EnvStmt.ofRun (RunsStmt.sequenceNext (RunsStmt.expression increment) (RunsStmt.skip _ _))
        (result := (cursor + 1, appended))
      · refine Eq.mp (congrArg (LocalEnv origin advanced) ?_) advancedEnv
        try dsimp only [rowValues, loopValues]
        core_env_values
      · refine ⟨effect.views.trans views, Or.inr ⟨rfl, rfl, ?_⟩⟩
        change LoopFacts scan (cursor + 1) appended advanced.heap
        rw [effect.heap]; exact next
  · try dsimp only [loopValues]
    core_env_values

private theorem actualGuard {rows lowered cursor : Nat}
    (env : LocalEnv origin before (loopValues raw workspace rows lowered cursor)) :
    RunsExpr extractedProgram before (ownedSource.whileLoop 0).1
      (.boolean (decide (cursor ≠ rows))) before := by
  change RunsExpr extractedProgram before
    (.binary .notEqual (.local (ownedSource.bindingId 16)) (.local (ownedSource.bindingId 14))) _ before
  apply RunsExpr.ofStable (StableExpr.binary (.local (env.read (id := ownedSource.bindingId 16) (by rfl)))
    (.local (env.read (id := ownedSource.bindingId 14) (by rfl))) (by decide) ?_) rfl
  simp [evalBinaryValue, scalarEqual, Bool.beq_eq_decide_eq, Int.ofNat_inj]

def scanSuffix : Stmt := match ownedSource.bindingStatement 16 with
  | .letLocal _ _ _ body => body | _ => .skip

private structure ScanExit where
  answer : Int
  cursor : Nat
  entries : List InsertedBody

private def ScanDone (scan : OriginalScan raw workspace normal validation)
    (answer : Int) (completion : Completion) (after : State) : Prop :=
  completion = .returned (some (.signed .i32 answer)) ∧
    ScanOutput scan answer after.heap ∧ after.i32ArrayViews = origin.i32ArrayViews

private theorem actualScanSuffix {cursor : Nat} {entries : List InsertedBody}
    (env : LocalEnv origin before (loopValues raw workspace normal.count entries.length cursor))
    (facts : LoopFacts scan cursor entries before.heap)
    (views : before.i32ArrayViews = origin.i32ArrayViews) :
    EnvStmt extractedProgram origin before scanSuffix
      (fun exit : ScanExit => loopValues raw workspace normal.count exit.entries.length exit.cursor)
      (fun exit => ScanDone scan exit.answer) := by
  let invariant := fun (remaining : Nat) (current : State) => ∃ (cursor : Nat) (entries : List InsertedBody),
    cursor + remaining = normal.count ∧
    LocalEnv origin current (loopValues raw workspace normal.count entries.length cursor) ∧
    LoopFacts scan cursor entries current.heap ∧ current.i32ArrayViews = origin.i32ArrayViews
  let post := fun (completion : Completion) (current : State) =>
    (completion = .next ∧ ∃ entries : List InsertedBody, LocalEnv origin current
      (loopValues raw workspace normal.count entries.length normal.count) ∧
      LoopFacts scan normal.count entries current.heap ∧ current.i32ArrayViews = origin.i32ArrayViews) ∨
    (completion = .returned (some (.signed .i32 (-1))) ∧ ∃ (cursor : Nat) (entries : List InsertedBody),
      LocalEnv origin current (loopValues raw workspace normal.count entries.length cursor) ∧
      ScanOutput scan (-1) current.heap ∧ current.i32ArrayViews = origin.i32ArrayViews)
  have finished : ∀ current, invariant 0 current → ∃ after,
      RunsExpr extractedProgram current (ownedSource.whileLoop 0).1 (.boolean false) after ∧ post .next after := by
    intro current ⟨cursor, entries, remaining, env, facts, views⟩
    have equal : cursor = normal.count := by omega
    subst cursor
    have condition := actualGuard env
    simp only [ne_eq, not_true_eq_false, decide_false] at condition
    exact ⟨current, condition, Or.inl ⟨rfl, entries, env, facts, views⟩⟩
  have step : ∀ remaining current, invariant (remaining + 1) current → ∃ middle,
      RunsExpr extractedProgram current (ownedSource.whileLoop 0).1 (.boolean true) middle ∧
        ((∃ after completion, RunsStmt extractedProgram middle (ownedSource.whileLoop 0).2 completion after ∧
          (completion = .next ∨ completion = .continueLoop) ∧ invariant remaining after) ∨
        (∃ after value, RunsStmt extractedProgram middle (ownedSource.whileLoop 0).2 (.returned value) after ∧
          post (.returned value) after)) := by
    intro remaining current ⟨cursor, entries, count, env, facts, views⟩
    have inside : cursor < normal.count := by omega
    have condition : RunsExpr extractedProgram current (ownedSource.whileLoop 0).1 (.boolean true) current := by
      simpa only [ne_eq, Nat.ne_of_lt inside, not_false_eq_true, decide_true] using actualGuard env
    refine ⟨current, condition, ?_⟩
    obtain ⟨⟨nextCursor, appended⟩, completion, after, run, afterEnv, views, result⟩ :=
      actualIteration env facts views inside
    rcases result with ⟨rfl, safe, impossible⟩ | ⟨rfl, next, facts⟩
    · exact Or.inr ⟨after, some (.signed .i32 (-1)), run,
        Or.inr ⟨rfl, nextCursor, appended, afterEnv, ScanOutput.failure safe impossible, views⟩⟩
    · exact Or.inl ⟨after, .next, run, Or.inl rfl, nextCursor, appended, by omega, afterEnv, facts, views⟩
  obtain ⟨completion, after, loop, observation⟩ := RunsStmt.whileCountOrReturn invariant post finished step
    (remaining := normal.count - cursor) ⟨cursor, entries, by have := facts.cursorBound; omega, env, facts, views⟩
  change EnvStmt extractedProgram origin before
    (.sequence (.whileLoop (ownedSource.whileLoop 0).1 (ownedSource.whileLoop 0).2)
      (.returnValue (some (.local (ownedSource.bindingId 15))))) _ _
  rcases observation with ⟨rfl, entries, finalEnv, finalFacts, views⟩ |
      ⟨rfl, cursor, entries, finalEnv, result, views⟩
  · exact EnvStmt.ofRun (RunsStmt.sequenceNext loop (RunsStmt.returnValue
      (.ofStable (.local (finalEnv.read (id := ownedSource.bindingId 15) (by rfl))) rfl)))
      (result := ⟨entries.length, normal.count, entries⟩) finalEnv ⟨rfl, finalFacts.complete, views⟩
  · exact EnvStmt.ofRun (RunsStmt.sequenceCompleted loop (by simp) _)
      (result := ⟨-1, cursor, entries⟩) finalEnv ⟨rfl, result, views⟩

private theorem actualScanInitializers
    (env : LocalEnv origin before ((entryValues raw workspace).set (ownedSource.bindingId 14) (.signed .i32 normal.count)))
    (locations : RowLocations normal)
    (heap : before.heap = origin.heap.borrowBlock normal.geometry.block.base)
    (views : before.i32ArrayViews = origin.i32ArrayViews) :
    EnvStmt extractedProgram origin before (ownedSource.bindingStatement 15)
      (fun _ : Int => (entryValues raw workspace).set (ownedSource.bindingId 14) (.signed .i32 normal.count))
      (ScanDone scan) := by
  have initialized : EnvStmt extractedProgram origin before (ownedSource.bindingStatement 15)
      (fun _ : ScanExit => (entryValues raw workspace).set (ownedSource.bindingId 14) (.signed .i32 normal.count))
      (fun exit => ScanDone scan exit.answer) := by
    core_env_scopes env
    · rename_i loweredEnv scanEnv
      apply actualScanSuffix (scan := scan) (cursor := 0) (entries := []) scanEnv
      · change LoopFacts scan 0 [] before.heap
        rw [heap]; exact LoopFacts.start scan locations
      · exact views
    all_goals
      try dsimp only [loopValues]
      core_env_values
  apply EnvStmt.adapt initialized
  intro exit completion after finalEnv observed
  exact ⟨exit.answer, rfl, observed⟩

/-- Only the heap/world observations vary through lexical scopes. Canonical
state-indexed catalog invariants are reified once at the public call boundary. -/
private noncomputable def OwnedObservation (domain : OriginalDomain raw workspace origin)
    (result : Int) (heap : Heap) (world : World.State) : Prop := by
  classical
  exact match domain with
  | .early _ => result = -1 ∧ heap = origin.heap ∧ world = origin.world
  | .header geometry _ _ _ _ =>
      result = -1 ∧ heap = origin.heap.borrowBlock geometry.block.base ∧ world = origin.world
  | .normal table _ _ _ _ _ validation scans =>
      if valid : SemanticValidSlice validation.values validation.index table.rowValue
          0 validation.values.count.toInt raw.tokenCount.toInt then
        ScanOutput (scans valid) result heap
      else result = -1 ∧ heap = origin.heap.borrowBlock table.geometry.block.base ∧ world = origin.world

private theorem OwnedObservation.project (domain : OriginalDomain raw workspace origin)
    (result : OwnedObservation domain answer after.heap after.world)
    (formed : after.CellsWellFormed) (views : after.i32ArrayViews = origin.i32ArrayViews) :
    OwnedOutcome domain answer after := by
  classical
  cases domain with
  | early rejected => exact result
  | header geometry native good nonnegative rejected => exact result
  | normal normal locations earlyGood descriptorGood exactRows positive validation scans =>
      by_cases valid : SemanticValidSlice validation.values validation.index normal.rowValue
          0 validation.values.count.toInt raw.tokenCount.toInt
      · simp only [OwnedObservation, OwnedOutcome, dif_pos valid] at result ⊢
        exact result.project formed (views.trans (scans valid).invariant.noViews)
      · simpa only [OwnedObservation, OwnedOutcome, dif_neg valid] using result

private def OwnedDone (domain : OriginalDomain raw workspace origin)
    (answer : Int) (completion : Completion) (after : State) : Prop :=
  completion = .returned (some (.signed .i32 answer)) ∧
    after.i32ArrayViews = origin.i32ArrayViews ∧ OwnedObservation domain answer after.heap after.world

private def validationFrom (original : OriginalSlice values index offset count tokenCount heap)
    (tableEq : index.table = table) (reads : HeapReads heap current)
    (native : BorrowedTable table current) (locations : RowLocations native.toNormalTable)
    (identity : ∀ position inside, (native.rows position inside).row = rows position) :
    NativeSlice values index rows offset count tokenCount current := by
  subst table
  exact NativeSlice.ofReads original reads (fun _ => native) (fun _ => locations) (fun _ => identity)

private theorem actualEntry
    (env : LocalEnv origin before (entryValues raw workspace))
    (heap : before.heap = origin.heap) (world : before.world = origin.world)
    (views : before.i32ArrayViews = origin.i32ArrayViews)
    (domain : OriginalDomain raw workspace origin) :
    EnvStmt extractedProgram origin before entrySuffix
      (fun _ : Int => entryValues raw workspace) (OwnedDone domain) := by
  classical
  cases domain with
  | early rejected =>
      obtain ⟨ready, guard, pure⟩ := actualEarlyGuard env rejected
      have readyEnv := env.afterExpr guard pure.cells
      obtain ⟨after, returned, tail⟩ := actualInvalidReturn readyEnv.formed
      rw [reachedHeaderShape]
      exact EnvStmt.ofRun (result := (-1 : Int))
        (RunsStmt.sequenceCompleted (RunsStmt.ifThenElseTrue guard returned) (by simp) _)
        (readyEnv.afterStmt returned tail.cells)
        ⟨rfl, tail.views.trans (pure.views.trans views),
          rfl, tail.heap.trans (pure.heap.trans heap), tail.world.trans (pure.world.trans world)⟩
  | header geometry native earlyGood nonnegative rejected =>
      let currentGeometry : HeaderGeometry raw.allocationTable before.heap := {
        geometry with found := by rw [heap]; exact geometry.found
                      unique := by rw [heap]; exact geometry.unique }
      let currentHeader : NativeHeader raw.allocationTable before.heap := {
        native with snapshot := by rw [heap]; exact native.snapshot }
      obtain ⟨ready, guard, effect⟩ := actualEntryHeaderGuard env currentGeometry currentHeader earlyGood
      have readyEnv := env.afterExpr guard effect.1
      have borrowed : ready.heap = origin.heap.borrowBlock geometry.block.base := by
        simpa only [currentGeometry, heap] using effect.2.2.2
      have readyWorld := effect.2.1.trans world
      have readyViews := effect.2.2.1.trans views
      rw [reachedHeaderShape]
      cases truth : entryHeaderBool raw workspace native.header with
      | true =>
          rw [truth] at guard
          obtain ⟨after, returned, pure⟩ := actualInvalidReturn readyEnv.formed
          exact EnvStmt.ofRun (result := (-1 : Int))
            (RunsStmt.sequenceCompleted (RunsStmt.ifThenElseTrue guard returned) (by simp) _)
            (readyEnv.afterStmt returned pure.cells)
            ⟨rfl, pure.views.trans readyViews, rfl, pure.heap.trans borrowed, pure.world.trans readyWorld⟩
      | false =>
          have nonpositive : native.header.rows.toInt ≤ 0 := by
            have good := truth
            simp only [entryHeaderBool, Bool.or_eq_false_iff, Bool.not_eq_eq_eq_not,
              Bool.not_false, decide_eq_true_eq, decide_eq_false_iff_not] at good
            rcases rejected with mismatch | descriptors | nonpositive
            · exact False.elim (mismatch good.1.1.1.1.1)
            · unfold RawInputs.afterHeaderReject at descriptors
              rcases descriptors with bad | bad | bad | bad | bad
              · exact False.elim (good.1.1.1.1.2 bad)
              · exact False.elim (good.1.1.1.2 bad)
              · exact False.elim (good.1.1.2 bad)
              · exact False.elim (good.1.2 bad)
              · exact False.elim (good.2 bad)
            · exact nonpositive
          rw [truth] at guard
          apply EnvStmt.sequenceNext (RunsStmt.ifThenElseFalse guard (RunsStmt.skip _ _))
          apply EnvStmt.letFramed readyEnv (by rfl)
            (insideValues := fun value (_ : Int) => (entryValues raw workspace).set (ownedSource.bindingId 14) value)
            (spec := fun value state => value = .signed .i32 native.header.rows.toInt ∧ PureFrame ready state)
          · obtain ⟨state, run, pure⟩ := actualBorrowedHeader geometry native borrowed readyEnv.formed
            have called := RunsExpr.callArguments (.cons (.ofStable (.local (readyEnv.read (id := ownedSource.bindingId 2) (by rfl))) rfl) .nil) run
            exact ⟨_, state, RunsExpr.field called (by rfl), pure.cells, rfl, pure⟩
          · intro value state rowEnv observed
            obtain ⟨valueEq, pure⟩ := observed
            subst value
            obtain ⟨after, returned, tail⟩ := actualInvalidReturn rowEnv.formed
            change EnvStmt extractedProgram origin _ headerRowsSuffix _ _
            rw [headerRowsShape]
            apply EnvStmt.ofRun (result := (-1 : Int))
              (RunsStmt.sequenceCompleted (RunsStmt.ifThenElseTrue (by core_env_run) returned) (by simp) _)
              (rowEnv.afterStmt returned tail.cells)
            exact ⟨rfl, tail.views.trans (pure.views.trans readyViews), rfl,
              tail.heap.trans (pure.heap.trans borrowed), tail.world.trans (pure.world.trans readyWorld)⟩
          · core_env_values
  | normal normal locations earlyGood descriptorGood exactRows positive validation scans =>
      let currentGeometry : HeaderGeometry raw.allocationTable before.heap := {
        normal.geometry with found := by rw [heap]; exact normal.geometry.found
                             unique := by rw [heap]; exact normal.geometry.unique }
      let currentHeader : NativeHeader raw.allocationTable before.heap := {
        normal.header with snapshot := by rw [heap]; exact normal.header.snapshot }
      obtain ⟨ready, guard, effect⟩ := actualEntryHeaderGuard env currentGeometry currentHeader earlyGood
      have guardFalse := entryHeaderFalse descriptorGood exactRows
      rw [guardFalse] at guard
      have readyEnv := env.afterExpr guard effect.1
      have borrowed : ready.heap = origin.heap.borrowBlock normal.geometry.block.base := by
        simpa only [currentGeometry, heap] using effect.2.2.2
      have readyWorld := effect.2.1.trans world
      have readyViews := effect.2.2.1.trans views
      rw [reachedHeaderShape]
      apply EnvStmt.sequenceNext (RunsStmt.ifThenElseFalse guard (RunsStmt.skip _ _))
      apply EnvStmt.letFramed readyEnv (by rfl)
        (insideValues := fun value (_ : Int) => (entryValues raw workspace).set (ownedSource.bindingId 14) value)
        (spec := fun value state => value = .signed .i32 normal.count ∧ PureFrame ready state)
      · obtain ⟨state, run, pure⟩ := actualBorrowedHeader normal.geometry normal.header borrowed readyEnv.formed
        have called := RunsExpr.callArguments (.cons (.ofStable (.local (readyEnv.read (id := ownedSource.bindingId 2) (by rfl))) rfl) .nil) run
        have projected := RunsExpr.field (fieldId := 1) called rfl
        change RunsExpr extractedProgram ready (ownedSource.bindingInitializer 14)
          (.signed .i32 normal.header.header.rows.toInt) state at projected
        refine ⟨_, state, ?_, pure.cells, rfl, pure⟩
        change RunsExpr extractedProgram ready (ownedSource.bindingInitializer 14)
          (.signed .i32 normal.count) state
        simpa only [exactRows, normal.countEq] using projected
      · intro value state rowEnv observed
        obtain ⟨valueEq, pure⟩ := observed
        subst value
        have rowHeap : state.heap = origin.heap.borrowBlock normal.geometry.block.base := pure.heap.trans borrowed
        have reads : HeapReads origin.heap state.heap := by
          intro pointer offset byte loaded
          rw [rowHeap, Heap.loadByte_borrowBlock]; exact loaded
        have represented : (tableRep normal).holds state.heap := by
          rw [rowHeap]; exact tableRep_borrow normal locations
        have unique : HeapBlockBasesUnique state.heap := by
          rw [rowHeap]; exact normal.geometry.unique.borrowBlock
        let native := tableRep_native normal represented unique
        let nativeValues := validationFrom (rows := normal.rowValue) validation.native validation.table reads native
          (tableRep_locations normal represented unique)
          (fun index inside => by rw [normal.rowValue_inside inside]; rfl)
        obtain ⟨checked, validator, checkFrame⟩ := actualValid
          (before := state.bindLocal (ownedSource.bindingId 14) (.signed .i32 normal.count))
          validation.values validation.index normal.rowValue
          raw.tokenCount nativeValues rfl rowEnv.formed
        change RunsExpr extractedProgram _
          (.call Extracted.«lowering::value_catalog».Functions.«valid».core.id
            [.value validation.values.value, .value (.signed .i32 raw.tokenCount.toInt), .value validation.index.value])
          (.boolean (sliceResult validation.values validation.index normal.rowValue
            0 validation.values.count.toInt raw.tokenCount.toInt)) checked at validator
        have actualValidator : RunsExpr extractedProgram
            (state.bindLocal (ownedSource.bindingId 14) (.signed .i32 normal.count))
            (.unary .logicalNot (.call Extracted.«lowering::value_catalog».Functions.«valid».core.id
              [.local (ownedSource.bindingId 4), .local (ownedSource.bindingId 10), .field (.local (ownedSource.argumentId 0)) 4]))
            (.boolean (!sliceResult validation.values validation.index normal.rowValue
              0 validation.values.count.toInt raw.tokenCount.toInt)) checked := by
          apply RunsExpr.unary (value := .boolean (sliceResult validation.values validation.index normal.rowValue
            0 validation.values.count.toInt raw.tokenCount.toInt))
            (RunsExpr.callArguments (values := [validation.values.value, .signed .i32 raw.tokenCount.toInt,
              validation.index.value]) ?_ validator) rfl
          rw [validation.valuesValue, validation.indexValue]
          core_facts [raw]
          core_arguments
        have checkedEnv := rowEnv.afterExpr actualValidator checkFrame.cells
        have checkedHeap := checkFrame.heap.trans rowHeap
        have checkedWorld := checkFrame.world.trans (pure.world.trans readyWorld)
        have checkedViews := checkFrame.views.trans (pure.views.trans readyViews)
        change EnvStmt extractedProgram origin _ headerRowsSuffix _ _
        rw [headerRowsShape]
        apply EnvStmt.guardFalse (by core_env_run)
        cases accepted : sliceResult validation.values validation.index normal.rowValue
            0 validation.values.count.toInt raw.tokenCount.toInt with
        | false =>
            rw [accepted] at actualValidator
            have invalid : ¬SemanticValidSlice validation.values validation.index normal.rowValue
                0 validation.values.count.toInt raw.tokenCount.toInt := by
              intro valid; have truth := sliceResult_iff.mpr valid; rw [accepted] at truth; cases truth
            obtain ⟨after, returned, tail⟩ := actualInvalidReturn checkedEnv.formed
            apply EnvStmt.ofRun (result := (-1 : Int))
              (RunsStmt.sequenceCompleted (RunsStmt.ifThenElseTrue actualValidator returned) (by simp) _)
              (checkedEnv.afterStmt returned tail.cells)
            refine ⟨rfl, tail.views.trans checkedViews, ?_⟩
            simp only [OwnedObservation, dif_neg invalid]
            exact ⟨True.intro, tail.heap.trans checkedHeap, tail.world.trans checkedWorld⟩
        | true =>
            rw [accepted] at actualValidator
            apply EnvStmt.sequenceNext (RunsStmt.ifThenElseFalse actualValidator (RunsStmt.skip _ _))
            have valid := sliceResult_iff.mp accepted
            apply EnvStmt.mono (actualScanInitializers (scan := scans valid) checkedEnv locations checkedHeap checkedViews)
            intro answer completion after finalEnv ⟨returned, resultSpec, finalViews⟩
            refine ⟨returned, finalViews, ?_⟩
            simpa only [OwnedObservation, dif_pos valid, restoreLocals_heap] using resultSpec
      · core_env_values

/-- Finite actual Core1180 execution on every admitted original input. -/
theorem actualOwnedLowering : OwnedLoweringCorrect := by
  intro raw workspace origin domain formed
  let post := fun result heap world views =>
    views = origin.i32ArrayViews ∧ OwnedObservation domain result heap world
  obtain ⟨result, after, run, cells, locals, views, observed⟩ := actualOwnedPrelude raw workspace formed post (by
    intro state env heap world views
    obtain ⟨result, completion, after, run, finalEnv, returned, finalViews, observed⟩ :=
      actualEntry env heap world views domain
    exact ⟨completion, after, run, result, returned, finalEnv.cells, finalViews, observed⟩)
  exact ⟨result, after, run, cells, locals, views,
    OwnedObservation.project domain observed (cells.after_cellsWellFormed formed) views⟩

#print axioms actualOwnedLowering

end IRBodyOwnedProof
