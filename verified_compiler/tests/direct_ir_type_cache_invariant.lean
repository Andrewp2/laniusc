import verified_compiler.tests.direct_ir_type_cache_store
import verified_compiler.tests.direct_ir_type_cache_reset
import Lanius.Semantics.ReadOnlyMemory

namespace IRTypeCacheInvariantProof

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics
open IRTypeRefProof IRExpressionKindProof IRTypeCacheProof IRTypeCacheStoreProof

variable {before after : State}

private def code : Option Reference → Int
  | none => -1
  | some kind => typeCode kind

/-- One arena's native cache, including empty entries. The two full tables
    must be disjoint, not merely the two words at the current query. -/
structure Table (query : Query) (state : State) where
  kinds : Nat → Option Reference
  budgets : Nat → Int32
  codeRead : ∀ index, index < query.count →
    readRawSliceIndex extractedProgram state (.scalar (.signed .i32)) query.codes query.capacity index =
      .ok (.signed .i32 (code (kinds index)))
  depthRead : ∀ index, index < query.count →
    readRawSliceIndex extractedProgram state (.scalar (.signed .i32)) query.depths query.capacity index =
      .ok (.signed .i32 (budgets index).toInt)
  supported : ∀ index, index < query.count → ∀ kind, kinds index = some kind → isValidResult kind = true
  codeRoom : state.heap.Readable query.codes (query.count * 4)
  depthRoom : state.heap.Readable query.depths (query.count * 4)
  separate : query.codes + query.count * 4 ≤ query.depths ∨ query.depths + query.count * 4 ≤ query.codes

/-- Semantic evidence belongs to the source node and scope, not to its numeric
    encoding. Clients supply their source typing relation here. This predicate
    does not mention successful execution of the compiler. -/
def Table.Sound (table : Table query state) (meaning : Nat → Reference → Int → Prop) : Prop :=
  ∀ index, index < query.count → ∀ kind, table.kinds index = some kind →
    meaning index kind (table.budgets index).toInt

def Table.retarget (table : Table query state) (target : Query)
    (same : target.storageKey = query.storageKey) : Table target state := by
  have codes : target.codes = query.codes := congrArg Prod.fst same
  have depths : target.depths = query.depths := congrArg (fun key => key.2.1) same
  have count : target.count = query.count := congrArg (fun key => key.2.2.1) same
  have capacity : target.capacity = query.capacity := congrArg (fun key => key.2.2.2) same
  exact { table with
    codeRead := by simpa only [codes, count, capacity] using table.codeRead
    depthRead := by simpa only [depths, count, capacity] using table.depthRead
    supported := by simpa only [count] using table.supported
    codeRoom := by simpa only [codes, count] using table.codeRoom
    depthRoom := by simpa only [depths, count] using table.depthRoom
    separate := by simpa only [codes, depths, count] using table.separate }

theorem Table.retargetSound (table : Table query state) {target : Query} (same : target.storageKey = query.storageKey)
    (sound : table.Sound meaning) : (table.retarget target same).Sound meaning := by
  have count : target.count = query.count := congrArg (fun key => key.2.2.1) same
  exact fun index inside kind found => sound index (by simpa only [count] using inside) kind found

def Table.reheap (table : Table query before) (same : after.heap = before.heap) : Table query after := {
  table with
  codeRead := by simpa only [readRawSliceIndex, same] using table.codeRead
  depthRead := by simpa only [readRawSliceIndex, same] using table.depthRead
  codeRoom := by simpa only [same] using table.codeRoom
  depthRoom := by simpa only [same] using table.depthRoom }

/-- An empty cache imposes no typing facts; every subsequent successful entry
    must acquire its evidence from inference. Depth words need not be cleared. -/
theorem Table.emptySound (table : Table query state)
    (empty : ∀ index, index < query.count → table.kinds index = none) : table.Sound meaning := by
  intro index inside kind found
  rw [empty index inside] at found
  contradiction

/-- Actual reset clears the live codes while preserving the independent
    budget table. Previous semantic evidence is deliberately discarded. -/
def Table.reset (table : Table query before)
    (write : HeapRegionWrite before.heap after.heap query.codes (query.count * 4))
    (cleared : ∀ index, index < query.count → readRawSliceIndex extractedProgram after
      (.scalar (.signed .i32)) query.codes query.capacity index = .ok (.signed .i32 (-1))) : Table query after := {
  kinds := fun _ => none
  budgets := table.budgets
  codeRead := cleared
  depthRead := i32Table_afterRegionWrite write query.storage table.depthRoom table.separate.symm table.depthRead
  supported := by intro index inside kind impossible; contradiction
  codeRoom := write.readable _ _ table.codeRoom
  depthRoom := write.readable _ _ table.depthRoom
  separate := table.separate }

/-- Initialization is derived from the real clearing call; stale entries may
    have arbitrary old meanings, or no semantic justification at all. -/
theorem actualResetSound (table : Table query before) (formed : before.CellsWellFormed)
    (unique : HeapBlockBasesUnique before.heap) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before
      (.call Extracted.«lowering::body_expression».Functions.«clear_expression_kinds».core.id
        [.value (.rawSlice (.scalar (.signed .i32)) query.codes query.capacity), .value (.signed .i32 query.count)])
      .unit after ∧ MemoryEffect (fun first last => HeapRegionWrite first last query.codes (query.count * 4)) before after ∧
      ∃ empty : Table query after, empty.Sound meaning ∧ ∀ index, empty.kinds index = none := by
  let input : IRTypeCacheResetProof.Input before := {
    address := query.codes, count := query.count, capacity := query.capacity, inside := query.storage,
    fits := Nat.lt_of_le_of_lt query.storage query.fits, room := table.codeRoom }
  obtain ⟨after, run, effect, cleared⟩ := IRTypeCacheResetProof.actualReset input formed unique noViews
  let empty := table.reset effect.2.2.2 cleared
  exact ⟨after, run, effect, empty, empty.emptySound (by intros; rfl), by intros; rfl⟩

def Table.entry (table : Table query state) (kind : Reference)
    (found : table.kinds query.node = some kind)
    (enough : (table.budgets query.node).toInt ≤ query.depth.toInt) : Entry state := {
  toQuery := query
  storedDepth := table.budgets query.node
  kind := kind
  sufficient := enough
  supported := table.supported query.node query.inside kind found
  codeRead := by simpa only [found, code] using table.codeRead query.node query.inside
  depthRead := table.depthRead query.node query.inside }

/-- Empty and insufficient-depth entries supply real miss preconditions. -/
def Table.missSlot (table : Table query before)
    (missed : table.kinds query.node = none ∨ query.depth.toInt < (table.budgets query.node).toInt) : Slot before := by
  have inside := query.inside
  have apart := table.separate
  exact {
    toQuery := query, oldCode := code (table.kinds query.node), oldDepth := (table.budgets query.node).toInt
    codeRead := table.codeRead query.node inside
    depthRead := table.depthRead query.node inside
    missed := missed.imp (by intro empty; rw [empty]; decide) id
    codeRoom := table.codeRoom.subrange (start := query.node * 4) (length := 4) (by omega)
    depthRoom := table.depthRoom.subrange (start := query.node * 4) (length := 4) (by omega)
    separate := by omega }

/-- Reusing the actual hit also recovers its source-level justification at
    the requested budget. Budget monotonicity is a property of that relation. -/
theorem actualHitSound (table : Table query before) (sound : table.Sound meaning)
    (monotone : ∀ node kind small large, small ≤ large → meaning node kind small → meaning node kind large)
    (kind : Reference) (found : table.kinds query.node = some kind)
    (enough : (table.budgets query.node).toInt ≤ query.depth.toInt)
    (header : Fin 5 → Value) (nodes countCell : Value) (unused : List Value)
    (formed : before.CellsWellFormed) :
    meaning query.node kind query.depth.toInt ∧ ∃ after,
      RunsExpr extractedProgram before (query.call header nodes countCell unused) (known kind) after ∧
      PureFrame before after :=
  ⟨monotone _ _ _ _ enough (sound _ query.inside _ found),
    actualHit (table.entry kind found enough) header nodes countCell unused formed⟩

/-- Both native word tables reflect the one-slot functional update. Every
    neighboring entry survives, even when table addresses are in either order. -/
def Table.store (input : Query) (table : Table input before)
    (kind : Reference) (supported : isValidResult kind = true)
    (write : Stored input kind before.heap after.heap) : Table input after := by
  refine {
    kinds := fun index => if index = input.node then some kind else table.kinds index
    budgets := fun index => if index = input.node then input.depth else table.budgets index
    codeRead := ?_, depthRead := ?_, supported := ?_
    codeRoom := ?_, depthRoom := ?_
    separate := table.separate }
  · obtain ⟨middle, codeWrite, depthWrite⟩ := write
    let intermediate : State := { before with heap := middle }
    have apart := table.separate
    have within := input.inside
    apply i32Table_afterRegionWrite (before := intermediate) (HeapRegionWrite.ofBytes depthWrite)
      input.storage (codeWrite.readable table.codeRoom)
      (by simp only [i32Bytes, List.length_map, List.length_range]; omega)
    intro index inside
    have first := readRawSliceIndex_i32_afterStore (program := extractedProgram)
      (before := before) (after := intermediate) (pointer := input.codes) (capacity := input.capacity)
      (position := index) codeWrite (typeCodeBits kind) (Nat.lt_of_lt_of_le inside input.storage)
      (table.codeRoom.subrange (start := index * 4) (length := 4) (by omega)) (fun _ => table.codeRead index inside)
    by_cases same : index = input.node <;> simpa only [same, ↓reduceIte, code] using first
  · obtain ⟨middle, codeWrite, depthWrite⟩ := write
    let intermediate : State := { before with heap := middle }
    have apart := table.separate
    have within := input.inside
    have first := i32Table_afterRegionWrite (before := before) (after := intermediate)
      (HeapRegionWrite.ofBytes codeWrite) input.storage table.depthRoom
      (by simp only [i32Bytes, List.length_map, List.length_range]; omega) table.depthRead
    have represented : (BitVec.ofInt 32 input.depth.toInt).toInt = input.depth.toInt := by
      change (BitVec.ofInt 32 input.depth.toBitVec.toInt).toInt = _
      rw [BitVec.ofInt_toInt]
      rfl
    intro index inside
    have second := readRawSliceIndex_i32_afterStore (program := extractedProgram)
      (before := intermediate) (after := after) (pointer := input.depths) (capacity := input.capacity)
      (position := index) depthWrite represented (Nat.lt_of_lt_of_le inside input.storage)
      (codeWrite.readable (table.depthRoom.subrange (start := index * 4) (length := 4) (by omega)))
      (fun _ => first index inside)
    simpa only [apply_ite] using second
  · intro index inside value found
    by_cases same : index = input.node
    · simp only [same, ↓reduceIte, Option.some.injEq] at found
      subst value
      exact supported
    · exact table.supported index inside value (by simpa only [same, ↓reduceIte] using found)
  · obtain ⟨middle, codeWrite, depthWrite⟩ := write
    exact depthWrite.readable (codeWrite.readable table.codeRoom)
  · obtain ⟨middle, codeWrite, depthWrite⟩ := write
    exact depthWrite.readable (codeWrite.readable table.depthRoom)

theorem Table.storeSound (input : Query) (table : Table input before)
    (kind : Reference) (supported : isValidResult kind = true)
    (write : Stored input kind before.heap after.heap)
    (sound : table.Sound meaning) (inferred : meaning input.node kind input.depth.toInt) :
    (Table.store input table kind supported write).Sound meaning := by
  intro index inside value found
  by_cases same : index = input.node
  · subst index
    simp only [Table.store, ↓reduceIte, Option.some.injEq] at found ⊢
    subst value
    exact inferred
  · simp only [Table.store, same, ↓reduceIte] at found ⊢
    exact sound index inside value found

/-- A proof of justified native writes, not an emitted log or a second AST.
    Any number of recursive children may contribute updates to one cache. -/
inductive Updates (query : Query) (meaning : Nat → Reference → Int → Prop) : Heap → Heap → Prop where
  | refl : Updates query meaning heap heap
  | store (previous : Updates query meaning first middle)
      (target : Query) (same : target.storageKey = query.storageKey)
      (supported : isValidResult kind = true) (justified : meaning target.node kind target.depth.toInt)
      (write : Stored target kind middle last) : Updates query meaning first last

theorem Updates.trans {before middle after : Heap}
    (first : Updates query meaning before middle) (last : Updates query meaning middle after) :
    Updates query meaning before after := by
  induction last with
  | refl => exact first
  | store previous target same supported justified write ih => exact .store ih target same supported justified write

theorem Updates.writable {before after : Heap} (updates : Updates query meaning before after)
    (ready : Writable parent before) : Writable parent after := by
  induction updates with
  | refl => exact ready
  | store previous target same supported justified write ih => exact write.writable ih

/-- Recursive cache writes retain a source fragment separated from both tables.
    The reference heap is proof-only; no source bytes are copied at runtime. -/
theorem Updates.reads {reference before after : Heap} (updates : Updates query meaning before after)
    (codes : ReadOnlyMemory reference before query.codes (query.count * 4))
    (depths : ReadOnlyMemory reference before query.depths (query.count * 4)) : HeapReads reference after := by
  induction updates with
  | refl => exact codes.reads
  | store previous target same supported justified write ih =>
    obtain ⟨middle, first, last⟩ := write
    have codeBase := congrArg Prod.fst same
    have depthBase := congrArg (fun key => key.2.1) same
    have count := congrArg (fun key => key.2.2.1) same
    have inside := target.inside
    intro pointer offset byte read
    have codeOutside := codes.outside _ _ _ read
    have depthOutside := depths.outside _ _ _ read
    rw [(HeapRegionWrite.ofBytes last).outside _ _ (by
      simp only [i32Bytes, List.length_map, List.length_range]
      dsimp only [Query.storageKey, Address] at *; omega)]
    rw [(HeapRegionWrite.ofBytes first).outside _ _ (by
      simp only [i32Bytes, List.length_map, List.length_range]
      dsimp only [Query.storageKey, Address] at *; omega)]
    exact ih _ _ _ read

/-- Native representation and every source fact survive the entire update
    sequence. Each new fact must be supplied by a proved inference rule. -/
theorem Updates.preserves (updates : Updates query meaning before.heap after.heap)
    (table : Table query before) (sound : table.Sound meaning) :
    ∃ next : Table query after, next.Sound meaning := by
  suffices step : ∀ {first last}, Updates query meaning first last →
      ∀ (table : Table query { before with heap := first }), table.Sound meaning →
        ∃ next : Table query { before with heap := last }, next.Sound meaning by
    obtain ⟨next, valid⟩ := step updates (table.reheap rfl) sound
    exact ⟨next.reheap rfl, valid⟩
  intro first last writes
  induction writes with
  | refl => exact fun table sound => ⟨table, sound⟩
  | store previous target same supported justified write ih =>
    intro table sound
    obtain ⟨middle, valid⟩ := ih table sound
    let selected := middle.retarget target same
    let next := Table.store (after := { before with heap := _ }) target selected _ supported write
    have correct := Table.storeSound (after := { before with heap := _ }) target selected _ supported write
      (middle.retargetSound same valid) justified
    exact ⟨next.retarget query same.symm, next.retargetSound same.symm correct⟩

/-- The real public query preserves every previously justified cache entry
    and installs the inference result. The inference execution and its meaning
    are explicit composition obligations, not hidden in the cache invariant. -/
theorem actualStoreSound (input : Slot before) (table : Table input.toQuery before)
    (sound : table.Sound meaning) (kind : Reference) (supported : isValidResult kind = true)
    (inferred : meaning input.node kind input.depth.toInt)
    (header : Fin 5 → Value) (nodes countCell : Value) (unused : List Value)
    (infer : Inference input.toQuery header nodes countCell unused kind before.heap)
    (formed : before.CellsWellFormed) (unique : HeapBlockBasesUnique before.heap)
    (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (input.toQuery.call header nodes countCell unused) (known kind) after ∧
      MemoryEffect (Stored input.toQuery kind) before after ∧ ∃ next : Table input.toQuery after,
        next.Sound meaning ∧ next.kinds input.node = some kind ∧ next.budgets input.node = input.depth := by
  obtain ⟨after, run, effect⟩ := actualStore input header nodes countCell unused kind supported infer formed unique noViews
  exact ⟨after, run, effect, Table.store input.toQuery table kind supported effect.2.2.2,
    Table.storeSound input.toQuery table kind supported effect.2.2.2 sound inferred,
    by simp only [Table.store, ↓reduceIte], by simp only [Table.store, ↓reduceIte]⟩

/-- One wrapper handles hits, empty slots and insufficient-depth entries.
    The closed caller must establish inference and the exact result type. -/
theorem actualQueryWith (query : Query) (table : Table layout before) (same : query.storageKey = layout.storageKey)
    (sound : table.Sound meaning) (kind : Reference) (supported : isValidResult kind = true)
    (inferred : meaning query.node kind query.depth.toInt)
    (determines : ∀ cached budget, meaning query.node cached budget → cached = kind)
    (header : Fin 5 → Value) (nodes countCell : Value) (unused : List Value)
    (infer : EffectfulInference query header nodes countCell unused kind before.heap (Updates layout meaning))
    (formed : before.CellsWellFormed) (noViews : before.i32ArrayViews = []) :
    ∃ after, RunsExpr extractedProgram before (query.call header nodes countCell unused) (known kind) after ∧
      MemoryEffect (Updates layout meaning) before after := by
  let selected := table.retarget query same
  have miss (missed : selected.kinds query.node = none ∨ query.depth.toInt < (selected.budgets query.node).toInt) :
      ∃ after, RunsExpr extractedProgram before (query.call header nodes countCell unused) (known kind) after ∧
        MemoryEffect (Updates layout meaning) before after := by
    obtain ⟨after, run, effect⟩ := actualStoreWith (selected.missSlot missed) header nodes countCell unused
      kind supported infer formed noViews
    obtain ⟨middle, previous, stored⟩ := effect.2.2.2
    have changes := Updates.store previous query same supported inferred stored
    exact ⟨after, run, effect.1, effect.2.1, effect.2.2.1, changes⟩
  cases found : selected.kinds query.node with
  | none => exact miss (Or.inl found)
  | some cached =>
    by_cases enough : (selected.budgets query.node).toInt ≤ query.depth.toInt
    · have correct := determines cached _ (table.retargetSound same sound _ query.inside _ found)
      subst cached
      obtain ⟨after, run, frame⟩ := actualHit (selected.entry kind found enough) header nodes countCell unused formed
      exact ⟨after, run, frame.cells, frame.world, frame.views, by rw [frame.heap]; exact .refl⟩
    · exact miss (Or.inr (by omega))

#print axioms actualHitSound
#print axioms actualStoreSound
#print axioms actualResetSound
#print axioms Updates.preserves
#print axioms Updates.reads
#print axioms actualQueryWith

end IRTypeCacheInvariantProof
