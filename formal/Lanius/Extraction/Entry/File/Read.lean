import Lanius.Extraction.Input.File.Call
import Lanius.Extraction.Host.File.Close
import Lanius.Extraction.Source.Statement
import Lanius.Semantics.Prefix

namespace Lanius.Extraction.Entry.File.Read

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation Lanius.CallContracts
open Lanius.Extraction.CompactOutput

structure Stage where
  handle : Lanius.VarId
  output : Lanius.VarId
  packed : Lanius.VarId
  count : Lanius.VarId
  closed : Lanius.VarId
  failure : Stmt
  continuation : Stmt

def Stage.guard (stage : Stage) : Expr := binary .logicalOr
  (binary .lessEqual (read stage.count) negativeOne) (binary .lessEqual (read stage.closed) negativeOne)

def Stage.statement (stage : Stage) (reader closer : FunctionId) : Stmt :=
  .letLocal stage.count i32 (.call reader [read stage.handle, read stage.output, number 65536, read stage.packed])
    (.letLocal stage.closed i32 (.call closer [read stage.handle])
      (.sequence (.ifThenElse stage.guard stage.failure .skip) stage.continuation))

structure Stage.Supported (stage : Stage) : Prop where
  handle : stage.count ≠ stage.handle
  count : stage.closed ≠ stage.count

def Stage.checkSupported? (stage : Stage) : Option (PLift stage.Supported) :=
  if valid : stage.count ≠ stage.handle ∧ stage.closed ≠ stage.count then some ⟨⟨valid.1, valid.2⟩⟩ else none

def check? (reader closer : FunctionId) (statement : Stmt) :
    Option (Source.CheckedStatement (fun stage : Stage => stage.statement reader closer) statement) := do
  let .letLocal count _ (.call _ [.local handle, .local output, _, .local packed])
    (.letLocal closed _ _ (.sequence (.ifThenElse _ failure _) continuation)) := statement | none
  let stage : Stage := ⟨handle, output, packed, count, closed, failure, continuation⟩
  let same ← Equality.statement? statement (stage.statement reader closer)
  pure ⟨stage, same.equal⟩

def closedWorld (resources : Input.File.Resources) (reads : Nat) : Lanius.World.State := {
  resources.finalWorld reads with
  fileHandles := resources.originalHandles
  calls := (resources.finalWorld reads).calls ++ [.close] }

theorem closesFresh (resources : Input.File.Resources) (reads : Nat) :
    Host.File.closedWorld (resources.finalWorld reads) resources.handle.id = closedWorld resources reads := by
  have kept : resources.originalHandles.filter (fun handle => handle.id != resources.handle.id) = resources.originalHandles := by
    apply List.filter_eq_self.mpr
    intro handle member
    simpa using resources.fresh handle member
  simp [Host.File.closedWorld, Input.File.Resources.finalWorld, closedWorld, kept]

/-- The reader's two buffer writes cannot change a caller local that holds
a scalar, pointer, or slice rather than an array backing cell. -/
theorem preservesLocal (resources : Input.File.Resources) (initial : Allocation.Registry before)
    {id : Lanius.VarId} {value : Value}
    (outputMember : resources.output ∈ before.i32ArrayViews) (packedMember : resources.packed ∈ before.i32ArrayViews)
    (finished : Input.File.Finished resources before after)
    (found : before.local? id = some value) (notArray : ∀ elements, value ≠ .array elements) :
    after.local? id = some value := by
  apply finished.effect.preservesLocal initial.wellFormed found
  intro cell binding written
  have separate (view : I32ArrayView) (member : view ∈ before.i32ArrayViews) : cell ≠ view.root := by
    obtain ⟨words, _, stored⟩ := initial.storage member
    exact local_cell_ne_of_distinct_value found stored (notArray _) binding
  exact written.elim (separate resources.output outputMember) (separate resources.packed packedMember)

/-- The common read/close prefix. Closing is unconditional: even a reader
rejection reaches the close call before the result guard is inspected. -/
theorem Stage.readClose (stage : Stage) (supported : stage.Supported)
    (reader : Input.File.Checked program) (closer : Host.CheckedExternal program.core .close 1)
    (resources : Input.File.Resources) (initial : Allocation.Registry before)
    (representable : Host.RepresentableViews before) (disjoint : before.i32ArrayViews.Pairwise I32ViewRangesDisjoint)
    (outputMember : resources.output ∈ before.i32ArrayViews) (packedMember : resources.packed ∈ before.i32ArrayViews)
    (outputContents : before.cellEntry? resources.output.root = some {
      id := resources.output.root
      value := some (.array (signedI32Values resources.original)) })
    (handleRead : before.local? stage.handle = some (.signed .i32 resources.handle.id))
    (outputRead : before.local? stage.output = some (.slice i32 resources.output.root [] 0 resources.output.length))
    (packedRead : before.local? stage.packed = some (.slice i32 resources.packed.root [] 0 resources.packed.length))
    (world : before.world = resources.world) (fixedCapacity : resources.capacity = 65536)
    (sizeFit : 65536 < unsignedModulus program.core.target .usize) :
    ∃ readState closed,
      Evaluates program.core before (.call reader.source.source.function.id
        [read stage.handle, read stage.output, number 65536, read stage.packed]) (.signed .i32 resources.result) readState ∧
      Input.File.Finished resources before readState ∧
      Evaluates program.core (readState.bindLocal stage.count (.signed .i32 resources.result))
        (.call closer.function.id [read stage.handle]) (.signed .i32 0) closed ∧
      Allocation.Registry closed ∧
      Host.Frame (readState.bindLocal stage.count (.signed .i32 resources.result)) closed ∧
      (∃ reads, 0 < reads ∧ closed.world = closedWorld resources reads) ∧
      Host.PreservesViews (readState.bindLocal stage.count (.signed .i32 resources.result)) closed (fun _ => True) := by
  obtain ⟨readState, readCall, finished⟩ := reader.read resources initial representable disjoint outputMember packedMember
    outputContents world sizeFit
    (.cons (local_evaluates program.core handleRead) (.cons (local_evaluates program.core outputRead)
      (.cons (by simpa [fixedCapacity] using (show Evaluates program.core before (number 65536) (.signed .i32 65536) before from evaluatesValue))
        (.cons (local_evaluates program.core packedRead) (.nil _ _)))))
  let counted := readState.bindLocal stage.count (.signed .i32 resources.result)
  have countedRegistry := finished.registry.bindLocal stage.count (.signed .i32 resources.result)
  have handleAfter := preservesLocal resources initial outputMember packedMember finished handleRead (by intro values same; cases same)
  have countedHandle : counted.local? stage.handle = some (.signed .i32 resources.handle.id) :=
    (bindLocal_preserves_other_local finished.registry.wellFormed supported.handle).trans handleAfter
  obtain ⟨reads, positive, readWorld⟩ := finished.world
  have handleFound : counted.world.handle? resources.handle.id =
      some { resources.handle with offset := resources.handle.offset + resources.consumed } := by
    change readState.world.handle? _ = _
    rw [readWorld]
    exact Lanius.World.handle_appended_fresh
      (opened := { resources.handle with offset := resources.handle.offset + resources.consumed }) resources.fresh rfl
  obtain ⟨closed, closeCall, closedRegistry, frame, closeWorld, preserved⟩ := Host.File.evaluatesClose closer
    countedRegistry resources.handle.id _ handleFound
    (.cons (local_evaluates program.core countedHandle) (.nil _ _))
  exact ⟨readState, closed, readCall, finished, closeCall, closedRegistry, frame,
    ⟨reads, positive, closeWorld.trans ((congrArg (fun world => Host.File.closedWorld world resources.handle.id)
      readWorld).trans (closesFresh resources reads))⟩, preserved⟩

/-- Compose the source's whole reader call, mandatory close, and success
guard. The continuation begins at `extract_syntax` with the original handle
list restored and the exact source bytes retained. -/
theorem Stage.executes (stage : Stage) (supported : stage.Supported)
    (reader : Input.File.Checked program) (closer : Host.CheckedExternal program.core .close 1)
    (resources : Input.File.Resources) (initial : Allocation.Registry before)
    (representable : Host.RepresentableViews before) (disjoint : before.i32ArrayViews.Pairwise I32ViewRangesDisjoint)
    (outputMember : resources.output ∈ before.i32ArrayViews) (packedMember : resources.packed ∈ before.i32ArrayViews)
    (outputContents : before.cellEntry? resources.output.root = some {
      id := resources.output.root
      value := some (.array (signedI32Values resources.original)) })
    (handleRead : before.local? stage.handle = some (.signed .i32 resources.handle.id))
    (outputRead : before.local? stage.output = some (.slice i32 resources.output.root [] 0 resources.output.length))
    (packedRead : before.local? stage.packed = some (.slice i32 resources.packed.root [] 0 resources.packed.length))
    (world : before.world = resources.world) (capacity : resources.bytes.length ≤ resources.capacity)
    (fixedCapacity : resources.capacity = 65536) (sizeFit : 65536 < unsignedModulus program.core.target .usize)
    (post : Completion → State → Prop)
    (continuationRun : ∀ readState middle,
      readState.locals = before.locals → Allocation.Registry middle → Host.RepresentableViews middle →
      middle.cellEntry? resources.output.root = some {
        id := resources.output.root
        value := some (.array (signedI32Values (Input.copiedBuffer [] resources.original resources.bytes))) } →
      (∃ reads, 0 < reads ∧ middle.world = closedWorld resources reads) →
      middle.local? stage.count = some (.signed .i32 resources.bytes.length) →
      middle.i32ArrayViews = before.i32ArrayViews →
      (∀ id, id ≠ stage.count → id ≠ stage.closed → middle.cellId? id = before.cellId? id) →
      (∀ id, id ≠ stage.count → id ≠ stage.closed → ∀ value, (∀ elements, value ≠ .array elements) →
        before.local? id = some value → middle.local? id = some value) →
      Host.PreservesViews before middle (fun view => view.root ≠ resources.output.root ∧ view.root ≠ resources.packed.root) →
      Prefix.Reaches program.core before (stage.statement reader.source.source.function.id closer.function.id)
        middle stage.continuation →
      ∃ completion after, Executes program.core middle stage.continuation completion after ∧ post completion (restoreLocals readState after)) :
    ∃ completion after, Executes program.core before (stage.statement reader.source.source.function.id closer.function.id)
      completion after ∧ post completion after := by
  obtain ⟨readState, closed, readCall, finished, closeCall, closedRegistry, frame, closeWorld, preserved⟩ :=
    stage.readClose supported reader closer resources initial representable disjoint outputMember packedMember
      outputContents handleRead outputRead packedRead world fixedCapacity sizeFit
  have result : resources.result = resources.bytes.length := if_pos capacity
  rw [result] at readCall closeCall frame preserved
  let counted := readState.bindLocal stage.count (.signed .i32 resources.bytes.length)
  have countedRegistry := finished.registry.bindLocal stage.count (.signed .i32 resources.bytes.length)
  obtain ⟨reads, positive, readyWorld⟩ := closeWorld
  let ready := closed.bindLocal stage.closed (.signed .i32 0)
  have readyRegistry := closedRegistry.bindLocal stage.closed (.signed .i32 0)
  have countedCount := Assertion.localPointsTo_local _ _ _ _
    (bindLocal_owns_fresh readState stage.count (.signed .i32 resources.bytes.length) finished.registry.wellFormed)
  have readyCount : ready.local? stage.count = some (.signed .i32 resources.bytes.length) :=
    (bindLocal_preserves_other_local closedRegistry.wellFormed supported.count).trans
      (frame.preservesLocal countedRegistry countedCount (by intro values same; cases same))
  have readyClosed := Assertion.localPointsTo_local _ _ _ _
    (bindLocal_owns_fresh closed stage.closed (.signed .i32 0) closedRegistry.wellFormed)
  have guard : Evaluates program.core ready stage.guard (.boolean false) ready := by
    have first : Evaluates program.core ready (binary .lessEqual (read stage.count) negativeOne) (.boolean false) ready := by
      apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program.core readyCount) (negativeOne_evaluates program.core ready)
      simp [evalBinaryValue, evalSignedBinary]
      omega
    have second : Evaluates program.core ready (binary .lessEqual (read stage.closed) negativeOne) (.boolean false) ready := by
      apply evaluatesEagerBinary (by decide) (by decide) (local_evaluates program.core readyClosed) (negativeOne_evaluates program.core ready)
      simp [evalBinaryValue, evalSignedBinary]
    exact evaluatesPureLogicalOr first second
  have countViews : (readState.bindLocal stage.count (.signed .i32 resources.bytes.length)).i32ArrayViews = before.i32ArrayViews := finished.effect.views
  have readyViews : ready.i32ArrayViews = before.i32ArrayViews := frame.views.trans countViews
  have countOutput : (readState.bindLocal stage.count (.signed .i32 resources.bytes.length)).cellEntry? resources.output.root = some {
      id := resources.output.root
      value := some (.array (signedI32Values (Input.copiedBuffer [] resources.original resources.bytes))) } :=
    ((bindLocal_effect readState stage.count (.signed .i32 resources.bytes.length)).oldCells resources.output.root
      (finished.registry.root_lt_next (by simpa only [finished.effect.views] using outputMember)) (by simp [CellSet.empty])).trans (finished.outputOfFits capacity)
  have afterOutput := preserved (by simpa only [countViews] using disjoint) resources.output
    (by simpa only [countViews] using outputMember) trivial _
    (by simp only [readCellProjection, countedRegistry.roots resources.output (by simpa only [countViews] using outputMember),
      countOutput, projectedValue])
    ((finished.representable.bindLocal finished.registry stage.count (.signed .i32 resources.bytes.length)) resources.output
      (by simpa only [countViews] using outputMember) _ countOutput)
  have readyOutput := ((bindLocal_effect closed stage.closed (.signed .i32 0)).oldCells resources.output.root
    (closedRegistry.root_lt_next (by simpa only [frame.views, countViews] using outputMember)) (by simp [CellSet.empty])).trans afterOutput
  obtain ⟨completion, after, continued, done⟩ := continuationRun readState ready finished.effect.locals readyRegistry
    (frame.representable.bindLocal closedRegistry stage.closed (.signed .i32 0)) readyOutput ⟨reads, positive, readyWorld⟩ readyCount readyViews (by
      intro id notCount notClosed
      change (closed.bindLocal stage.closed (.signed .i32 0)).cellId? id = before.cellId? id
      rw [bindLocal_preserves_other_cellId closed stage.closed id _ notClosed.symm]
      simp only [State.cellId?, frame.locals]
      change counted.cellId? id = before.cellId? id
      rw [show counted.cellId? id = readState.cellId? id from
        bindLocal_preserves_other_cellId readState stage.count id _ notCount.symm]
      simp only [State.cellId?, finished.effect.locals]) (by
      intro id notCount notClosed value notArray found
      exact (bindLocal_preserves_other_local closedRegistry.wellFormed (Ne.symm notClosed)).trans
        (frame.preservesLocal countedRegistry
          ((bindLocal_preserves_other_local finished.registry.wellFormed (Ne.symm notCount)).trans
            (preservesLocal resources initial outputMember packedMember finished found notArray)) notArray)) (by
      intro _ view member apart words contents range
      obtain ⟨original, _, stored⟩ := initial.storage member
      have same : signedI32Values original = signedI32Values words := by
        have compared : Except.ok (Value.array (signedI32Values original)) =
            (Except.ok (Value.array (signedI32Values words)) : Except Lanius.Trap Value) := by
          simpa only [readCellProjection, initial.roots view member, stored, projectedValue] using contents
        exact Value.array.inj (Except.ok.inj compared)
      rw [same] at stored
      have atRead := finished.effect.preservesEntry initial.wellFormed stored (fun changed => changed.elim apart.1 apart.2)
      have atCount := ((bindLocal_effect readState stage.count (.signed .i32 resources.bytes.length)).oldCells view.root
        (finished.registry.root_lt_next (by simpa only [finished.effect.views] using member)) (by simp [CellSet.empty])).trans atRead
      have atClose := preserved (by simpa only [countViews] using disjoint) view (by simpa only [countViews] using member)
        trivial words (by simp only [readCellProjection, countedRegistry.roots view (by simpa only [countViews] using member),
          atCount, projectedValue]) range
      exact ((bindLocal_effect closed stage.closed (.signed .i32 0)).oldCells view.root
        (closedRegistry.root_lt_next (by simpa only [frame.views, countViews] using member)) (by simp [CellSet.empty])).trans atClose)
    (.letLocal readCall (.letLocal closeCall (.sequence (executesIfFalse guard (executesSkip _ _)) .here)))
  exact ⟨completion, restoreLocals readState (restoreLocals closed after), executesLetLocal readCall
    (executesLetLocal closeCall (executesSequence (executesIfFalse guard (executesSkip _ _)) continued)), done⟩

end Lanius.Extraction.Entry.File.Read
