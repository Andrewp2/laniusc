import Lanius.Semantics.HeapFrame

namespace Lanius.Semantics

open Lanius Lanius.Core Lanius.Memory

/-- A representation is frameable only with a proof of its locality.
    Fixed logical contents and coordinates are parameters, never rewritten by framing. -/
structure Rep where
  footprint : Footprint
  holds : Heap → Prop
  stable : ∀ {before after}, HeapFrame footprint before after → holds before → holds after

namespace Rep

theorem frame (rep : Rep) (represented : rep.holds before) (effect : HeapFrame observed before after)
    (covered : Footprint.Subset rep.footprint observed) : rep.holds after :=
  rep.stable (effect.restrict covered) represented

def and (left right : Rep) : Rep where
  footprint := left.footprint.union right.footprint
  holds heap := left.holds heap ∧ right.holds heap
  stable effect valid :=
    ⟨left.stable (effect.restrict ⟨fun _ h => Or.inl h, fun _ h => Or.inl h, fun _ h => Or.inl h⟩) valid.1,
      right.stable (effect.restrict ⟨fun _ h => Or.inr h, fun _ h => Or.inr h, fun _ h => Or.inr h⟩) valid.2⟩

/-- Index by a bounded type when only a finite logical prefix is represented. -/
def all (family : ι → Rep) : Rep where
  footprint := .iUnion (fun i => (family i).footprint)
  holds heap := ∀ i, (family i).holds heap
  stable effect valid i := (family i).stable
    (effect.restrict ⟨fun _ h => ⟨i, h⟩, fun _ h => ⟨i, h⟩, fun _ h => ⟨i, h⟩⟩) (valid i)

def native (fuel : Nat) (program : Program) (type : Ty) (base : Address) (value : Value) (size : Nat) : Rep where
  footprint := ⟨fun p => base + 8 - size ≤ p ∧ p < base + 8 - size + size, fun _ => False, fun _ => False⟩
  holds heap := NativeSnapshot fuel program heap type base value size
  stable effect snapshot := effect.snapshot snapshot (fun _ lower upper => ⟨lower, upper⟩)

/-- Writable/readable room does not assert preservation of its old contents. -/
def readable (base : Address) (size : Nat) : Rep where
  footprint := .empty
  holds heap := heap.Readable base size
  stable effect room := effect.readable base size room

/-- The allocation selected by this address retains shape, not ownership. -/
def block (pointer : Address) (shape : Block) : Rep where
  footprint := ⟨fun _ => False, fun p => p = pointer, fun _ => False⟩
  holds heap := ∃ actual, heap.containingBlock? pointer = some actual ∧ blockShape actual = shape
  stable effect valid := by
    obtain ⟨actual, found, same⟩ := valid
    obtain ⟨current, located, retained⟩ := effect.blocks pointer actual rfl found
    exact ⟨current, located, retained.trans same⟩

/-- An explicit allocator-ownership observation; borrowing an owned target
    cannot frame this fact unchanged. -/
def owned (pointer : Address) (ownership : Bool) : Rep where
  footprint := ⟨fun _ => False, fun _ => False, fun p => p = pointer⟩
  holds heap := ∃ actual, heap.containingBlock? pointer = some actual ∧ actual.owned = ownership
  stable effect valid := by
    obtain ⟨actual, found, same⟩ := valid
    obtain ⟨current, located, retained⟩ := effect.ownership pointer actual rfl found
    exact ⟨current, located, retained.trans same⟩

/-- An actual selected borrow establishes the new observation, regardless
    of whether the original allocation was already borrowed. -/
theorem borrowed {heap : Heap} {pointer : Address} {actual : Block}
    (found : heap.containingBlock? pointer = some actual) :
    (owned pointer false).holds (heap.borrowBlock actual.base) :=
  ⟨{ actual with owned := false }, Heap.containingBlock?_borrowSelected found, rfl⟩

end Rep

/-- The inline scalar cases used by native body events. In particular this
    does not assert confinement for strings or other indirect values. -/
theorem NativeSnapshot.scalarOfRead
    (inline : type = .scalar .bool ∨ type = .scalar (.signed .i32))
    (read : readNativeValue (fuel + 1) program heap type address = .ok value) :
    NativeSnapshot (fuel + 1) program heap type address value 8 := by
  rcases inline with rfl | rfl <;> intro other within
  all_goals
    cases loaded : heap.loadBytes address 4 with
    | error reason =>
        rw [readNativeValue] at read
        simp only [loadNatLE, loaded] at read
        dsimp only [Bind.bind, Except.bind, Pure.pure, Except.pure] at read
        cases read
    | ok bytes =>
        have retained := within address 4 bytes (by omega) (by omega) loaded
        simpa only [readNativeValue, loadNatLE, loaded, retained] using read

private theorem enumTagOfRead {id : TypeId}
    (declaration : program.enumeration? id = some enumeration)
    (read : readNativeValue (fuel + 1) program heap (.enumeration id) address =
      .ok (.enumeration id ordinal values)) :
    ∃ bytes, heap.loadBytes address 4 = .ok bytes ∧ decodeNatLE bytes = ordinal := by
  cases loaded : heap.loadBytes address 4 with
  | error reason =>
      rw [readNativeValue, declaration] at read
      simp only [loadNatLE, loaded] at read
      dsimp only [Bind.bind, Except.bind, Pure.pure, Except.pure] at read
      cases read
  | ok bytes =>
      rw [readNativeValue, declaration] at read
      simp only [loadNatLE, loaded] at read
      dsimp only [Bind.bind, Except.bind, Pure.pure, Except.pure] at read
      cases selected : enumeration.variants[decodeNatLE bytes]? with
      | none => rw [selected] at read; cases read
      | some types =>
          rw [selected] at read
          dsimp only at read
          split at read
          · cases read
          · have same := Except.ok.inj read
            exact ⟨bytes, rfl, congrArg (fun value : Value =>
              match value with | .enumeration _ tag _ => tag | _ => 0) same⟩

/-- Empty enum values depend only on the native four-byte discriminant. -/
theorem NativeSnapshot.enumEmptyOfRead {id : TypeId}
    (declaration : program.enumeration? id = some enumeration)
    (variant : enumeration.variants[ordinal]? = some [])
    (read : readNativeValue (fuel + 1) program heap (.enumeration id) address =
      .ok (.enumeration id ordinal [])) :
    NativeSnapshot (fuel + 1) program heap (.enumeration id) address (.enumeration id ordinal []) 8 := by
  obtain ⟨bytes, loaded, tag⟩ := enumTagOfRead declaration read
  intro other within
  have retained := within address 4 bytes (by omega) (by omega) loaded
  rw [readNativeValue, declaration]
  simp only [loadNatLE, retained]
  dsimp only [Bind.bind, Except.bind, Pure.pure, Except.pure]
  rw [tag, variant]
  rfl

/-- Only a single inline bool/i32 payload is admitted by this confinement
    rule. Its payload word is the one below the tag, as the native reader has it. -/
theorem NativeSnapshot.enumSingleOfRead {id : TypeId}
    (declaration : program.enumeration? id = some enumeration)
    (variant : enumeration.variants[ordinal]? = some [type])
    (inline : type = .scalar .bool ∨ type = .scalar (.signed .i32))
    (above : 8 ≤ address)
    (read : readNativeValue (fuel + 2) program heap (.enumeration id) address =
      .ok (.enumeration id ordinal [value])) :
    NativeSnapshot (fuel + 2) program heap (.enumeration id) address
      (.enumeration id ordinal [value]) 16 := by
  obtain ⟨bytes, loaded, tag⟩ := enumTagOfRead declaration read
  have payload : readNativeValue (fuel + 1) program heap type (address - 8) = .ok value := by
    rw [readNativeValue, declaration] at read
    simp only [loadNatLE, loaded] at read
    dsimp only [Bind.bind, Except.bind, Pure.pure, Except.pure] at read
    rw [tag, variant] at read
    simp [NativeLayout.wordBytes, List.range_succ, wordBelow, above] at read
    cases parsed : readNativeValue (fuel + 1) program heap type (address - 8) with
    | error reason =>
        have impossible : (Except.error reason : Except Trap Value) =
            .ok (Value.enumeration id ordinal [value]) := by
          simpa only [parsed, Functor.map, Except.map] using read
        cases impossible
    | ok field =>
        have same : field = value := by simpa [parsed, Functor.map, Except.map] using read
        simpa only [same] using parsed
  have snapshot := NativeSnapshot.scalarOfRead inline payload
  intro other within
  have retained := within address 4 bytes (by omega) (by omega) loaded
  have payload := snapshot other (within.narrow (by omega) (by omega))
  rw [readNativeValue, declaration]
  simp only [loadNatLE, retained]
  dsimp only [Bind.bind, Except.bind, Pure.pure, Except.pure]
  rw [tag, variant]
  simp [NativeLayout.wordBytes, List.range_succ, wordBelow, above]
  simp only [payload, Functor.map, Except.map]

#print axioms Rep.frame
#print axioms Rep.native
#print axioms Rep.block
#print axioms Rep.owned
#print axioms Rep.borrowed
#print axioms NativeSnapshot.scalarOfRead
#print axioms NativeSnapshot.enumEmptyOfRead
#print axioms NativeSnapshot.enumSingleOfRead

end Lanius.Semantics
