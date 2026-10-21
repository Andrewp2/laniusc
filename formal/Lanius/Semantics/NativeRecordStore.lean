import Lanius.Semantics.NativeStore

namespace Lanius.Semantics

open Lanius.Core Lanius.Memory

variable {fuel size : Nat} {program : Program} {type : Nat → Ty} {value : Nat → Value}
  {offset width : Nat → Nat} {values : List Value} {declarationData : StructDecl}

/-- One rule for an arbitrary ordered set of native fields. The premise for
    each field is a proved codec, not an assumed successful write. -/
theorem storeNativeFields (count : Nat)
    (codecs : ∀ index, index < count → NativeStoreSpec fuel program (type index) (value index) (width index))
    (bounds : ∀ index, index < count → offset index + width index ≤ size)
    (ordered : ∀ left right, left < right → right < count → offset left + width left ≤ offset right) :
    ∀ state heap address, heap.Readable address size → HeapBlockBasesUnique heap →
      ∃ after, (List.range count).foldlM (fun current index =>
        writeNativeValue fuel program state current (type index) (address + offset index) (value index)) heap = .ok after ∧
        (∀ index, index < count → NativeSnapshot fuel program after (type index)
          (address + offset index) (value index) (width index)) ∧ HeapRegionWrite heap after address size := by
  induction count with
  | zero =>
      intro state heap address _ unique
      exact ⟨heap, rfl, fun _ impossible => False.elim (Nat.not_lt_zero _ impossible), HeapRegionWrite.refl heap unique⟩
  | succ count ih =>
      intro state heap address readable unique
      obtain ⟨middle, prefixRun, snapshots, prefixEffect⟩ := ih
        (fun index inside => codecs index (by omega)) (fun index inside => bounds index (by omega))
        (fun left right before inside => ordered left right before (by omega)) state heap address readable unique
      obtain ⟨after, last, snapshot, lastEffect⟩ := codecs count (by omega) state middle (address + offset count)
        ((prefixEffect.readable _ _ readable).subrange (bounds count (by omega))) prefixEffect.unique
      refine ⟨after, ?_, ?_, prefixEffect.trans (lastEffect.enlarge (by omega) (by have := bounds count (by omega); omega))⟩
      · rw [List.range_succ, List.foldlM_append, prefixRun]
        simp only [List.foldlM, Bind.bind, Except.bind]
        rw [last]
        rfl
      · intro index inside
        by_cases earlier : index < count
        · exact (snapshots index earlier).afterWrite lastEffect (Or.inl (by
            have := ordered index count earlier (by omega); omega))
        · have same : index = count := by omega
          subst index
          exact snapshot

private theorem foldlM_congr_on (indices : List Nat) (left right : Heap → Nat → Except Trap Heap)
    (same : ∀ index ∈ indices, ∀ current, left current index = right current index) (heap : Heap) :
    indices.foldlM left heap = indices.foldlM right heap := by
  induction indices generalizing heap with
  | nil => rfl
  | cons index rest ih =>
      simp only [List.foldlM_cons]
      rw [same index (by simp)]
      congr 1
      funext current
      exact ih (fun item member => same item (by simp [member])) current

private theorem mapM_range_of_get (values : List Value) {read : Nat → Except Trap Value} (found : ∀ index, index < values.length →
    read index = .ok ((values[index]?).getD .unit)) :
    (List.range values.length).mapM read = .ok values := by
  have all : ∀ indices : List Nat, (∀ index ∈ indices, index < values.length) →
      indices.mapM read = .ok (indices.map fun index => (values[index]?).getD .unit) := by
    intro indices inside
    induction indices with
    | nil => rfl
    | cons index rest ih =>
        simp only [List.mapM_cons, found index (inside index (by simp)),
          ih (fun member present => inside member (by simp [present])), List.map_cons]
        rfl
  rw [all _ (fun index member => List.mem_range.mp member)]
  congr 1
  apply List.ext_getElem
  · simp
  · intro index left right
    simp only [List.getElem_map, List.getElem_range, List.getElem?_eq_getElem (by simpa using left), Option.getD_some]

/-- Construct an immutable record snapshot from its original field snapshots.
    This is the same read-back argument used by the native store contract. -/
theorem NativeSnapshot.record {id : TypeId}
    (declaration : program.structure? id = some declarationData)
    (length : values.length = declarationData.fields.length)
    (locations : ∀ index, index < values.length → NativeLayout.structureFieldOffset? program id index = some (offset index))
    (bounds : ∀ index, index < values.length → offset index + width index ≤ size)
    (snapshots : ∀ index, index < values.length → NativeSnapshot fuel program heap
      ((declarationData.fields[index]?).getD .unit) (address + offset index)
      ((values[index]?).getD .unit) (width index)) :
    NativeSnapshot (fuel + 1) program heap (.structure id) address (.structure id values) size := by
  have types : ∀ index, index < values.length → declarationData.fields[index]? =
      some ((declarationData.fields[index]?).getD .unit) := by
    intro index inside
    rw [List.getElem?_eq_getElem (by omega)]
    rfl
  intro other reads
  have decoded : ∀ index, index < values.length → readNativeValue fuel program other
      ((declarationData.fields[index]?).getD .unit) (address + offset index) = .ok ((values[index]?).getD .unit) := by
    intro index inside
    exact snapshots index inside other (reads.narrow (by omega) (by have := bounds index inside; omega))
  simp only [readNativeValue, declaration]
  rw [← length]
  have fields := mapM_range_of_get values (read := fun index => do
    let some fieldType := declarationData.fields[index]? | .error .typeMismatch
    let some fieldOffset := NativeLayout.structureFieldOffset? program id index | .error .typeMismatch
    readNativeValue fuel program other fieldType (address + fieldOffset)) (by
      intro index inside
      rw [types index inside, locations index inside]
      exact decoded index inside)
  exact congrArg (fun result : Except Trap (List Value) => result.bind fun members =>
    Except.ok (Value.structure id members)) fields

/-- The complete actual native record store/read-back contract. Metadata
    identifies its fields; each field codec and the static layout are proved
    by callers. Arbitrary arity and field widths use the same induction. -/
theorem NativeStoreSpec.record {id : TypeId}
    (declaration : program.structure? id = some declarationData)
    (length : values.length = declarationData.fields.length)
    (locations : ∀ index, index < values.length → NativeLayout.structureFieldOffset? program id index = some (offset index))
    (bounds : ∀ index, index < values.length → offset index + width index ≤ size)
    (ordered : ∀ left right, left < right → right < values.length → offset left + width left ≤ offset right)
    (codecs : ∀ index, index < values.length → NativeStoreSpec fuel program
      ((declarationData.fields[index]?).getD .unit) ((values[index]?).getD .unit) (width index)) :
    NativeStoreSpec (fuel + 1) program (.structure id) (.structure id values) size := by
  intro state heap address readable unique
  obtain ⟨after, written, snapshots, effect⟩ := storeNativeFields values.length codecs bounds ordered state heap address readable unique
  have types : ∀ index, index < values.length → declarationData.fields[index]? =
      some ((declarationData.fields[index]?).getD .unit) := by
    intro index inside
    rw [List.getElem?_eq_getElem (by omega)]
    rfl
  have valuesFound : ∀ index, index < values.length → values[index]? = some ((values[index]?).getD .unit) := by
    intro index inside
    rw [List.getElem?_eq_getElem inside]
    rfl
  refine ⟨after, ?_, ?_, effect⟩
  · simp only [writeNativeValue, declaration, bne_self_eq_false, Bool.false_eq_true,
      length, ↓reduceIte]
    have steps : ∀ current index, index < values.length →
        (do
          let some fieldType := declarationData.fields[index]? | .error .typeMismatch
          let some fieldValue := values[index]? | .error .typeMismatch
          let some fieldOffset := NativeLayout.structureFieldOffset? program id index | .error .typeMismatch
          writeNativeValue fuel program state current fieldType (address + fieldOffset) fieldValue) =
        writeNativeValue fuel program state current ((declarationData.fields[index]?).getD .unit)
          (address + offset index) ((values[index]?).getD .unit) := by
      intro current index inside
      rw [types index inside, valuesFound index inside, locations index inside]
      rfl
    rw [← length]
    exact (foldlM_congr_on _ _ _ (fun index member current => steps current index (List.mem_range.mp member)) heap).trans written
  · exact NativeSnapshot.record declaration length locations bounds snapshots

end Lanius.Semantics
