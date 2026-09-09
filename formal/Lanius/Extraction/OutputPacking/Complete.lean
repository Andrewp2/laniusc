import Lanius.Extraction.OutputPacking.Setup
import Lanius.Extraction.OutputPacking.Stdout

namespace Lanius.Extraction.OutputPacking
open Lanius Lanius.Core Lanius.Semantics Lanius.Properties Lanius.Separation

theorem prepare_and_write (program : Program) (memory : LoopMemory) (locals : LoopLocals)
    (wordCount clearCursor : VarId) (original : List Int)
    (wellFormed : StateWellFormed before)
    (bounded : memory.bytes.length ≤ 8388608) (capacity : memory.words ≤ original.length)
    (tailEq : memory.tail = original.drop memory.words)
    (workspaceRead : before.local? locals.workspace = some
      (.slice (.scalar (.signed .i32)) memory.workspaceCell [] 0 original.length))
    (workspaceContents : before.cellEntry? memory.workspaceCell = some {
      id := memory.workspaceCell, value := some (.array (signedI32Values original)) })
    (inputRead : before.local? locals.input = some
      (.slice (.scalar (.signed .i32)) memory.inputCell [] 0 memory.inputValues.length))
    (inputContents : before.cellEntry? memory.inputCell = some {
      id := memory.inputCell, value := some (.array (signedI32Values memory.inputValues)) })
    (lengthRead : before.local? locals.length = some (.signed .i32 memory.bytes.length))
    (wordDistinct : ∀ localId ∈ [locals.workspace, locals.input, locals.length], wordCount ≠ localId)
    (clearDistinct : ∀ localId ∈ [locals.workspace, wordCount, locals.input, locals.length], clearCursor ≠ localId)
    (packDistinct : ∀ localId ∈ [locals.workspace, locals.input, locals.length], locals.cursor ≠ localId)
    (source : StdoutTail) (function : Function) (bindings : List (VarId × Value)) (view : I32ArrayView)
    (sameLength : source.length = locals.length)
    (fits : memory.bytes.length < unsignedModulus program.target .usize)
    (pointerRead : before.local? source.pointer = some (.pointer view.address))
    (pointerDistinct : wordCount ≠ source.pointer ∧ clearCursor ≠ source.pointer ∧ locals.cursor ≠ source.pointer)
    (pointerSeparate : ∀ cell, before.cellId? source.pointer = some cell → cell ≠ memory.workspaceCell)
    (sizeLength : source.size ≠ source.length) (sizePointer : source.size ≠ source.pointer)
    (functionId : function.id = source.function)
    (functionFound : program.function? function.id = some function)
    (parametersBound : bindParameters function.parameters
      [.pointer view.address, .unsigned .usize memory.bytes.length] = some bindings)
    (noBody : function.body = none) (host : function.external = some (.host .writeStdout))
    (member : view ∈ before.i32ArrayViews) (viewRoot : view.root = memory.workspaceCell)
    (blocks : ∀ view ∈ before.i32ArrayViews, I32ArrayViewBlockWellFormed before.heap view)
    (disjoint : before.i32ArrayViews.Pairwise I32ViewRangesDisjoint)
    (roots : ∀ view ∈ before.i32ArrayViews, view.projections = [])
    (metadata : ∀ view ∈ before.i32ArrayViews, view.root = memory.workspaceCell →
      view.length = memory.words + memory.tail.length)
    (arrays : ∀ view ∈ before.i32ArrayViews, view.root ≠ memory.workspaceCell → ∃ elements,
      readCellProjection before view.root view.projections = .ok (.array elements) ∧
      elements.length = view.length ∧
      ∀ element ∈ elements, ∃ value, element = .signed .i32 value)
    (lengthSeparate : ∀ cell, before.cellId? locals.length = some cell →
      ∀ view ∈ before.i32ArrayViews, cell ≠ view.root) :
    ∃ after, Executes program before
      (Preparation.statement ⟨locals, wordCount, clearCursor, source.statement⟩)
      (.returned (some (.signed .i32 0))) after ∧
      after.world = { before.world with
        standardOutput := before.world.standardOutput ++ memory.bytes
        calls := before.world.calls ++ [.writeStdout] } := by
  apply prepare_with_continuation program memory locals wordCount clearCursor original wellFormed
    (continuation := source.statement) (completion := .returned (some (.signed .i32 0)))
    (post := fun world => world = { before.world with
      standardOutput := before.world.standardOutput ++ memory.bytes
      calls := before.world.calls ++ [.writeStdout] })
    bounded capacity tailEq workspaceRead workspaceContents inputRead inputContents lengthRead
    wordDistinct clearDistinct packDistinct
  intro clear next cleared packed clearSpace clearFresh packFresh nextSpace nextInput nextBytes nextTail nextInputTail clearing complete packing effect
  have pointerBinding := preparation_local_binding memory locals wordCount clearCursor source.pointer
    pointerDistinct.1 pointerDistinct.2.1 pointerDistinct.2.2 clearing packing
  have keptPointer := preserved_local wellFormed effect pointerBinding pointerRead pointerSeparate
  have lengthBinding := preparation_local_binding memory locals wordCount clearCursor locals.length
    (wordDistinct _ (by simp)) (clearDistinct _ (by simp)) (packDistinct _ (by simp)) clearing packing
  have registry := effect.views
  have packedArrays := complete.registered_arrays wellFormed effect
    (fun other mem same => ⟨roots other mem, by
      have size := metadata other mem (same.trans nextSpace)
      simpa only [LoopMemory.words, nextBytes, nextTail] using size⟩)
    (fun other mem different => by
      change other.root ≠ memory.workspaceCell
      simpa only [nextSpace] using different)
    (fun other mem different => arrays other mem (by simpa only [nextSpace] using different))
  have contents : readCellProjection packed view.root view.projections =
      .ok (.array (pack memory.bytes ++ signedI32Values memory.tail)) := by
    have stored := complete.complete_contents
    rw [nextSpace, nextBytes, nextTail] at stored
    simp [readCellProjection, viewRoot, roots view member, stored, projectedValue]
  obtain ⟨after, run, world⟩ := source.executes program packed function bindings view memory.bytes memory.tail
    complete.wellFormed fits bounded
    (by simpa only [sameLength, nextBytes] using complete.limit) keptPointer sizeLength sizePointer
    functionId functionFound parametersBound noBody host
    (by simpa only [registry] using disjoint) (by simpa only [registry] using member) contents
    (fun other mem => by
      rw [effect.heap]
      exact blocks other (by simpa only [registry] using mem))
    (fun other mem => roots other (by simpa only [registry] using mem)) packedArrays
    (fun cell binding other mem => lengthSeparate cell
      (by simpa only [sameLength, lengthBinding] using binding) other
      (by simpa only [registry] using mem))
  exact ⟨after, run, by simpa only [effect.world] using world⟩

end Lanius.Extraction.OutputPacking
