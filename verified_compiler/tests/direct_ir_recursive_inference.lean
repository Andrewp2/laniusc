import verified_compiler.tests.direct_ir_source_cache
import verified_compiler.tests.direct_ir_binary_inference

namespace IRRecursiveInferenceProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRTypeRefProof IRExpressionKindProof IRTypeCacheProof IRTypeCacheStoreProof IRTypeCacheInvariantProof
open IRUnaryInferenceProof IRSourceCacheProof
open IRTypeCacheFillProof (Literal Environment nodeType)

variable {source : Source}

private def operation : Surface.UnaryOp → Operation
  | .positive => .positive | .negative => .negate | .logicalNot => .not

/-- Independent scalar type/depth specification over the existing source AST.
    Literal category is classified here; spelling and decoding remain lowering's job. -/
def classify : Surface.Expr → Option (Reference × Nat)
  | .literal (.integer _) => some (.I32, 1)
  | .literal (.boolean _) => some (.Bool, 1)
  | .literal (.string _) => some (.String, 1)
  | .unary op child => do
      let (kind, needed) ← classify child
      let op := operation op
      if accepts op kind then some (op.kind, needed + 1) else none
  | .binary op left right => do
      let (leftKind, leftDepth) ← classify left
      let (rightKind, rightDepth) ← classify right
      let kind ← IRBinaryKindProof.scalarResult op leftKind rightKind
      some (kind, max leftDepth rightDepth + 1)
  | _ => none

private theorem classifyLiteral (literal : Literal) (text : String) :
    classify (.literal (surfaceLiteral literal text)) = some (literal.kind, 1) := by
  cases literal <;> rfl

private theorem classifyUnary (op : Operation)
    (model : classify (.unary (surfaceOperation op) child) = some (kind, needed)) :
    ∃ childKind childDepth, classify child = some (childKind, childDepth) ∧
      accepts op childKind = true ∧ kind = op.kind ∧ needed = childDepth + 1 := by
  have inverse : operation (surfaceOperation op) = op := by cases op <;> rfl
  simp only [classify, inverse] at model
  cases found : classify child with
  | none => simp only [found, Bind.bind, Option.bind] at model; contradiction
  | some pair =>
    obtain ⟨childKind, childDepth⟩ := pair
    by_cases accepted : accepts op childKind = true
    · simp only [found, Bind.bind, Option.bind, accepted, ↓reduceIte, Option.some.injEq, Prod.mk.injEq] at model
      exact ⟨childKind, childDepth, rfl, accepted, model.1.symm, model.2.symm⟩
    · simp only [found, Bind.bind, Option.bind, accepted] at model; contradiction

private theorem classifyBinary
    (model : classify (.binary op left right) = some (kind, needed)) :
    ∃ leftKind rightKind leftDepth rightDepth, classify left = some (leftKind, leftDepth) ∧
      classify right = some (rightKind, rightDepth) ∧
      IRBinaryKindProof.scalarResult op leftKind rightKind = some kind ∧
      needed = max leftDepth rightDepth + 1 := by
  simp only [classify] at model
  cases leftFound : classify left with
  | none => simp only [leftFound, Bind.bind, Option.bind] at model; contradiction
  | some leftPair =>
    obtain ⟨leftKind, leftDepth⟩ := leftPair
    cases rightFound : classify right with
    | none => simp only [leftFound, rightFound, Bind.bind, Option.bind] at model; contradiction
    | some rightPair =>
      obtain ⟨rightKind, rightDepth⟩ := rightPair
      cases resultFound : IRBinaryKindProof.scalarResult op leftKind rightKind with
      | none =>
        simp only [leftFound, rightFound, resultFound, Bind.bind, Option.bind] at model
        contradiction
      | some output =>
        simp only [leftFound, rightFound, resultFound, Bind.bind, Option.bind,
          Option.some.injEq, Prod.mk.injEq] at model
        obtain ⟨rfl, rfl⟩ := model
        exact ⟨leftKind, rightKind, leftDepth, rightDepth, rfl, rfl, resultFound, rfl⟩

/-- Native/source agreement for the literal/unary/scalar-binary subset. This carries bytes,
    syntax and bounds, never a successful compiler run or inferred type. -/
inductive Native (source : Source) (layout : Query) (nodes : Nat) (heap : Heap) : Nat → Prop where
  | literal (literal : Literal) (text : String) (fields : Fin 4 → Value)
      (inside : node < layout.count)
      (shape : source.expressions node = .literal (surfaceLiteral literal text))
      (read : readRawSliceIndex extractedProgram { heap := heap } nodeType nodes layout.capacity node =
        .ok (literal.value fields)) : Native source layout nodes heap node
  | unary (op : Operation) (unused : Fin 3 → Value) (inside : node < layout.count)
      (shape : source.expressions node = .unary (surfaceOperation op) (source.expressions child))
      (read : readRawSliceIndex extractedProgram { heap := heap } nodeType nodes layout.capacity node =
        .ok (nodeValue op child unused))
      (operand : Native source layout nodes heap child) : Native source layout nodes heap node
  | binary (op : Surface.BinaryOp) (unused : Fin 2 → Value) (inside : node < layout.count)
      (shape : source.expressions node = .binary op (source.expressions left) (source.expressions right))
      (read : readRawSliceIndex extractedProgram { heap := heap } nodeType nodes layout.capacity node =
        .ok (IRBinaryInferenceProof.nodeValue op left right unused))
      (leftNative : Native source layout nodes heap left)
      (rightNative : Native source layout nodes heap right) : Native source layout nodes heap node

theorem Native.inside (native : Native source layout nodes heap node) : node < layout.count := by
  cases native <;> assumption

theorem Native.reheap (native : Native source layout nodes before node) (reads : HeapReads before after) :
    Native source layout nodes after node := by
  induction native with
  | literal literal text fields inside shape read =>
    exact .literal literal text fields inside shape (reads.rawSlice read)
  | unary op unused inside shape read operand ih =>
    exact .unary op unused inside shape (reads.rawSlice read) ih
  | binary op unused inside shape read left right leftIH rightIH =>
    exact .binary op unused inside shape (reads.rawSlice read) leftIH rightIH

private theorem Native.classified (native : Native source layout nodes heap node)
    (model : classify (source.expressions node) = some (kind, needed)) :
    0 < needed ∧ isValidResult kind = true ∧ ∀ depth, source.Meaning node kind depth := by
  induction native generalizing kind needed with
  | literal literal text fields inside shape read =>
    rw [shape, classifyLiteral] at model
    obtain ⟨rfl, rfl⟩ := Prod.mk.inj (Option.some.inj model)
    exact ⟨by decide, by cases literal <;> rfl, fun _ => source.literal literal text shape⟩
  | unary op unused inside shape read operand ih =>
    rw [shape] at model
    obtain ⟨childKind, childDepth, childModel, accepted, rfl, rfl⟩ := classifyUnary op model
    obtain ⟨positive, _, childMeaning⟩ := ih childModel
    exact ⟨by omega, by cases op <;> rfl, fun _ => source.unary op accepted shape (childMeaning 0)⟩
  | binary op unused inside shape read left right leftIH rightIH =>
    rw [shape] at model
    obtain ⟨leftKind, rightKind, leftDepth, rightDepth, leftModel, rightModel, accepted, rfl⟩ := classifyBinary model
    obtain ⟨leftPositive, _, leftMeaning⟩ := leftIH leftModel
    obtain ⟨rightPositive, _, rightMeaning⟩ := rightIH rightModel
    exact ⟨by omega, (IRBinaryKindProof.scalarValid accepted).2.2,
      fun _ => source.binaryScalar op accepted shape (leftMeaning 0) (rightMeaning 0)⟩

private theorem naturalDepth (depth : Nat) (fits : depth < 2 ^ 31) : (Int32.ofNat depth).toInt = depth := by
  rw [Int32.toInt_ofNat']
  change (depth : Int).bmod 4294967296 = depth
  apply Int.bmod_eq_of_le <;> omega

private def queryAt (layout : Query) (node : Nat) (inside : node < layout.count)
    (depth : Nat) (positive : 0 < depth) (fits : depth < 2 ^ 31) : Query :=
  { layout with
    node := node
    inside := inside
    depth := Int32.ofNat depth
    positive := by rw [naturalDepth depth fits]; omega }

def call (layout : Query) (nodes : Nat) (env : Environment) (node depth : Nat) : Expr :=
  .call Extracted.«lowering::body_expression».Functions.«expression_kind».core.id
    ([layout.context env.header (.rawSlice nodeType nodes layout.capacity) env.countCell env.suffix,
      .signed .i32 layout.count, .signed .i32 node, .signed .i32 depth].map Expr.value)

/-- Retain the exact inferred handle as well as its source classification.
    This is proof state, not another runtime or emitted typing tree. -/
structure Fact (source : Source) (node : Nat) (kind : Reference) (depth : Int) : Prop where
  inferred : ∃ needed, classify (source.expressions node) = some (kind, needed)
  meaning : source.Meaning node kind depth

theorem Fact.kindEq (fact : Fact source node cached budget)
    (model : classify (source.expressions node) = some (kind, needed)) : cached = kind := by
  obtain ⟨oldDepth, oldModel⟩ := fact.inferred
  exact (Prod.mk.inj (Option.some.inj (oldModel.symm.trans model))).1

/-- A sound cache may be empty, partly populated, or fully reusable. -/
structure Cache (source : Source) (layout : Query) (before : State) where
  table : Table layout before
  sound : table.Sound (Fact source)
  formed : before.CellsWellFormed
  unique : HeapBlockBasesUnique before.heap
  noViews : before.i32ArrayViews = []

def Cache.reheap (cache : Cache source layout before) (same : after.heap = before.heap)
    (formed : after.CellsWellFormed) (noViews : after.i32ArrayViews = []) : Cache source layout after := {
  table := cache.table.reheap same, sound := cache.sound, formed := formed
  unique := by rw [same]; exact cache.unique
  noViews := noViews }

theorem Cache.writable (cache : Cache source layout before) (query : Query)
    (same : query.storageKey = layout.storageKey) : Writable query before.heap := by
  let table := cache.table.retarget query same
  have inside := query.inside
  exact ⟨table.codeRoom.subrange (start := query.node * 4) (length := 4) (by omega),
    table.depthRoom.subrange (start := query.node * 4) (length := 4) (by omega), cache.unique⟩

theorem Cache.after {after : State} (cache : Cache source layout before)
    (effect : MemoryEffect (Updates layout (Fact source)) before after) : Nonempty (Cache source layout after) := by
  obtain ⟨table, sound⟩ := effect.2.2.2.preserves cache.table cache.sound
  exact ⟨{
    table := table, sound := sound, formed := effect.1.after_cellsWellFormed cache.formed
    unique := (effect.2.2.2.writable (cache.writable layout rfl)).unique
    noViews := effect.2.2.1.trans cache.noViews }⟩

/-- The real clearing call establishes the recursive theorem's precondition
    while retaining the separated source bytes. Old cache meanings are unused. -/
theorem prepare (table : Table layout before)
    (sourceBytes : ReadOnlyMemory reference before.heap layout.codes (layout.count * 4))
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::body_expression».Functions.«clear_expression_kinds».core.id
        [.value (.rawSlice (.scalar (.signed .i32)) layout.codes layout.capacity), .value (.signed .i32 layout.count)])
      .unit after ∧ MemoryEffect (fun first last => HeapRegionWrite first last layout.codes (layout.count * 4)) before after ∧
      Nonempty (Cache source layout after) ∧ HeapReads reference after.heap := by
  obtain ⟨after, run, effect, empty, sound, _⟩ := actualResetSound (meaning := Fact source)
    table formed unique noViews
  refine ⟨after, run, effect, ⟨{
    table := empty, sound := sound
    formed := by core_formed
    unique := effect.2.2.2.unique
    noViews := effect.2.2.1.trans noViews }⟩, ?_⟩
  intro pointer offset byte read
  rw [effect.2.2.2.outside _ _ (sourceBytes.outside _ _ _ read)]
  exact sourceBytes.reads _ _ _ read

/-- Structural recursion closes every child call for the supported source
    tree. Depth is a sufficient input budget, not an assumed successful run. -/
theorem actual (native : Native source layout nodes heap node) :
    ∀ {before : State}, Cache source layout before →
      ReadOnlyMemory heap before.heap layout.codes (layout.count * 4) →
      ReadOnlyMemory heap before.heap layout.depths (layout.count * 4) →
      ∀ {kind needed}, classify (source.expressions node) = some (kind, needed) →
        ∀ depth, needed ≤ depth → depth < 2 ^ 31 → ∀ env : Environment,
          ∃ after, RunsExpr extractedProgram before (call layout nodes env node depth) (known kind) after ∧
            MemoryEffect (Updates layout (Fact source)) before after ∧ source.Meaning node kind depth ∧
            Nonempty (Cache source layout after) := by
  induction native with
  | literal literal text fields inside shape read =>
    intro before ready codes depths kind needed model depth enough fits env
    rw [shape, classifyLiteral] at model
    obtain ⟨rfl, rfl⟩ := Prod.mk.inj (Option.some.inj model)
    let query := queryAt layout _ inside depth (by omega) fits
    have rootModel : classify (source.expressions query.node) = some (literal.kind, 1) := by
      dsimp only [query, queryAt]; rw [shape, classifyLiteral]
    have fact : Fact source query.node literal.kind query.depth.toInt :=
      ⟨⟨1, rootModel⟩, source.literal literal text shape⟩
    have infer : EffectfulInference query env.header (.rawSlice nodeType nodes layout.capacity) env.countCell env.suffix
        literal.kind before.heap (Updates layout (Fact source)) := by
      intro state currentHeap formed views
      obtain ⟨after, run, frame⟩ := IRTypeCacheFillProof.actualLiteral {
        toQuery := query, literal := literal, nodes := nodes, fields := fields, env := env
        nodeRead := by
          have readable := codes.reads.rawSlice read
          simpa only [query, queryAt, readRawSliceIndex, currentHeap] using readable } formed
      exact ⟨after, run, ⟨frame.cells, frame.world, frame.views, by rw [frame.heap]; exact .refl⟩,
        by rw [frame.heap, currentHeap]; exact ready.writable query rfl⟩
    obtain ⟨after, run, effect⟩ := actualQueryWith query ready.table rfl ready.sound literal.kind
      (by cases literal <;> rfl) fact (fun _ _ cached => cached.kindEq rootModel) env.header
      (.rawSlice nodeType nodes layout.capacity) env.countCell env.suffix infer ready.formed ready.noViews
    refine ⟨after, ?_, effect, source.literal literal text shape, ready.after effect⟩
    simp only [query, queryAt, Query.call, Query.context, naturalDepth depth fits] at run
    exact run
  | unary op unused inside shape read operand ih =>
    intro before ready codes depths kind needed model depth enough fits env
    have rootModel := model
    rw [shape] at model
    obtain ⟨childKind, childDepth, childModel, accepted, rfl, rfl⟩ := classifyUnary op model
    obtain ⟨childPositive, _, childMeaning⟩ := operand.classified childModel
    have positive : 0 < depth - 1 := by omega
    have childFits : depth - 1 < 2 ^ 31 := by omega
    let childQuery := queryAt layout _ operand.inside (depth - 1) positive childFits
    let query := queryAt layout _ inside depth (by omega) fits
    have fact : Fact source query.node op.kind query.depth.toInt :=
      ⟨⟨childDepth + 1, rootModel⟩, source.unary op accepted shape (childMeaning 0)⟩
    let input : IRUnaryInferenceProof.Input before := {
      child := childQuery, root := _, inside := inside, depth := Int32.ofNat depth
      predecessor := by dsimp only [childQuery, queryAt]; rw [naturalDepth depth fits, naturalDepth _ childFits]; omega
      nodes := nodes, env := env, op := op, unused := unused
      nodeRead := by
        have readable := codes.reads.rawSlice read
        simpa only [childQuery, queryAt] using readable }
    have infer : EffectfulInference query env.header (.rawSlice nodeType nodes layout.capacity)
        env.countCell env.suffix op.kind before.heap (Updates layout (Fact source)) := by
      intro state currentHeap formed views
      obtain ⟨after, run, effect⟩ := actualWith (input.reheap currentHeap) childKind
        (relation := Updates layout (Fact source)) (fun childHeap childFormed childViews => by
          obtain ⟨after, run, effect, _⟩ := ih
            (ready.reheap (childHeap.trans currentHeap) childFormed (childViews.trans views))
            ⟨by rw [childHeap, currentHeap]; exact codes.reads, codes.outside⟩
            ⟨by rw [childHeap, currentHeap]; exact depths.reads, depths.outside⟩
            childModel (depth - 1) (by omega) childFits env
          refine ⟨after, ?_, effect⟩
          simp only [call] at run
          simp only [input, Input.reheap, childQuery, queryAt, Query.call, Query.context,
            naturalDepth _ childFits]
          exact run) formed
      simp only [input, Input.reheap, outcome, accepted, ↓reduceIte] at run
      exact ⟨after, run, effect, effect.2.2.2.writable (by
        rw [currentHeap]; exact ready.writable query rfl)⟩
    obtain ⟨after, run, effect⟩ := actualQueryWith query ready.table rfl ready.sound op.kind
      (by cases op <;> rfl) fact (fun _ _ cached => cached.kindEq rootModel) env.header
      (.rawSlice nodeType nodes layout.capacity) env.countCell env.suffix infer ready.formed ready.noViews
    refine ⟨after, ?_, effect, source.unary op accepted shape (childMeaning 0), ready.after effect⟩
    simp only [query, queryAt, Query.call, Query.context, naturalDepth depth fits] at run
    exact run
  | binary op unused inside shape read leftNative rightNative leftIH rightIH =>
    intro before ready codes depths kind needed model depth enough fits env
    have rootModel := model
    rw [shape] at model
    obtain ⟨leftKind, rightKind, leftDepth, rightDepth, leftModel, rightModel, accepted, rfl⟩ := classifyBinary model
    obtain ⟨leftPositive, _, leftMeaning⟩ := leftNative.classified leftModel
    obtain ⟨rightPositive, _, rightMeaning⟩ := rightNative.classified rightModel
    have positive : 0 < depth - 1 := by omega
    have childFits : depth - 1 < 2 ^ 31 := by omega
    let leftQuery := queryAt layout _ leftNative.inside (depth - 1) positive childFits
    let query := queryAt layout _ inside depth (by omega) fits
    have fact : Fact source query.node kind query.depth.toInt :=
      ⟨⟨max leftDepth rightDepth + 1, rootModel⟩,
        source.binaryScalar op accepted shape (leftMeaning 0) (rightMeaning 0)⟩
    let input : IRBinaryInferenceProof.Input before := {
      left := leftQuery, right := _, rightInside := rightNative.inside, root := _, inside := inside
      depth := Int32.ofNat depth
      predecessor := by dsimp only [leftQuery, queryAt]; rw [naturalDepth depth fits, naturalDepth _ childFits]; omega
      nodes := nodes, env := env, op := op, unused := unused
      nodeRead := by
        have readable := codes.reads.rawSlice read
        simpa only [leftQuery, queryAt] using readable }
    have infer : EffectfulInference query env.header (.rawSlice nodeType nodes layout.capacity)
        env.countCell env.suffix kind before.heap (Updates layout (Fact source)) := by
      intro state currentHeap formed views
      obtain ⟨after, run, effect⟩ := IRBinaryInferenceProof.actualWith (input.reheap currentHeap) leftKind rightKind
        (IRBinaryKindProof.scalarValid accepted).1 (IRBinaryKindProof.scalarValid accepted).2.1
        (relation := Updates layout (Fact source)) Updates.trans
        (fun childHeap childFormed childViews => by
          obtain ⟨after, run, effect, _⟩ := leftIH
            (ready.reheap (childHeap.trans currentHeap) childFormed (childViews.trans views))
            ⟨by rw [childHeap, currentHeap]; exact codes.reads, codes.outside⟩
            ⟨by rw [childHeap, currentHeap]; exact depths.reads, depths.outside⟩
            leftModel (depth - 1) (by omega) childFits env
          refine ⟨after, ?_, effect⟩
          simp only [call, input, IRBinaryInferenceProof.Input.reheap, leftQuery, queryAt,
            Query.call, Query.context, naturalDepth _ childFits] at run ⊢
          exact run)
        (fun {current : State} updates childFormed childViews => by
          let entryCache := ready.reheap currentHeap formed views
          have reads := updates.reads
            ⟨by rw [currentHeap]; exact codes.reads, codes.outside⟩
            ⟨by rw [currentHeap]; exact depths.reads, depths.outside⟩
          obtain ⟨table, sound⟩ := updates.preserves entryCache.table entryCache.sound
          let childCache : Cache source layout current := {
            table := table, sound := sound, formed := childFormed
            unique := (updates.writable (entryCache.writable layout rfl)).unique
            noViews := childViews.trans entryCache.noViews }
          obtain ⟨after, run, effect, _⟩ := rightIH childCache ⟨reads, codes.outside⟩ ⟨reads, depths.outside⟩
            rightModel (depth - 1) (by omega) childFits env
          refine ⟨after, ?_, effect⟩
          simp only [call, input, IRBinaryInferenceProof.Input.reheap,
            IRBinaryInferenceProof.Input.rightQuery, leftQuery, queryAt, Query.call, Query.context,
            naturalDepth _ childFits] at run ⊢
          exact run)
        (fun h => by
          have decision := IRBinaryKindProof.actualScalar (input.reheap currentHeap).site accepted h
          simp only [input, IRBinaryInferenceProof.Input.reheap] at decision ⊢
          exact decision)
        formed
      exact ⟨after, run, effect, effect.2.2.2.writable (by
        rw [currentHeap]; exact ready.writable query rfl)⟩
    obtain ⟨after, run, effect⟩ := actualQueryWith query ready.table rfl ready.sound
      kind (IRBinaryKindProof.scalarValid accepted).2.2 fact
      (fun _ _ cached => cached.kindEq rootModel) env.header
      (.rawSlice nodeType nodes layout.capacity) env.countCell env.suffix infer ready.formed ready.noViews
    refine ⟨after, ?_, effect,
      source.binaryScalar op accepted shape (leftMeaning 0) (rightMeaning 0), ready.after effect⟩
    simp only [query, queryAt, Query.call, Query.context, naturalDepth depth fits] at run
    exact run

#print axioms actual

/-- The closed traversal also preserves its source/native correspondence.
    Source/cache separation is a memory precondition, not assumed execution. -/
theorem actualFramed (native : Native source layout nodes reference node) (ready : Cache source layout before)
    (codes : ReadOnlyMemory reference before.heap layout.codes (layout.count * 4))
    (depths : ReadOnlyMemory reference before.heap layout.depths (layout.count * 4))
    (model : classify (source.expressions node) = some (kind, needed))
    (enough : needed ≤ depth) (fits : depth < 2 ^ 31) (env : Environment) :
    ∃ after, RunsExpr extractedProgram before (call layout nodes env node depth) (known kind) after ∧
      MemoryEffect (Updates layout (Fact source)) before after ∧ source.Meaning node kind depth ∧
      Native source layout nodes after.heap node ∧
      Nonempty (Cache source layout after) := by
  obtain ⟨after, run, effect, meaning, table⟩ := actual native ready codes depths model depth enough fits env
  exact ⟨after, run, effect, meaning, native.reheap (effect.2.2.2.reads codes depths), table⟩

#print axioms actualFramed
#print axioms prepare

end IRRecursiveInferenceProof
