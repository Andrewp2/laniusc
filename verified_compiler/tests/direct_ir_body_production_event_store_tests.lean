import verified_compiler.tests.direct_ir_event_store

namespace IRBodyProductionEventStoreTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IREventStoreProof

def eventBytes := encodeNatLE 4 0 ++ List.replicate 4 165 ++ i32Bytes 0 ++ List.replicate 28 165
def typeBytes := encodeNatLE 4 1 ++ List.replicate 12 165
def original : State := {
  heap := {
    blocks := [{
      base := 16
      size := 112
      alignment := 8
      bytes := eventBytes ++ eventBytes ++ typeBytes ++ typeBytes }]
    nextAddress := 128 }
  locals := [(9, 3)]
  cells := [{ id := 3, value := some (.signed .i32 91) }]
  nextCell := 4 }

def input (enabled : Bool) : Context original := {
  position := 0, capacity := 2, events := 88
  types := if enabled then 120 else 0
  typesLength := if enabled then 2 else 0
  enabled := enabled, eventBase := 56, typeBase := if enabled then 112 else 0
  bound := by decide, fits := by decide
  eventLocation := by
    have width : NativeLayout.valueWords? extractedProgram eventType = some 5 := by decide +kernel
    simp only [rawSliceElementAddress?, width]
    rfl
  typeBound := by intro yes; simp only [yes, ↓reduceIte]; decide
  typeLocation := by
    intro yes
    have width : NativeLayout.valueWords? extractedProgram referenceType = some 2 := by decide +kernel
    simp only [yes, ↓reduceIte, rawSliceElementAddress?, width]
    rfl
  eventRoom := Heap.Readable.of_loadBytes (show original.heap.loadBytes 56 40 = .ok eventBytes from rfl)
  typeRoom := by
    intro yes
    simp only [yes, ↓reduceIte]
    exact Heap.Readable.of_loadBytes (show original.heap.loadBytes 112 16 = .ok typeBytes from rfl)
  separate := by intro yes; simp only [yes, ↓reduceIte]; exact Or.inl (by decide) }

-- The theorem is applied to independently supplied bytes in both modes.
-- Disabled storage is null/empty; neighboring annotations are still retained.
theorem appendPreserves (enabled : Bool) (word : BitVec 32) :
    ∃ after, RunsExpr extractedProgram original ((input enabled).call (integer word)) (.signed .i32 1) after ∧
      readNativeValue 64 extractedProgram after.heap eventType 56 = .ok (integer word) ∧
      after.heap.loadBytes 16 40 = .ok eventBytes ∧
      after.heap.loadBytes 96 16 = .ok typeBytes ∧
      FreshCellFrame original after ∧ after.world = original.world ∧
      after.i32ArrayViews = original.i32ArrayViews := by
  obtain ⟨after, run, cells, world, views, snapshot, effect⟩ := actualAppend (input enabled) (integerCodec word)
    (by simp [State.CellsWellFormed, original])
    (by intro left hl right hr _; simp only [original, List.mem_singleton] at hl hr; exact hl.trans hr.symm) rfl
  have footprint := (show appendHeapEffect (input enabled).enabled (input enabled).eventBase
    (input enabled).typeBase (integer word) original.heap after.heap from ⟨snapshot, effect⟩).footprint
  refine ⟨after, run, snapshot.read, ?_, ?_, cells, world, views⟩
  · exact footprint.loadBytes (pointer := 16) (count := 40)
      (show original.heap.loadBytes 16 40 = .ok eventBytes from rfl)
      (by intro location inside writes; dsimp only [input] at writes
          rcases writes with event | annotation
          · omega
          · rcases annotation with ⟨yes, bounds⟩; simp only [yes, ↓reduceIte] at bounds; omega)
  · exact footprint.loadBytes (pointer := 96) (count := 16)
      (show original.heap.loadBytes 96 16 = .ok typeBytes from rfl)
      (by intro location inside writes; dsimp only [input] at writes
          rcases writes with event | annotation
          · change 56 ≤ 96 + location ∧ 96 + location < 96 at event
            omega
          · rcases annotation with ⟨yes, bounds⟩; simp only [yes, ↓reduceIte] at bounds; omega)

example : original.heap.loadBytes (input false).types 1 = .error .invalidPointer := by rfl

#print axioms appendPreserves

#eval (do
  for enabled in [false, true] do
    for word in [0, -1, 2147483647, -2147483648] do
      let event := integer (BitVec.ofInt 32 word)
      let .done result after := evalExpr 100 extractedProgram original ((input enabled).call event)
        | throw (IO.userError "conditional event append trapped")
      unless result == .signed .i32 1 do throw (IO.userError "conditional append cursor changed")
      let .ok stored := readNativeValue 64 extractedProgram after.heap eventType 56
        | throw (IO.userError "conditional append payload unreadable")
      let .ok neighbor := after.heap.loadBytes 16 40
        | throw (IO.userError "neighboring event unreadable")
      let .ok annotationNeighbor := after.heap.loadBytes 96 16
        | throw (IO.userError "neighboring annotation unreadable")
      unless stored == event do throw (IO.userError "conditional append payload changed")
      unless neighbor == eventBytes && annotationNeighbor == typeBytes do
        throw (IO.userError "conditional append changed neighboring storage")
      if enabled then
        let .ok annotation := readNativeValue 64 extractedProgram after.heap referenceType 112
          | throw (IO.userError "enabled append annotation unreadable")
        unless annotation == invalid do
          throw (IO.userError "enabled append did not reset annotation")
      else
        let .ok annotation := after.heap.loadBytes 112 16
          | throw (IO.userError "disabled append changed annotation readability")
        unless annotation == typeBytes do
          throw (IO.userError "disabled append wrote annotation bytes")
      unless after.locals == original.locals && after.world.calls.isEmpty &&
          after.local? 9 == original.local? 9 && after.i32ArrayViews.isEmpty do
        throw (IO.userError "conditional append changed caller metadata")
  IO.println "actual conditional append fixtures: enabled reset and unreadable disabled annotations passed" : IO Unit)

end IRBodyProductionEventStoreTests
