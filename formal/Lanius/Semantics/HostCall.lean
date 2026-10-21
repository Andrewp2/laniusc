import Lanius.Semantics.CallRun
import Lanius.Semantics.Typing.Native.Mapping
import Lanius.Memory.Footprint

namespace Lanius.Semantics

open Lanius.Core
open Lanius.Typing Lanius.Memory

private theorem hostCallSynchronized
    (found : program.function? functionId = some function)
    (body : function.body = none) (external : function.external = some (.host service))
    (parameters : bindParameters function.parameters values = some bindings)
    (flushed : syncI32ViewsToHeap before = .ok { before with heap := flushedHeap })
    (called : World.call flushedHeap before.world service values = .returned value heap world)
    (refreshed : syncI32ViewsFromHeap { before with heap, world } = .ok after) :
    RunsExpr program before (.call functionId (values.map Expr.value)) value after := by
  obtain ⟨threshold, arguments, _⟩ := RunsExprs.values (program := program) (state := before) values
  apply RunsExpr.ofEval (fuel := threshold + 1)
  rw [evalExpr.eq_def]
  simp only [arguments threshold (Nat.le_refl _), found, body, parameters, external, flushed,
    called, worldCallOutcome, refreshed]

/-- A host call with no registered cell-backed views. The host effect is an
    explicit premise to derive at the caller; this rule handles only the call
    syntax, argument evaluation, and unchanged lexical/cell state. -/
theorem RunsExpr.hostCall
    (found : program.function? functionId = some function)
    (body : function.body = none) (external : function.external = some (.host service))
    (parameters : bindParameters function.parameters values = some bindings)
    (noViews : before.i32ArrayViews = [])
    (called : World.call before.heap before.world service values = .returned value heap world) :
    RunsExpr program before (.call functionId (values.map Expr.value)) value
      { before with heap, world } := by
  have flushed : syncI32ViewsToHeap before = .ok before := by
    simp only [syncI32ViewsToHeap, noViews, syncI32ViewsToHeapFrom]
  apply hostCallSynchronized found body external parameters flushed called
  simp only [syncI32ViewsFromHeap, noViews, syncI32ViewsFromHeapFrom]

/-- Compose a flushed host effect with typed native refresh. The host's actual
    effect and post-storage validity remain explicit; refresh success is derived.
    Clients should obtain the flush from `I32ViewsAccessible.flush`. -/
theorem RunsExpr.hostCallViews
    (found : program.function? functionId = some function)
    (body : function.body = none) (external : function.external = some (.host service))
    (parameters : bindParameters function.parameters values = some bindings)
    (flushed : syncI32ViewsToHeap before = .ok { before with heap := flushedHeap })
    (called : World.call flushedHeap before.world service values = .returned value heap world)
    (access : ({ before with heap, world } : State).I32ViewsAccessible program types) :
    ∃ cells, RunsExpr program before (.call functionId (values.map Expr.value)) value
      { before with cells, heap, world } ∧
      ({ before with cells, heap, world } : State).I32ViewsAccessible program types ∧
      (before.I32ViewsUnique →
        ({ before with cells, heap, world } : State).I32ViewsCoherent program types) := by
  obtain ⟨cells, refreshed, finalAccess, coherent⟩ := access.refresh
  exact ⟨cells, hostCallSynchronized found body external parameters flushed called refreshed, finalAccess, coherent⟩

/-- The extractor's stdout service is total on readable output storage, even
    with live native views. Neither synchronization nor host success is assumed.
    Output is the complete requested heap range, and cells remain typed. -/
theorem RunsExpr.writeStdoutViews
    (found : program.function? functionId = some function)
    (body : function.body = none) (external : function.external = some (.host .writeStdout))
    (parameters : bindParameters function.parameters [.pointer pointer, .unsigned .usize count] = some bindings)
    (access : before.I32ViewsAccessible program types) (readable : before.heap.Readable pointer count) :
    ∃ bytes after, RunsExpr program before
      (.call functionId [.value (.pointer pointer), .value (.unsigned .usize count)]) (World.i32Result count) after ∧
      after.I32ViewsAccessible program types ∧ bytes.length = count ∧
      after.world.standardOutput = before.world.standardOutput ++ bytes := by
  obtain ⟨heap, flushed, readyAccess, retained, _⟩ := access.flush
  obtain ⟨bytes, loaded⟩ := (retained pointer count readable).loadBytes
  have length := (loadBytesFrom_spec loaded).1
  let world := { World.record before.world .writeStdout with standardOutput := before.world.standardOutput ++ bytes }
  have called : World.call heap before.world .writeStdout [.pointer pointer, .unsigned .usize count] =
      .returned (World.i32Result count) heap world := by
    simp only [World.call, World.callSimple, loaded, length]
    rfl
  obtain ⟨cells, run, finalAccess, _⟩ := RunsExpr.hostCallViews found body external parameters flushed called
    (readyAccess.bytesWrite (world := world) (BytesWrite.refl (address := pointer) readyAccess.unique))
  exact ⟨bytes, _, run, finalAccess, length, rfl⟩

/-- Stdout preserves the entire cell/alias state. Flushing establishes byte
    coherence; readonly host execution then makes refresh an exact identity. -/
theorem RunsExpr.writeStdoutFramed
    (found : program.function? functionId = some function)
    (body : function.body = none) (external : function.external = some (.host .writeStdout))
    (parameters : bindParameters function.parameters [.pointer pointer, .unsigned .usize count] = some bindings)
    (access : before.I32ViewsAccessible program types) (readable : before.heap.Readable pointer count)
    (apart : before.i32ArrayViews.Pairwise I32ArrayView.Disjoint) (unique : (before.cells.map Cell.id).Nodup) :
    ∃ bytes heap world, RunsExpr program before
      (.call functionId [.value (.pointer pointer), .value (.unsigned .usize count)]) (World.i32Result count)
      { before with heap, world } ∧ ({ before with heap } : State).I32ViewsCoherent program types ∧
      heap.loadBytes pointer count = .ok bytes ∧ bytes.length = count ∧ world = { World.record before.world .writeStdout with
        standardOutput := before.world.standardOutput ++ bytes } := by
  obtain ⟨heap, flushed, coherent, retained, _⟩ := access.flushCoherent apart
  obtain ⟨bytes, loaded⟩ := (retained pointer count readable).loadBytes
  have length := (loadBytesFrom_spec loaded).1
  let world := { World.record before.world .writeStdout with standardOutput := before.world.standardOutput ++ bytes }
  have called : World.call heap before.world .writeStdout [.pointer pointer, .unsigned .usize count] =
      .returned (World.i32Result count) heap world := by
    simp only [World.call, World.callSimple, loaded, length]; rfl
  have finalCoherent : ({ before with heap, world } : State).I32ViewsCoherent program types :=
    coherent.withWorld
  exact ⟨bytes, heap, world, hostCallSynchronized found body external parameters flushed called
    (finalCoherent.refresh unique), coherent, loaded, length, rfl⟩

/-- Exact observations of the modeled file operation, including invalid
    handles, cursor changes, returned count and the byte-write frame. -/
def FileReadResult (before : Heap) (world : World.State) (handle : Int) (pointer count : Nat)
    (value : Value) (heap : Heap) (after : World.State) : Prop :=
  match World.readFileBytes (World.record world .read) handle count with
  | none => value = World.i32Result (-1) ∧ heap = before ∧ after = World.record world .read
  | some (bytes, next) => value = World.i32Result bytes.length ∧ after = next ∧
      bytes.length ≤ count ∧ BytesWrite before heap pointer bytes

/-- The byte effect occurs after flushing registered views. This is a proved
    postcondition, not an input assumption that a host call succeeded. -/
def ReadEffect (before : State) (handle : Int) (pointer count : Nat) (value : Value) (after : State) : Prop :=
  ∃ heap, syncI32ViewsToHeap before = .ok { before with heap } ∧
    FileReadResult heap before.world handle pointer count value after.heap after.world

/-- Pointer argument effects precede the file operation. The witness retains
    that boundary, so callers never interpret a read against the wrong world. -/
def PointerReadEffect (program : Program) (before : State) (expression : Expr)
    (handle : Int) (count : Nat) (value : Value) (after : State) : Prop :=
  ∃ pointer mapped, RunsExpr program before expression (.pointer pointer) mapped ∧
    ReadEffect mapped handle pointer count value after

theorem FileReadResult.readable (effect : FileReadResult heap world handle pointer count value after next)
    (readable : heap.Readable address length) : after.Readable address length := by
  cases read : World.readFileBytes (World.record world .read) handle count with
  | none =>
    simp only [FileReadResult, read] at effect
    simpa only [effect.2.1] using readable
  | some result =>
    rcases result with ⟨bytes, updated⟩
    simp only [FileReadResult, read] at effect
    exact effect.2.2.2.readable readable

/-- Retain the requested-range frame for either a successful read or an
    invalid handle. The actual byte count and writes are derived by the service. -/
theorem FileReadResult.footprint (effect : FileReadResult heap world handle pointer count value after next)
    (unique : HeapBlockBasesUnique heap) :
    HeapWritesOn heap after (fun location => pointer ≤ location ∧ location < pointer + count) := by
  cases read : World.readFileBytes (World.record world .read) handle count with
  | none =>
      simp only [FileReadResult, read] at effect
      simpa only [effect.2.1] using (HeapWritesOn.refl (allowed := fun location =>
        pointer ≤ location ∧ location < pointer + count) unique)
  | some pair =>
      simp only [FileReadResult, read] at effect
      exact effect.2.2.2.footprint.weaken (by
        intro location inside
        exact ⟨inside.1, Nat.lt_of_lt_of_le inside.2 (Nat.add_le_add_left effect.2.2.1 _)⟩)

theorem ReadEffect.noViews (effect : ReadEffect before handle pointer count value after)
    (views : before.i32ArrayViews = []) :
    FileReadResult before.heap before.world handle pointer count value after.heap after.world := by
  obtain ⟨heap, flushed, result⟩ := effect
  have identity : syncI32ViewsToHeap before = .ok before := by
    simp only [syncI32ViewsToHeap, views, syncI32ViewsToHeapFrom]
  have same : heap = before.heap := congrArg State.heap (Except.ok.inj (flushed.symm.trans identity))
  simpa only [same] using result

/-- A supplied pointer contract selects the already-proved effect boundary
    using determinism; it does not reevaluate the argument. -/
theorem PointerReadEffect.atPointer
    (effect : PointerReadEffect program before expression handle count value after)
    (pointer : RunsExpr program before expression (.pointer address) mapped) :
    ReadEffect mapped handle address count value after := by
  obtain ⟨actual, completed, run, result⟩ := effect
  obtain ⟨same, rfl⟩ := run.agree pointer
  have same := Value.pointer.inj same
  subst actual
  exact result

/-- Requests below the signed ABI limit cannot wrap a successful byte count
    into an error or exceed the request. Invalid handles still return -1. -/
theorem FileReadResult.success
    (effect : FileReadResult heap world handle pointer count value after next)
    (read : World.readFileBytes (World.record world .read) handle count = some (bytes, updated))
    (fits : count < 2 ^ 31) :
    value = .signed .i32 bytes.length ∧ next = updated ∧ bytes.length ≤ count ∧
      BytesWrite heap after pointer bytes := by
  simp only [FileReadResult, read] at effect
  have wrapped : World.i32Result bytes.length = .signed .i32 bytes.length := by
    simp only [World.i32Result, World.wrapI32]
    rw [Int.emod_eq_of_lt (Int.natCast_nonneg _) (by omega), if_neg (by omega)]
  exact ⟨effect.1.trans wrapped, effect.2⟩

theorem FileReadResult.returnBound
    (effect : FileReadResult heap world handle pointer count value after next)
    (fits : count < 2 ^ 31) :
    ∃ number : Int, value = .signed .i32 number ∧
      (number = -1 ∨ 0 ≤ number ∧ number ≤ count) := by
  cases read : World.readFileBytes (World.record world .read) handle count with
  | none =>
    simp only [FileReadResult, read] at effect
    exact ⟨-1, effect.1.trans (by unfold World.i32Result; congr 1), Or.inl rfl⟩
  | some result =>
    rcases result with ⟨bytes, updated⟩
    obtain ⟨value, _, range, _⟩ := effect.success read fits
    exact ⟨bytes.length, value, Or.inr ⟨Int.natCast_nonneg _, by omega⟩⟩

private theorem readFileBytes_bound
    (read : World.readFileBytes world handle count = some (bytes, after)) : bytes.length ≤ count := by
  unfold World.readFileBytes at read
  split at read
  · cases read
  · split at read
    · cases read
    · split at read
      · cases read
      · simp only [Option.some.injEq, Prod.mk.injEq] at read
        rw [← read.1, List.length_take]
        exact Nat.min_le_left _ _

/-- The byte-oriented host service is total on readable storage. This shared
    boundary derives the call, exact file result and byte frame before any
    registered-view synchronization or source-call composition. -/
theorem FileReadResult.perform {heap : Heap} {world : World.State} {handle : Int} {pointer count : Nat}
    (unique : HeapBlockBasesUnique heap) (readable : heap.Readable pointer count) :
    ∃ value after next bytes,
      World.call heap world .read [.signed .i32 handle, .pointer pointer, .unsigned .usize count] =
        .returned value after next ∧ FileReadResult heap world handle pointer count value after next ∧
      BytesWrite heap after pointer bytes := by
  cases read : World.readFileBytes (World.record world .read) handle count with
  | none =>
    exact ⟨World.i32Result (-1), heap, World.record world .read, [],
      by simp only [World.call, World.callSimple, read],
      by simp only [FileReadResult, read, true_and], BytesWrite.refl unique⟩
  | some result =>
    rcases result with ⟨bytes, next⟩
    have bound := readFileBytes_bound read
    have range : heap.Readable pointer bytes.length := by
      simpa only [Nat.add_zero] using readable.subrange (start := 0) (length := bytes.length) (by omega)
    obtain ⟨after, stored, effect⟩ := Heap.storeBytes_of_readable bytes unique range
    exact ⟨World.i32Result bytes.length, after, next, bytes,
      by simp only [World.call, World.callSimple, read, stored],
      by simp only [FileReadResult, read, true_and]; exact ⟨bound, effect⟩, effect⟩

/-- Raw-buffer host reads retain the entire cell/local/view state. Readability
    and heap uniqueness derive completion; invalid handles still return -1.
    This route does not manufacture an empty typing context for raw storage. -/
theorem RunsExpr.readRaw
    (found : program.function? functionId = some function)
    (body : function.body = none) (external : function.external = some (.host .read))
    (parameters : bindParameters function.parameters
      [.signed .i32 handle, .pointer pointer, .unsigned .usize count] = some bindings)
    (noViews : before.i32ArrayViews = []) (unique : HeapBlockBasesUnique before.heap)
    (readable : before.heap.Readable pointer count) :
    ∃ value heap world, RunsExpr program before
      (.call functionId [.value (.signed .i32 handle), .value (.pointer pointer), .value (.unsigned .usize count)])
      value { before with heap, world } ∧
      FileReadResult before.heap before.world handle pointer count value heap world := by
  obtain ⟨value, heap, world, _, called, result, _⟩ := FileReadResult.perform unique readable
  exact ⟨value, heap, world, RunsExpr.hostCall found body external parameters noViews called, result⟩

/-- Reading a file into accessible storage preserves live typed views. Invalid
    handles still return the modeled error value; successful reads may update
    aliases through native storage. Host and synchronization success are derived. -/
theorem RunsExpr.readViews
    (found : program.function? functionId = some function)
    (body : function.body = none) (external : function.external = some (.host .read))
    (parameters : bindParameters function.parameters
      [.signed .i32 handle, .pointer pointer, .unsigned .usize count] = some bindings)
    (access : before.I32ViewsAccessible program types) (readable : before.heap.Readable pointer count) :
    ∃ value after, RunsExpr program before
      (.call functionId [.value (.signed .i32 handle), .value (.pointer pointer), .value (.unsigned .usize count)])
      value after ∧ after.I32ViewsAccessible program types ∧
      (before.I32ViewsUnique → after.I32ViewsCoherent program types) ∧
      (before.I32ViewsReady program types → after.I32ViewsReady program types) ∧
      ReadEffect before handle pointer count value after := by
  obtain ⟨heap, flushed, readyAccess, retained, bounded⟩ := access.flush
  obtain ⟨value, written, world, bytes, called, result, effect⟩ :=
    FileReadResult.perform readyAccess.unique (retained pointer count readable)
  obtain ⟨cells, run, finalAccess, coherent⟩ := RunsExpr.hostCallViews found body external parameters flushed called
    (readyAccess.bytesWrite effect)
  exact ⟨value, _, run, finalAccess, coherent,
    fun ready => ⟨finalAccess, effect.below (bounded ready.below), ready.keys⟩, heap, flushed, result⟩

/-- Reuse a host-read contract after an effectful pointer expression. -/
theorem RunsExpr.readPointer {bindings : Address → List (VarId × Value)}
    (found : program.function? functionId = some function)
    (body : function.body = none) (external : function.external = some (.host .read))
    (parameters : ∀ pointer, bindParameters function.parameters
      [.signed .i32 handle, .pointer pointer, .unsigned .usize count] = some (bindings pointer))
    (pointer : RunsExpr program before expression (.pointer address) mapped)
    (ready : mapped.I32ViewsReady program types) (readable : mapped.heap.Readable address count) :
    ∃ value after, RunsExpr program before
      (.call functionId [.value (.signed .i32 handle), expression,
        .value (.unsigned .usize count)]) value after ∧
      after.I32ViewsReady program types ∧ after.I32ViewsCoherent program types ∧
      PointerReadEffect program before expression handle count value after := by
  obtain ⟨value, after, called, _, coherent, finalReady, effect⟩ := RunsExpr.readViews found body external
    (parameters _) ready.toI32ViewsAccessible readable
  exact ⟨value, after, RunsExpr.callArguments
    (.cons (.ofStable .value rfl) (.cons pointer (.cons (.ofStable .value rfl) .nil))) called,
    finalReady ready, coherent ready.keys, address, mapped, pointer, effect⟩

/-- Typed array exposure derives the pointer's readable storage. -/
theorem RunsExpr.readArray {bindings : Address → List (VarId × Value)}
    (found : program.function? functionId = some function)
    (body : function.body = none) (external : function.external = some (.host .read))
    (parameters : ∀ pointer, bindParameters function.parameters
      [.signed .i32 handle, .pointer pointer, .unsigned .usize count] = some (bindings pointer))
    (target : CellTargetValid program types before cell [] (.array (.scalar (.signed .i32)) length))
    (binding : before.cellId? localId = some cell) (ready : before.I32ViewsReady program types)
    (bound : count ≤ length * 4) :
    ∃ value after, RunsExpr program before
      (.call functionId [.value (.signed .i32 handle), .i32ArrayDataPtr (.local localId),
        .value (.unsigned .usize count)]) value after ∧
      after.I32ViewsReady program types ∧ after.I32ViewsCoherent program types ∧
      PointerReadEffect program before (.i32ArrayDataPtr (.local localId)) handle count value after := by
  obtain ⟨mapped, pointer, mappedReady, readable, _⟩ := target.i32ArrayDataPtr binding ready
  exact RunsExpr.readPointer found body external parameters pointer mappedReady
    (by simpa only [Nat.add_zero] using readable.subrange (start := 0) (length := count) (by simpa using bound))

/-- The extractor's slice-pointer calling convention. Operand effects occur
    before storage validation, and bounded requests derive destination readability. -/
theorem RunsExpr.readSlice {bindings : Address → List (VarId × Value)}
    (found : program.function? functionId = some function)
    (body : function.body = none) (external : function.external = some (.host .read))
    (parameters : ∀ pointer, bindParameters function.parameters
      [.signed .i32 handle, .pointer pointer, .unsigned .usize count] = some (bindings pointer))
    (operand : RunsExpr program before expression slice middle)
    (valid : I32SliceValid program types middle slice length) (ready : middle.I32ViewsReady program types)
    (bound : count ≤ length * 4) :
    ∃ value after, RunsExpr program before
      (.call functionId [.value (.signed .i32 handle), .i32SliceDataPtr expression,
        .value (.unsigned .usize count)]) value after ∧
      after.I32ViewsReady program types ∧ after.I32ViewsCoherent program types ∧
      PointerReadEffect program before (.i32SliceDataPtr expression) handle count value after := by
  obtain ⟨address, mapped, pointer, mappedReady, readable, _⟩ := valid.dataPointer operand ready
  exact RunsExpr.readPointer found body external parameters pointer mappedReady
    (by simpa only [Nat.add_zero] using readable.subrange (start := 0) (length := count) (by simpa using bound))

#print axioms RunsExpr.hostCallViews
#print axioms FileReadResult.perform
#print axioms RunsExpr.readRaw
#print axioms RunsExpr.writeStdoutViews
#print axioms RunsExpr.writeStdoutFramed
#print axioms RunsExpr.readViews
#print axioms RunsExpr.readArray
#print axioms RunsExpr.readSlice
#print axioms ReadEffect.noViews
#print axioms PointerReadEffect.atPointer
#print axioms FileReadResult.returnBound
#print axioms FileReadResult.success
#print axioms FileReadResult.readable

end Lanius.Semantics
