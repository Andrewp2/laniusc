import verified_compiler.tests.direct_ir_event_store

namespace IREventStoreTests

open Lanius Lanius.Core Lanius.Memory Lanius.Semantics IREventStoreProof

def eventBytes := encodeNatLE 4 0 ++ List.replicate 4 165 ++ i32Bytes 0 ++ List.replicate 28 165
def typeBytes := encodeNatLE 4 1 ++ List.replicate 12 165
def sample : State := { heap := { blocks := [{
  base := 16
  size := 112
  alignment := 8
  bytes := eventBytes ++ eventBytes ++ typeBytes ++ typeBytes }], nextAddress := 128 } }
def oldType := source_value Extracted.«ir::type_ref».Types.«TypeRef».«Void» []
private theorem eventWidth : NativeLayout.valueWords? extractedProgram eventType = some 5 := by decide +kernel
private theorem typeWidth : NativeLayout.valueWords? extractedProgram referenceType = some 2 := by decide +kernel

def input : Context sample := {
  position := 0, capacity := 2, events := 88, types := 120, typesLength := 2, enabled := true
  eventBase := 56, typeBase := 112
  bound := by decide, fits := by decide, typeBound := fun _ => by decide
  eventLocation := by
    have width := eventWidth
    dsimp only [eventType] at width ⊢
    simp only [rawSliceElementAddress?, width]
    rfl
  typeLocation := by
    intro _
    have width := typeWidth
    dsimp only [referenceType] at width ⊢
    simp only [rawSliceElementAddress?, width]
    rfl
  eventRoom := Heap.Readable.of_loadBytes (show sample.heap.loadBytes 56 40 = .ok eventBytes from rfl)
  typeRoom := fun _ => Heap.Readable.of_loadBytes (show sample.heap.loadBytes 112 16 = .ok typeBytes from rfl)
  separate := fun _ => Or.inl (by decide) }

-- Arbitrary signed i32 payload, not just the example 7. Nonzero padding and
-- a previous Void annotation witness the real overwrite/reset contract.
theorem appendReadback (codec : NativeStoreSpec 64 extractedProgram eventType event 40) :
    ∃ after, RunsExpr extractedProgram sample (input.call event) (.signed .i32 1) after ∧
      readNativeValue 64 extractedProgram after.heap eventType 56 = .ok event ∧
      readNativeValue 64 extractedProgram after.heap referenceType 112 = .ok invalid ∧
      after.heap.loadBytes 16 40 = .ok eventBytes ∧ after.heap.loadBytes 96 16 = .ok typeBytes := by
  obtain ⟨after, run, _, _, _, event, middle, first, last⟩ := actualAppend input codec
    (by simp [State.CellsWellFormed, sample])
    (by intro left hl right hr _; simp only [sample, List.mem_singleton] at hl hr; exact hl.trans hr.symm) rfl
  obtain ⟨annotation, second⟩ := last
  exact ⟨after, run, event.read, annotation.read,
    second.loadBytes (first.loadBytes (show sample.heap.loadBytes 16 40 = .ok eventBytes from rfl)
      (Or.inl (by decide))) (Or.inl (by decide)),
    second.loadBytes (first.loadBytes (show sample.heap.loadBytes 96 16 = .ok typeBytes from rfl)
      (Or.inr (by decide))) (Or.inl (by decide))⟩

theorem integerAppend (word : BitVec 32) :
    ∃ after, RunsExpr extractedProgram sample (input.call (integer word)) (.signed .i32 1) after ∧
      readNativeValue 64 extractedProgram after.heap eventType 56 = .ok (integer word) ∧
      readNativeValue 64 extractedProgram after.heap referenceType 112 = .ok invalid ∧
      after.heap.loadBytes 16 40 = .ok eventBytes ∧ after.heap.loadBytes 96 16 = .ok typeBytes :=
  appendReadback (integerCodec word)

-- Bounds rejection is independent of storage validity: null descriptors in
-- an empty heap are safe here because neither store is reached.
example : ∃ after, RunsExpr extractedProgram {} (.call Extracted.«ir::body_events».Functions.«append».core.id
    [.value (source_value Extracted.«ir::body_events».Types.«Region».mk
      [.rawSlice eventType 0 0, .rawSlice referenceType 0 0, .boolean true, .signed .i32 0]),
      .value (.signed .i32 0), .value (integer 7)]) (.signed .i32 (-1)) after ∧ PureFrame {} after :=
  actualReject _ _ 0 0 rfl (Or.inr (by decide)) (by simp [State.CellsWellFormed])

#print axioms integerAppend

#eval (do
  let source := Extracted.«ir::body_events».Functions.«append».core
  let cases := [integer 0, integer 7, integer (-1), integer 2147483647, integer (-2147483648),
    boolean false, boolean true, pointerNull]
  for event in cases do
    for position in [0, 1] do
      let region := source_value Extracted.«ir::body_events».Types.«Region».mk
        [.rawSlice eventType 88 2, .rawSlice referenceType 120 2, .boolean true, .signed .i32 2]
      let .done cursor after := evalExpr 100 extractedProgram sample
        (.call source.id [.value region, .value (.signed .i32 position), .value event])
        | throw (IO.userError "typed append trapped")
      unless cursor == .signed .i32 (position + 1) do throw (IO.userError "append cursor is incorrect")
      let .ok actual := readRawSliceIndex extractedProgram after eventType 88 2 position.toNat
        | throw (IO.userError "appended event became unreadable")
      unless actual == event do throw (IO.userError "appended event changed its payload")
      let .ok annotation := readRawSliceIndex extractedProgram after referenceType 120 2 position.toNat
        | throw (IO.userError "annotation became unreadable")
      unless annotation == invalid do throw (IO.userError "append did not reset the annotation")
      let other := 1 - position
      let .ok untouched := readRawSliceIndex extractedProgram after eventType 88 2 other.toNat
        | throw (IO.userError "neighboring event became unreadable")
      unless untouched == integer 0 do throw (IO.userError "append changed a neighboring event")
      let .ok untouchedType := readRawSliceIndex extractedProgram after referenceType 120 2 other.toNat
        | throw (IO.userError "neighboring annotation became unreadable")
      unless untouchedType == oldType do throw (IO.userError "append changed a neighboring annotation") : IO Unit)

end IREventStoreTests
