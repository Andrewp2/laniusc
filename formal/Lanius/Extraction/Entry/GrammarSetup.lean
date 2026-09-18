import Lanius.Extraction.Entry.GrammarCursor
import Lanius.Extraction.Allocation.Borrowed

namespace Lanius.Extraction.Entry.Grammar

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation
open Lanius.Extraction.CompactOutput

theorem setupAndLoop (checked : Hex.Checked program) (locals : Locals) (before : State)
    (text : String) (textBinding : Lanius.VarId) (values : List Nat) (untouched : List Int)
    (destinationCell : Lanius.CellId) (continuation : Stmt) (completion : Completion)
    (post : Lanius.World.State → Prop) (wellFormed : StateWellFormed before)
    (textLocal : before.local? textBinding = some (.string text))
    (destinationLocal : before.local? locals.destination = some (.slice i32 destinationCell [] 0 untouched.length))
    (destinationContents : before.cellEntry? destinationCell = some {
      id := destinationCell, value := some (.array (signedI32Values untouched)) })
    (bounded : ∀ value ∈ values, value < 65536) (capacity : values.length ≤ untouched.length)
    (fits : untouched.length ≤ 2147483647) (count : locals.count = values.length)
    (size : (Lanius.World.utf8Bytes text).length = values.length * 4)
    (decoded : decodeI32Array values.length (Lanius.World.utf8Bytes text) =
      .ok (signedI32Values (values.map (fun value => (Hex.packedWord value : Int)))))
    (sourceDestination : locals.source ≠ locals.destination)
    (cursorSource : locals.cursor ≠ locals.source) (cursorDestination : locals.cursor ≠ locals.destination)
    (wordDestination : locals.word ≠ locals.destination) (wordCursor : locals.word ≠ locals.cursor)
    (continuationRun : ∀ memory : Memory locals, memory.values = values → memory.untouched = untouched →
      memory.destinationCell = destinationCell → ∀ middle, Invariant memory memory.values middle →
      middle.world = before.world →
      CellEffect (CellSet.singleton destinationCell) before (restoreLocals before middle) →
      (∀ id, id ≠ locals.source → id ≠ locals.cursor → middle.cellId? id = before.cellId? id) →
      (Allocation.Registry before → Allocation.Registry middle) →
      (∃ fresh, middle.i32ArrayViews = before.i32ArrayViews ++ fresh) →
      Prefix.Reaches program.core before
        (.letLocal locals.source (.slice i32)
          (.i32SliceFromRawParts (.stringDataPtr (.local textBinding)) (.value (.signed .i32 values.length)))
          (.letLocal locals.cursor i32 (.value (.signed .i32 0))
            (.sequence (locals.loop checked.source.function.id) continuation))) middle continuation →
      ∃ after, Executes program.core middle continuation completion after ∧ post after.world) :
    ∃ after, Executes program.core before
      (.letLocal locals.source (.slice i32)
        (.i32SliceFromRawParts (.stringDataPtr (.local textBinding)) (.value (.signed .i32 values.length)))
        (.letLocal locals.cursor i32 (.value (.signed .i32 0))
          (.sequence (locals.loop checked.source.function.id) continuation))) completion after ∧ post after.world := by
  let words := values.map (fun value => (Hex.packedWord value : Int))
  obtain ⟨viewed, initialized, sourceContents, viewedWF, sameLocals, preserved, nextCell, world, domain, localValues, viewResources⟩ :=
    stringInitializer program.core before text textBinding words wellFormed textLocal
      (by simpa [words] using size) (by simpa [words] using decoded)
  have length : words.length = values.length := List.length_map _
  rw [length] at initialized
  have oldDestination := StateWellFormed.cell_lt_next_of_entry wellFormed destinationContents
  have destinationViewed := (preserved destinationCell oldDestination).trans destinationContents
  let sourceValue := Value.slice i32 before.nextCell [] 0 values.length
  let scope := viewed.bindLocal locals.source sourceValue
  have scopeWF : StateWellFormed scope := bindLocal_preserves_well_formed viewed _ _ viewedWF
  have sourceKept := ((bindLocal_effect viewed locals.source sourceValue).oldCells before.nextCell
    (StateWellFormed.cell_lt_next_of_entry viewedWF sourceContents) (by simp [CellSet.empty])).trans sourceContents
  have destinationKept := ((bindLocal_effect viewed locals.source sourceValue).oldCells destinationCell
    (StateWellFormed.cell_lt_next_of_entry viewedWF destinationViewed) (by simp [CellSet.empty])).trans destinationViewed
  let memory : Memory locals := {
    sourceCell := before.nextCell, destinationCell, cursorCell := scope.nextCell,
    values, untouched, bounded, capacity, fits, count,
    sourceDestination := Ne.symm (Nat.ne_of_lt oldDestination),
    sourceCursor := Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry scopeWF sourceKept),
    destinationCursor := Nat.ne_of_lt (StateWellFormed.cell_lt_next_of_entry scopeWF destinationKept),
    wordDestination, wordCursor }
  have sourceRead : scope.local? locals.source = some (.slice i32 memory.sourceCell [] 0 memory.source.length) := by
    simpa [memory, Memory.source, sourceValue] using bindLocal_finds_local viewed locals.source sourceValue viewedWF
  have destinationRead : scope.local? locals.destination = some (.slice i32 destinationCell [] 0 untouched.length) :=
    (bindLocal_preserves_other_local viewedWF sourceDestination).trans
      ((localValues locals.destination).trans destinationLocal)
  have viewEffect : CellEffect CellSet.empty before viewed :=
    ⟨viewedWF, sameLocals, world, fun cell old _ => preserved cell old,
      by rw [nextCell]; exact Nat.le_succ _, domain⟩
  obtain ⟨after, ran, satisfied⟩ := initializeAndLoop checked locals memory scope continuation completion post
    scopeWF rfl sourceRead destinationRead sourceKept destinationKept cursorSource cursorDestination
    (fun middle invariant effect heapFrame reached => by
      have closedCursor := CellEffect.closeLocal scope locals.cursor (.signed .i32 0) scopeWF effect
      have narrowed : CellEffect (CellSet.singleton destinationCell) scope (restoreLocals scope middle) :=
        closedCursor.narrow (by
          intro cell old changed
          rcases changed with destination | cursor
          · exact destination
          · exact False.elim ((Nat.ne_of_lt old) cursor))
      have closedSource := CellEffect.closeLocal viewed locals.source sourceValue viewedWF narrowed
      have combined := (viewEffect.weaken CellSet.empty_subset).trans closedSource
      apply continuationRun memory rfl rfl rfl middle invariant (effect.world.trans world)
      · simpa only [restoreLocals, sameLocals] using combined
      · intro id notSource notCursor
        simp only [State.cellId?, effect.locals]
        simp [scope, State.bindLocal, State.bindCell, State.cellId?, Ne.symm notSource,
          Ne.symm notCursor, sameLocals]
      · intro initialRegistry
        have viewedRegistry := initialRegistry.borrowed viewResources viewedWF
        have scopeRegistry := viewedRegistry.bindLocal locals.source sourceValue
        have cursorRegistry := scopeRegistry.bindLocal locals.cursor (.signed .i32 0)
        have initialInvariant := cursorInvariant locals memory scope scopeWF rfl sourceRead destinationRead
          sourceKept destinationKept cursorSource cursorDestination
        exact preservesRegistry memory [] (by simp) cursorRegistry initialInvariant invariant effect heapFrame
      · obtain ⟨address, elements, views, _⟩ := viewResources.storage
        refine ⟨[{ address, root := before.nextCell, projections := [], length := words.length }], ?_⟩
        rw [heapFrame.views]
        exact views
      · exact .letLocal initialized reached)
  refine ⟨restoreLocals viewed after, ?_, satisfied⟩
  exact executesLetLocal initialized ran

end Lanius.Extraction.Entry.Grammar
