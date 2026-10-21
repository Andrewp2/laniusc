import verified_compiler.tests.direct_match_arms
import verified_compiler.tests.direct_surface_fallback

namespace SurfaceMatchProof

open Lanius Lanius.Core Lanius.Semantics Lanius.Extraction Lanius.Memory
open SurfaceBooleanProof SurfaceDispatchProof SurfaceExpressionTreeProof IRBuilderNavigationProof IRNavigationProof
open SurfaceOperationsProof MatchArmsProof

private def source := MatchBindingsProof.source
attribute [local simp] source MatchBindingsProof.sourceBindings Function.bindingId Function.argumentId
private def cursorId := source.bindingId 3
private def childId := source.bindingId 4
private def ordinalId := source.bindingId 5
private def right (ordinal : Nat) : Expr := match source.effectExpression ordinal with
  | .assign _ _ expression => expression | _ => .value .unit
private def arguments (ordinal : Nat) : List Expr := match right ordinal with
  | .call _ expressions => expressions | _ => []
private def afterHeader : Stmt := match source.body with
  | some (.letLocal _ _ _ (.letLocal _ _ _ (.letLocal _ _ _ body))) => body | _ => .skip
private def childInitializer : Expr := match afterHeader with
  | .letLocal _ _ _ (.sequence _ (.sequence _ (.letLocal _ _ initial _))) => initial
  | _ => .value .unit
attribute [local simp] cursorId childId ordinalId

def atom : Expression → Bool
  | .literal _ | .integer _ | .localName _ _ => true
  | .unary _ _ | .binary _ _ _ => false

private theorem optionalNot (truth : Bool) (byte : UInt8) :
    (if !truth then [byte] else []) = (if truth then [] else [byte]) := by cases truth <;> rfl
private theorem glyph40 : UInt8.ofNat 40 = (40 : UInt8) := rfl
private theorem glyph41 : UInt8.ofNat 41 = (41 : UInt8) := rfl
attribute [local simp] glyph40 glyph41

/-- Classify the represented scrutinee using the actual native reader. The
    existing annotation and event facts suffice; no typing tree is rebuilt. -/
theorem actualClassifier (tree : Ready region { heap := reference }) (expression : Expression)
    (represented : SurfaceExpressionTreeProof.Represents tree expression index scope)
    (reads : HeapReads reference state.heap) (formed : state.CellsWellFormed) :
    ∃ after, RunsExpr extractedProgram state
      (.call classifier.id [.value tree.value, .value (.signed .i32 index)])
      (.boolean (atom expression)) after ∧ PureFrame state after := by
  let live := tree.ofReads reads
  cases expression with
  | literal value =>
      obtain ⟨inside, event, annotations, annotation⟩ := represented
      exact actualBooleanClassifier live value inside event annotations (reads.rawSlice annotation) formed
  | integer value =>
      obtain ⟨inside, event, canonical, allowed⟩ := represented
      exact actualIntegerClassifier live value inside event allowed formed
  | localName token spelling =>
      obtain ⟨inside, event, _⟩ := represented
      exact SurfaceLocalProof.actualClassifier live token inside event formed
  | unary operation child =>
      obtain ⟨inside, event, _⟩ := represented
      have read := live.eventReads index inside
      rw [event] at read
      exact actualNonAtom operation.event live inside read (by cases operation <;> rfl) formed
  | binary operation left right =>
      obtain ⟨inside, event, _⟩ := represented
      have read := live.eventReads index inside
      rw [event] at read
      exact actualBinaryClassifier operation live inside read formed

private theorem classifiedMatch (result : IRTypeRefProof.Reference) (typeId count : Int)
    (classified : IRShapeProof.Classifies (IRShapeProof.matchEvent result typeId count)
      (IRShapeProof.shapeValue (IRShapeProof.kindValue kind) arity (IRShapeProof.ruleValue rule))) :
    IRShapeProof.shapeValue (IRShapeProof.kindValue kind) arity (IRShapeProof.ruleValue rule) =
      IRShapeProof.matchShape result typeId count := by
  have formed : ({} : State).CellsWellFormed := by simp [State.CellsWellFormed]
  obtain ⟨_, classifiedRun, _⟩ := IRShapeProof.actualEvent classified formed
  obtain ⟨_, headerRun, _⟩ := IRShapeProof.actualMatchEvent result typeId count formed
  exact (classifiedRun.agree headerRun).1

/-- Derive the scrutinee/arm child chain and overflow-safe first-child arity
    from the existing builder tree and actual match header. -/
theorem matchLayout {count typeId : Nat} (tree : Ready region state) (inside : index < region.count)
    (event : region.events index = IRShapeProof.matchEvent result typeId count) (bounded : count < 2 ^ 31) :
    0 < count ∧ count + 1 < 2 ^ 31 ∧ region.arities index = (count + 1 : Nat) ∧
      region.rules index = .ExpressionThenArms ∧ tree.Children index 0 (count + 1) (index + 1) := by
  have classified := region.classified index inside
  rw [event] at classified
  have layout := classifiedMatch result typeId count classified
  have nonnegative := (tree.suffix index (Nat.zero_le _) inside).1
  unfold IRShapeProof.matchShape at layout
  split at layout
  · simp [IRShapeProof.shapeValue] at layout
    omega
  · rename_i valid
    simp [IRShapeProof.shapeValue, IRShapeProof.kindValue, IRShapeProof.ruleValue] at layout
    have wrapped : 0 ≤ wrapSigned extractedProgram.target .i32 ((count : Int) + 1) := by omega
    have fits := i32_succ_bound extractedProgram.target count bounded wrapped
    have normal := wrapSigned_i32_nat_lt extractedProgram.target (count + 1) fits
    simp only [Int.natCast_add, Int.natCast_one] at normal
    have arity : region.arities index = (count + 1 : Nat) := by omega
    have rule : region.rules index = .ExpressionThenArms := by
      cases kind : region.rules index <;> simp_all [IRShapeProof.ruleValue]
    exact ⟨by omega, fits, arity, rule, by
      simpa only [arity, Int.toNat_natCast] using tree.childrenStart inside⟩

/-- Native facts for one match. The specification relates to the existing
    tree and catalogs, never to successful printer execution or a typing tree. -/
structure Match (reference : Heap) (region : IRBuilderCallProof.Region original) where
  tree : Ready region { heap := reference }
  metadata : Metadata
  index : Nat
  result : IRTypeRefProof.Reference
  typeId : Nat
  scrutinee : List UInt8
  atomic : Bool
  arms : List (Arm reference)
  inside : index < region.count
  event : region.events index = IRShapeProof.matchEvent result typeId arms.length
  fits : arms.length < 2 ^ 31
  scrutineeInside : index + 1 < region.count
  armsRep : MatchArmsProof.Represents tree metadata typeId arms (tree.ends (index + 1))

def bytes (scrutinee : List UInt8) (atomic : Bool) (arms : List (Arm reference)) (enclosed : Bool) : List UInt8 :=
  (if enclosed then [40] else []) ++ World.utf8Bytes "match " ++
    (if atomic then [] else [40]) ++ scrutinee ++
    (if atomic then [] else [41]) ++ World.utf8Bytes " with\n" ++
    MatchArmsProof.output arms ++ (if enclosed then [41] else [])
def output (matching : Match reference region) (enclosed : Bool) : List UInt8 :=
  bytes matching.scrutinee matching.atomic matching.arms enclosed
attribute [local simp] output bytes

/-- Internal classifier obligation, proved directly from the represented node
    by the final expression closure. It is not a native-input field. -/
def Classifier (tree : Ready region { heap := reference }) (index : Nat) (atomic : Bool) : Prop :=
  ∀ {state}, HeapReads reference state.heap → state.CellsWellFormed →
    ∃ after, RunsExpr extractedProgram state
      (.call classifier.id [.value tree.value, .value (.signed .i32 index)])
      (.boolean atomic) after ∧ PureFrame state after
def call (context : Context state) (index : Nat) (enclosed : Bool) : Expr :=
  .call source.id ([context.views, .signed .i32 index, .signed .i32 context.position, .boolean enclosed].map Expr.value)

private def byteSource := Extracted.«verified::lean_output».Functions.«byte».core
private def delimiterArguments (byte : Fin 256) : List Expr :=
  [.field (.local (source.bindingId 0)) 6, .field (.local (source.bindingId 0)) 7,
    .local cursorId, .value (.signed .i32 byte.val)]
private def delimiterGuard : Expr :=
  .unary .logicalNot (.call classifier.id [.field (.local (source.bindingId 0)) 0, .local childId])

/-- Both operand delimiters reuse this same native guard and byte writer.
    The guard's temporary cells are included in the output/caller frame. -/
private theorem actualDelimiter (matching : Match reference region) (context : Context base)
    (classify : Classifier matching.tree (matching.index + 1) matching.atomic)
    (input : Protected context reference) (representation : context.tree = matching.tree.value)
    (cursor : WriterCursor base current cursorId cell (context.address + context.position)
      context.position front (scope := scope)) (byte : Fin 256)
    (view : current.local? (source.bindingId 0) = some context.value)
    (child : current.local? childId = some (.signed .i32 (matching.index + 1 : Nat)))
    (prefixRoom : context.position + front.length ≤ context.capacity)
    (room : (!matching.atomic) = true → context.position + (front ++ [UInt8.ofNat byte.val]).length ≤ context.capacity)
    (environment : WriterEnvironment base) :
    ∃ after, RunsStmt extractedProgram current (.ifThenElse delimiterGuard
      (.sequence (.expression (.assign .set (.local cursorId)
        (.call byteSource.id (delimiterArguments byte)))) .skip) .skip) .next after ∧
      WriterCursor base after cursorId cell (context.address + context.position) context.position
        (front ++ if !matching.atomic then [UInt8.ofNat byte.val] else []) (scope := scope) ∧
      (∀ key value, current.local? key = some value → current.cellId? key ≠ some cell → after.local? key = some value) := by
  have formed := environment.formed
  have classified : ∃ ready, RunsExpr extractedProgram current delimiterGuard
      (.boolean (!matching.atomic)) ready ∧ PureFrame current ready := by
    apply RunsExpr.unaryPure (value := .boolean matching.atomic)
    · apply RunsExpr.callPureArguments (values := [context.tree, .signed .i32 (matching.index + 1 : Nat)])
      · core_arguments
      · rw [representation]
        exact classify
          (input.afterOutput cursor.frame.output prefixRoom).memory.reads (cursor.frame.afterFormed formed)
    · cases matching.atomic <;> rfl
  exact cursor.branchArguments formed (!matching.atomic) classified
    (values := [.rawSlice (.scalar (.signed .i32)) context.address context.words,
      .signed .i32 context.capacity, .signed .i32 (context.position + front.length : Nat), .signed .i32 byte.val])
    (suffix := [UInt8.ofNat byte.val]) (expressions := delimiterArguments byte)
    (fun yes ready pure => OutputWriterProof.byteAt context.toBuffer (cursor.afterPure pure).frame byte (room yes) environment)
    (fun ready pure => by
      have viewReady := pure.localFound view
      have cursorReady := pure.localFound cursor.value
      core_arguments)

/-- One enclosing match step. The final expression induction supplies the
    scrutinee classifier/writer and all arm bodies, without assuming execution. -/
theorem actualCallStep (matching : Match reference region) (context : Context state)
    (classify : Classifier matching.tree (matching.index + 1) matching.atomic)
    (scrutineeWriter : Writer Context.expressionCall reference matching.tree.value
      (matching.index + 1) matching.scrutinee (.fixed matching.metadata))
    (armWriters : BodyWriters matching.tree matching.metadata matching.arms (matching.tree.ends (matching.index + 1)))
    (input : Protected context reference) (representation : context.tree = matching.tree.value)
    (names : context.metadata = matching.metadata) (enclosed : Bool)
    (room : context.position + (output matching enclosed).length ≤ context.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (call context matching.index enclosed)
      (.signed .i32 (context.position + (output matching enclosed).length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) (output matching enclosed) := by
  have formed := environment.formed
  obtain ⟨positive, _, arity, _, chain⟩ := matchLayout matching.tree matching.inside matching.event matching.fits
  have nonempty : matching.arms ≠ [] := by intro empty; simp only [empty, List.length_nil] at positive; omega
  have scrutineeInside := matching.scrutineeInside
  have afterScrutinee : matching.tree.Children matching.index 1 matching.arms.length
      (matching.tree.ends (matching.index + 1)).toNat := by
    cases chain with | cons _ _ _ _ remaining => exact remaining
  have afterOrder : matching.index < (matching.tree.ends (matching.index + 1)).toNat := by
    cases chain with | cons _ _ forward _ _ => omega
  have afterNonnegative : 0 ≤ matching.tree.ends (matching.index + 1) := by
    cases chain with | cons _ _ forward _ _ => omega
  have measured := room
  simp only [output, bytes, List.length_append] at measured
  have matchLength : (World.utf8Bytes "match ").length = 6 := rfl
  have withLength : (World.utf8Bytes " with\n").length = 6 := rfl
  core_call_framed Lanius.Extraction.RunsExpr.callWriter source as callee
  have calleeHeap : callee.heap = state.heap := rfl
  let viewed := callee.bindLocal (source.bindingId 0) context.value
  let events := viewed.bindLocal (source.bindingId 1) (.rawSlice eventType region.eventsAddress region.eventsLength)
  have eventRead := input.memory.reads.rawSlice (matching.tree.eventReads matching.index matching.inside)
  rw [matching.event] at eventRead
  apply actualViewEvents (context.reheap (after := callee) rfl) matching.tree representation (by core_local) (by core_formed)
  apply RunsStmt.letReadWriter (value := IRShapeProof.matchHeaderValue matching.result matching.typeId matching.arms.length)
  · apply RunsExpr.callPureArguments (values := [IRShapeProof.matchEvent matching.result matching.typeId matching.arms.length])
    · core_arguments
    · exact MatchMetadataProof.actualHeader _ _ _ (by core_formed)
  · intro headerReady headerPure
    let base := headerReady.bindLocal (source.bindingId 2)
      (IRShapeProof.matchHeaderValue matching.result matching.typeId matching.arms.length)
    let start : Context base := context.reheap headerPure.heap
    let retained : Protected start reference := ⟨by
      simpa only [start, Context.reheap, base, State.bindLocal, State.bindCell, headerPure.heap, calleeHeap] using input.memory,
      by simpa only [readRawSliceIndex, start, Context.reheap, Context.value] using input.viewRead⟩
    have startPosition : start.position = context.position := rfl
    have startCapacity : start.capacity = context.capacity := rfl
    let env := environment.reheap (after := base) headerPure.heap headerPure.views (by core_formed)
    have formed := env.formed
    have baseViews : base.local? (source.argumentId 0) = some context.views := by core_local
    have baseIndex : base.local? (source.argumentId 1) = some (.signed .i32 matching.index) := by core_local
    have basePosition : base.local? (source.argumentId 2) = some (.signed .i32 context.position) := by core_local
    have baseView : base.local? (source.bindingId 0) = some context.value := by core_local
    have baseEnclosed : base.local? (source.argumentId 3) = some (.boolean enclosed) := by core_local
    let bound := base.bindLocal cursorId (.signed .i32 context.position)
    have cursor : WriterCursor base bound cursorId base.nextCell
        (context.address + context.position) context.position [] := WriterCursor.begin formed env.unique cursorId
    have enclosedRead : bound.local? (source.argumentId 3) = some (.boolean enclosed) := by core_local
    obtain ⟨opened, openingRun, cursor1, _⟩ := cursor.branchArguments
      (conditionExpr := .local (source.argumentId 3)) formed enclosed
      ⟨bound, by core_run, PureFrame.refl (cursor.frame.afterFormed formed)⟩
      (values := [.rawSlice (.scalar (.signed .i32)) context.address context.words,
        .signed .i32 context.capacity, .signed .i32 context.position, .signed .i32 40])
      (suffix := [40]) (expressions := arguments 0)
      (fun yes ready pure => by
        have space : start.position + ([] ++ [40]).length ≤ start.capacity := by
          simp only [yes, ↓reduceIte, matchLength, withLength,
            List.length_cons, List.length_nil] at measured; change context.position + 1 ≤ context.capacity; omega
        exact OutputWriterProof.byteAt start.toBuffer (cursor.afterPure pure).frame ⟨40, by decide⟩ space env)
      (fun ready pure => by
        let liveCursor := cursor.afterPure pure
        core_facts 1 [liveCursor]
        core_arguments)
    core_facts 1 [cursor1]
    obtain ⟨prefixed, prefixRun, cursor2, _⟩ := cursor1.advanceArgumentsKeeping formed
      (OutputWriterProof.textAt start.toBuffer cursor1.frame "match " 6 rfl
        (by change context.position + (([] ++ if enclosed then [40] else []) ++ World.utf8Bytes "match ").length ≤ context.capacity
            simp only [List.length_append, List.length_nil, matchLength, withLength] at measured ⊢; omega) env)
      (expressions := arguments 1) (by core_arguments) rfl
    let live2 := matching.tree.ofReads (retained.afterOutput cursor2.frame.output (by
      simp only [startPosition, startCapacity, List.length_append, List.length_nil, matchLength, withLength] at measured ⊢; omega)).memory.reads
    obtain ⟨childReady, firstChild, childPure⟩ := live2.firstChild matching.inside (cursor2.frame.afterFormed formed)
    have positiveArity : ¬ region.arities matching.index ≤ 0 := by rw [arity]; omega
    simp only [Ready.firstIndex, if_neg positiveArity] at firstChild
    have firstRun : RunsExpr extractedProgram prefixed childInitializer
        (.signed .i32 (matching.index + 1 : Nat)) childReady := by
      change RunsExpr extractedProgram prefixed (matching.tree.firstChildCall matching.index)
        (.signed .i32 ((matching.index : Int) + 1)) childReady at firstChild
      simp only [Ready.firstChildCall] at firstChild
      rw [← representation] at firstChild
      have positionEq : ((matching.index : Int) + 1) = (matching.index + 1 : Nat) := by omega
      rw [positionEq] at firstChild
      exact RunsExpr.callArguments (values := [context.tree, .signed .i32 matching.index]) (by core_arguments) (by
        exact firstChild)
    have cursorChild := Nat.lt_of_lt_of_le
      ((cursor2.frame.afterFormed formed).localCellBound cursor2.slot cursor2.value) childPure.cells.choose_spec.2.1
    let childBound := childReady.bindLocal childId (.signed .i32 (matching.index + 1 : Nat))
    let childCursor := (cursor2.afterPure childPure).bindLocal formed childId
      (.signed .i32 (matching.index + 1 : Nat)) (by decide)
    have childSlot : childBound.cellId? childId = some childReady.nextCell := State.bindLocal_cellId _ _ _
    have childSeparated : childBound.cellId? childId ≠ some base.nextCell := by
      rw [childSlot]
      exact fun equal => Nat.ne_of_gt cursorChild (Option.some.inj equal)
    core_facts 1 [childCursor]
    have child : childBound.local? childId = some (.signed .i32 (matching.index + 1 : Nat)) := by core_local
    obtain ⟨scrutineeOpen, scrutineeOpening, cursor3, kept3⟩ := actualDelimiter matching start classify retained representation
      childCursor ⟨40, by decide⟩ (by core_local) child
      (by simp only [startPosition, startCapacity, List.length_append, List.length_nil, matchLength, withLength] at measured ⊢; omega)
      (fun yes => by cases h : matching.atomic <;>
        simp only [h, Bool.not_false, Bool.not_true, Bool.false_eq_true, ↓reduceIte, startPosition, startCapacity,
          List.length_append, List.length_cons, List.length_nil, matchLength, withLength] at measured yes ⊢ <;> omega) env
    simp only [start, Context.reheap, glyph40] at cursor3
    have child3 := kept3 childId _ child childSeparated
    core_facts 1 [cursor3]
    let front3 : List UInt8 := (if enclosed then [40] else []) ++ World.utf8Bytes "match " ++
      (if !matching.atomic then [40] else [])
    have cursor3Value : scrutineeOpen.local? cursorId =
        some (.signed .i32 (context.position + front3.length : Nat)) := by
      simpa only [front3, List.nil_append] using cursor3.value
    have views3 : scrutineeOpen.local? (source.argumentId 0) = some context.views :=
      cursor3.localFound (by decide) baseViews (by rfl)
    let ctx3 := start.afterOutput retained cursor3.frame.output (by
      simp only [startPosition, startCapacity, optionalNot, List.length_append,
        List.length_cons, List.length_nil, matchLength, withLength] at measured ⊢; omega)
    have printScrutinee := scrutineeWriter ctx3
      (retained.afterOutput cursor3.frame.output (by
        simp only [startPosition, startCapacity, optionalNot, List.length_append,
          List.length_cons, List.length_nil, matchLength, withLength] at measured ⊢; omega))
      representation names
      (by simp only [ctx3, Context.afterOutput, startPosition, startCapacity, optionalNot,
        List.length_append, List.length_cons, List.length_nil, matchLength, withLength] at measured ⊢; omega)
      (env.afterWrite cursor3.frame)
    obtain ⟨printed, scrutineeRun, cursor4, kept4⟩ := cursor3.advanceArgumentsKeeping
      (suffix := matching.scrutinee)
      (values := [context.views, .signed .i32 (matching.index + 1 : Nat),
        .signed .i32 (context.position + front3.length : Nat)]) formed
      (by simpa only [Context.expressionCall, ctx3, Context.afterOutput, start, Context.reheap,
        Context.views, front3, List.nil_append, Nat.add_assoc] using printScrutinee)
      (expressions := arguments 3) (by core_arguments)
      (by simp only [front3, List.nil_append, List.length_append, Nat.add_assoc])
    have child4 := kept4 childId _ child3 (by rw [cursor3.slotsEq childCursor]; exact childSeparated)
    obtain ⟨scrutineeClosed, scrutineeClosing, cursor5, kept5⟩ := actualDelimiter matching start classify retained representation
      cursor4 ⟨41, by decide⟩ (cursor4.localFound (by decide) baseView (by rfl)) child4
      (by simp only [startPosition, startCapacity, optionalNot, List.length_append,
        List.length_cons, List.length_nil, matchLength, withLength] at measured ⊢; omega)
      (fun yes => by cases h : matching.atomic <;>
        simp only [h, Bool.not_false, Bool.not_true, Bool.false_eq_true, ↓reduceIte, startPosition, startCapacity,
          List.length_append, List.length_cons, List.length_nil, matchLength, withLength] at measured yes ⊢ <;> omega) env
    simp only [start, Context.reheap, glyph41] at cursor5
    have child5 := kept5 childId _ child4 (by rw [cursor4.slotsEq childCursor]; exact childSeparated)
    core_facts 1 [cursor5]
    obtain ⟨separated, separatorRun, cursor6, kept6⟩ := cursor5.advanceArgumentsKeeping formed
      (OutputWriterProof.textAt start.toBuffer cursor5.frame " with\n" 6 rfl
        (by simp only [startPosition, startCapacity, optionalNot, List.length_append,
          List.length_cons, List.length_nil, matchLength, withLength] at measured ⊢; omega) env)
      (expressions := arguments 5) (by core_arguments) rfl
    have child6 := kept6 childId _ child5 (by rw [cursor5.slotsEq childCursor]; exact childSeparated)
    let live6 := matching.tree.ofReads (retained.afterOutput cursor6.frame.output (by
      simp only [startPosition, startCapacity, optionalNot, List.length_append,
        List.length_cons, List.length_nil, matchLength, withLength] at measured ⊢; omega)).memory.reads
    obtain ⟨armReady, navigate, navigatePure⟩ := live6.nextChild (by omega : matching.index < matching.index + 1)
      chain (cursor6.frame.afterFormed formed)
    change RunsExpr extractedProgram separated (siblingCall matching.tree.value matching.index (matching.index + 1))
      (.signed .i32 (if matching.arms.length = 0 then -1 else matching.tree.ends (matching.index + 1))) armReady at navigate
    simp only [if_neg (by omega : matching.arms.length ≠ 0), siblingCall] at navigate
    rw [← representation] at navigate
    have view6 : separated.local? (source.bindingId 0) = some context.value :=
      cursor6.localFound (by decide) baseView (by rfl)
    have index6 : separated.local? (source.argumentId 1) = some (.signed .i32 matching.index) :=
      cursor6.localFound (by decide) baseIndex (by rfl)
    have navigation : RunsExpr extractedProgram separated (right 6)
        (.signed .i32 (matching.tree.ends (matching.index + 1))) armReady :=
      RunsExpr.callArguments (values := [context.tree, .signed .i32 matching.index,
        .signed .i32 (matching.index + 1 : Nat)]) (by core_arguments) navigate
    obtain ⟨advanced, advanceRun, cursor7, armParent, _⟩ := cursor6.assignControl formed
      (control := childId) (controlCell := childReady.nextCell)
      (by rw [cursor6.slotsEq childCursor]; exact childSlot) child6
      (Nat.le_of_lt cursorChild) (Nat.ne_of_gt cursorChild) navigation navigatePure
    have parentOrdinal := (cursor7.frame.afterFormed formed).localCellBound
      (show advanced.cellId? childId = some childReady.nextCell from by rw [cursor7.slotsEq childCursor]; exact childSlot) armParent
    let ordinalBound := advanced.bindLocal ordinalId (.signed .i32 0)
    let cursor8 := cursor7.bindLocal formed ordinalId (.signed .i32 0) (by decide)
    let loopInput : MatchArmProof.Input base region := {
      reference := reference, context := start, inputMemory := retained, tree := matching.tree,
      representation := representation, matchIndex := matching.index, result := matching.result,
      typeId := matching.typeId, armCount := matching.arms.length, cursorCell := base.nextCell,
      parentCell := childReady.nextCell, ordinalCell := advanced.nextCell, ordered := ⟨cursorChild, parentOrdinal⟩,
      view := by core_local, events := by core_local, header := by core_local,
      views := by core_local, index := by core_local, environment := env }
    let loopFront : List UInt8 := front3 ++ matching.scrutinee ++
      (if !matching.atomic then [41] else []) ++ World.utf8Bytes " with\n"
    have initial : MatchArmProof.LoopState loopInput ordinalBound loopFront
        (matching.tree.ends (matching.index + 1)) 0 := by
      refine ⟨?_, ?_, ?_⟩
      · change WriterCursor base ordinalBound cursorId base.nextCell
          (context.address + context.position) context.position loopFront
          [(ordinalId, advanced.nextCell), (childId, childReady.nextCell)]
        simpa only [loopFront, front3, List.nil_append] using cursor8
      · exact State.bindLocal_local?_of_ne advanced (cursor7.frame.afterFormed formed)
          childId ordinalId _ _ (by decide) armParent
      · exact State.bindLocal_local? advanced (cursor7.frame.afterFormed formed) ordinalId _
    obtain ⟨armsDone, armsRun, final⟩ := actualArmsStep loopInput matching.arms initial
      (by change MatchArmsProof.Represents matching.tree context.metadata matching.typeId matching.arms
            (matching.tree.ends (matching.index + 1))
          rw [names]; exact matching.armsRep)
      (by change BodyWriters matching.tree context.metadata matching.arms (matching.tree.ends (matching.index + 1))
          rw [names]; exact armWriters)
      (Or.inr afterScrutinee) (fun _ => afterOrder) (Nat.zero_add _) matching.fits
      (by change context.position + (loopFront ++ MatchArmsProof.output matching.arms).length ≤ context.capacity
          simp only [loopFront, front3, optionalNot, List.length_append,
            List.length_nil, matchLength, withLength] at measured ⊢; omega)
    let armCursor := final.cursor
    have enclosedFinal := armCursor.localFound (by decide) baseEnclosed (by rfl)
    have viewFinal := armCursor.localFound (by decide) baseView (by rfl)
    obtain ⟨closed, closingRun, finalCursor, _⟩ := armCursor.branchArguments
      (conditionExpr := .local (source.argumentId 3)) formed enclosed
      ⟨armsDone, .ofStable (StableExpr.local enclosedFinal) rfl,
        PureFrame.refl (armCursor.frame.afterFormed formed)⟩
      (values := [.rawSlice (.scalar (.signed .i32)) context.address context.words,
        .signed .i32 context.capacity,
        .signed .i32 (context.position + (loopFront ++ MatchArmsProof.output matching.arms).length : Nat),
        .signed .i32 41])
      (suffix := [41]) (expressions := arguments 19)
      (fun yes ready pure => OutputWriterProof.byteAt start.toBuffer (armCursor.afterPure pure).frame ⟨41, by decide⟩
        (by change context.position + ((loopFront ++ MatchArmsProof.output matching.arms) ++ [41]).length ≤ context.capacity
            simpa only [output, bytes, loopFront, front3, optionalNot, yes, ↓reduceIte,
              List.append_assoc] using room) env)
      (fun ready pure => by
        let liveCursor := armCursor.afterPure pure
        core_facts 1 [liveCursor]
        core_arguments)
    have finalValue := finalCursor.value
    change closed.local? cursorId = _ at finalValue
    simp only [loopInput, start, Context.reheap, loopFront, front3, optionalNot,
      List.nil_append, List.append_assoc] at finalValue
    have returned : RunsStmt extractedProgram closed (.returnValue (some (.local cursorId)))
        (.returned (some (.signed .i32 (context.position + (output matching enclosed).length : Nat)))) closed := by
      simpa only [output, bytes, List.append_assoc] using
        RunsStmt.returnValue (program := extractedProgram) (RunsExpr.ofStable (StableExpr.local finalValue) rfl)
    have body : RunsStmt extractedProgram bound
        (match afterHeader with | .letLocal _ _ _ body => body | _ => .skip)
        (.returned (some (.signed .i32 (context.position + (output matching enclosed).length : Nat))))
        (restoreLocals childReady (restoreLocals advanced closed)) :=
      RunsStmt.sequenceNext openingRun (RunsStmt.sequenceNext (.expression prefixRun)
        (RunsStmt.letLocal firstRun (RunsStmt.sequenceNext scrutineeOpening
          (RunsStmt.sequenceNext (.expression scrutineeRun) (RunsStmt.sequenceNext scrutineeClosing
            (RunsStmt.sequenceNext (.expression separatorRun) (RunsStmt.sequenceNext (.expression advanceRun)
              (RunsStmt.letLocal (RunsExpr.ofStable StableExpr.value rfl)
                (RunsStmt.sequenceNext armsRun (RunsStmt.sequenceNext closingRun returned))))))))))
    refine ⟨restoreLocals base closed, ?_, ?_⟩
    · exact RunsStmt.letLocal (afterBody := restoreLocals childReady (restoreLocals advanced closed))
        (RunsExpr.ofStable (StableExpr.local basePosition) rfl) body
    · change WriterFrame base (restoreLocals base closed) (context.address + context.position) (output matching enclosed)
      simpa only [loopInput, start, Context.reheap, output, bytes, loopFront, front3, optionalNot,
        List.nil_append, List.append_assoc] using finalCursor.frame.restoreLocals base

#print axioms actualClassifier
#print axioms matchLayout
#print axioms actualCallStep

private def route (result : IRTypeRefProof.Reference) (typeId count : Nat) :
    SurfaceFallbackProof.Route (IRShapeProof.matchEvent result typeId count) := {
  target := source.id, literalArguments := [.boolean true],
  bindings := [(SurfaceFallbackProof.binding 9, IRShapeProof.matchHeaderValue result typeId count)],
  nonAtom := by rfl, binary := by rfl, intrinsic := by rfl, selected := by rfl,
  noShadow := by
    intro binding member i bound
    simp only [List.mem_singleton] at member
    subst binding
    change SurfaceFallbackProof.binding 9 ≠ expression.argumentId i
    have choices : i = 0 ∨ i = 1 ∨ i = 2 := by omega
    rcases choices with rfl | rfl | rfl <;> decide }

/-- Reuse the match step through the normal expression entry. Its fourth,
    literal argument requests outer parentheses. -/
theorem actualExpressionStep (matching : Match reference region) (context : Context state)
    (classify : Classifier matching.tree (matching.index + 1) matching.atomic)
    (scrutineeWriter : Writer Context.expressionCall reference matching.tree.value
      (matching.index + 1) matching.scrutinee (.fixed matching.metadata))
    (armWriters : BodyWriters matching.tree matching.metadata matching.arms (matching.tree.ends (matching.index + 1)))
    (input : Protected context reference) (representation : context.tree = matching.tree.value)
    (names : context.metadata = matching.metadata)
    (room : context.position + (output matching true).length ≤ context.capacity)
    (environment : WriterEnvironment state) :
    ∃ after, RunsExpr extractedProgram state (context.expressionCall matching.index)
      (.signed .i32 (context.position + (output matching true).length : Nat)) after ∧
      WriterFrame state after (context.address + context.position) (output matching true) := by
  have helper : Writer (SurfaceFallbackProof.entry source.id [.boolean true]) reference matching.tree.value
      matching.index (output matching true) (.fixed matching.metadata) := by
    intro current c native represented metadata space env
    exact actualCallStep matching c classify scrutineeWriter armWriters native represented metadata true space env
  exact SurfaceFallbackProof.actualDispatch (route matching.result matching.typeId matching.arms.length)
    context input matching.tree representation matching.inside matching.event helper names room environment

#print axioms actualExpressionStep

end SurfaceMatchProof
