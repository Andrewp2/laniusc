import Lanius.Semantics.Typing.Cell
import Lanius.Semantics.Typing.Projection.Frame

namespace Lanius.Semantics.ProjectionTests

open Lanius.Core Lanius.Typing

private def item : StructDecl := { id := 6, fields := [.scalar .bool, .scalar .string] }
private def envelope : StructDecl := { id := 5, fields := [.array (.structure 6) 2, .scalar .char] }
private def program : Program := { structures := [envelope, item] }
private def root : Value := .structure 5 [
  .array [.structure 6 [.boolean false, .string "left"],
          .structure 6 [.boolean true, .string "right"]], .character 81]
private def path : List ValueProjection := [.field 0, .index 1, .field 0]
private def updated (replacement : Value) : Value := .structure 5 [
  .array [.structure 6 [.boolean false, .string "left"],
          .structure 6 [replacement, .string "right"]], .character 81]

private theorem rootTyped : ValueHasType program root (.structure 5) :=
  .structure envelope rfl (.cons
    (.array _ (.structure 6) rfl (.cons
      (.structure item rfl (.cons (.boolean false) (.cons (.string "left") .nil)))
      (.cons (.structure item rfl (.cons (.boolean true) (.cons (.string "right") .nil))) .nil)))
    (.cons (.character 81) .nil))
private theorem pathTyped : ProjectionHasType program (.structure 5) path (.scalar .bool) :=
  .field envelope rfl rfl (.index (by decide) (.field item rfl rfl .root))

example : ∃ value, projectedValue root path = .ok value ∧ ValueHasType program value (.scalar .bool) :=
  projectedValue_typed pathTyped rootTyped
example (flag : Bool) : ∃ result, replaceProjectedValue root path (.boolean flag) = .ok result ∧
    ValueHasType program result (.structure 5) ∧ projectedValue result path = .ok (.boolean flag) :=
  replaceProjectedValue_typed pathTyped rootTyped (.boolean flag)
example (flag : Bool) : replaceProjectedValue root path (.boolean flag) = .ok (updated (.boolean flag)) := rfl
example (flag : Bool) : projectedValue (updated (.boolean flag)) [.field 0, .index 0, .field 1] =
    .ok (.string "left") := rfl
example (flag : Bool) : projectedValue (updated (.boolean flag)) [.field 0, .index 1, .field 1] =
    .ok (.string "right") := rfl
example (flag : Bool) : projectedValue (updated (.boolean flag)) [.field 1] = .ok (.character 81) := rfl

private def before : State := (({} : State).bindLocal 3 root).bindLocal 8 (.string "untouched")
private def place : ResolvedPlace := { root := 0, projections := path, value := some (.boolean true) }

-- Derived from the general writer law, not an assumed successful write.
theorem cellWrite (flag : Bool) : ∃ after result,
    writeResolvedPlaceNative program before place (.boolean flag) = .ok after ∧
    ValueHasType program result (.structure 5) ∧
    readCellProjection after 0 path = .ok (.boolean flag) ∧
    after.cellEntry? 1 = some { id := 1, value := some (.string "untouched") } ∧
    readCellProjection after 0 [.field 0, .index 1, .field 1] = .ok (.string "right") ∧
    readCellProjection after 0 [.field 0, .index 0, .field 1] = .ok (.string "left") ∧
    after.locals = before.locals ∧ after.heap = before.heap ∧ after.world = before.world := by
  obtain ⟨after, result, written, present, typed, readBack, replaced, effect⟩ :=
    writeResolvedPlaceNative_typed (state := before) (place := place)
      rfl pathTyped rootTyped rfl (.boolean flag)
  exact ⟨after, result, written, typed, readBack, effect.otherCell (by decide) rfl,
    effect.projectedRead (Or.inr (.step (.step (.field (by decide))))) rfl replaced rfl,
    effect.projectedRead (Or.inr (.step (.index (by decide)))) rfl replaced rfl,
    effect.locals, effect.heap, effect.world⟩

example : ∃ value, readCellProjection before 0 path = .ok value ∧
    ValueHasType program value (.scalar .bool) := readCellProjection_typed pathTyped rootTyped rfl

-- Full place resolution, assignment and empty-view synchronization also agree.
private def assignment (flag : Bool) : Expr := .assign .set
  (.field (.index (.field (.local 3) 0) (.value (.unsigned .usize 1))) 0) (.value (.boolean flag))
example (flag : Bool) : ExprHasType program (Context.empty.bind 3 (.structure 5)) (assignment flag) .unit :=
  .assign (.field (.indexArray (.field (.local rfl) envelope rfl rfl)
    (.value (.unsigned .usize 1 (by decide))) (.unsigned .usize)) item rfl rfl)
    (.value (.boolean flag) rfl) .set
example (flag : Bool) : evalExpr 6 program before (assignment flag) =
    .done .unit { before with cells := replaceCell before.cells 0 (updated (.boolean flag)) } := rfl

-- Empty paths replace the entire root, including empty arrays.
example : ∃ result, replaceProjectedValue (.array []) [] (.array []) = .ok result ∧
    ValueHasType program result (.array (.scalar .bool) 0) ∧ projectedValue result [] = .ok (.array []) :=
  replaceProjectedValue_typed .root (.array [] (.scalar .bool) rfl .nil) (.array [] (.scalar .bool) rfl .nil)
example : ∃ after result, writeResolvedPlaceNative program before
    { root := 0, projections := [], value := some root } root = .ok after ∧
    after.cellEntry? 0 = some { id := 0, value := some result } ∧
    ValueHasType program result (.structure 5) ∧ readCellProjection after 0 [] = .ok root ∧
    replaceProjectedValue root [] root = .ok result ∧
    CellEffect before after 0 result :=
  writeResolvedPlaceNative_typed rfl .root rootTyped rfl rootTyped

-- Dynamic primitives reject malformed paths and invalid/uninitialized roots.
example : projectedValue root [.field 2] = .error .typeMismatch := rfl
example : projectedValue root [.field 0, .index 2] = .error .arrayBounds := rfl
example : replaceProjectedValue root [.field 0, .index 2] (.boolean false) = .error .arrayBounds := rfl
example : projectedValue root [.index 0] = .error .typeMismatch := rfl
example : projectedValue (.array []) [.index 0] = .error .arrayBounds := rfl
example : readCellProjection before 2 path = .error .invalidPointer := rfl
example : readCellProjection (({} : State).bindUninitialized 3) 0 path = .error .uninitializedLocal := rfl
example : writeResolvedPlace {} place (.boolean true) = .error .typeMismatch := rfl
example : writeResolvedPlace (({} : State).bindUninitialized 3) place (.boolean true) =
    .error .uninitializedLocal := rfl
example : ¬ ProjectionHasType program (.structure 5) [.field 2] (.scalar .bool) := by
  intro invalid
  cases invalid with
  | field declaration found fieldFound rest =>
    have same : declaration = envelope := Option.some.inj (found.symm.trans rfl)
    subst declaration
    cases fieldFound

-- Runtime writes deliberately do not re-typecheck replacements. The type premise
-- in the general theorem is necessary, not an assertion supplied by the writer.
example : replaceProjectedValue root path (.string "wrong") = .ok (updated (.string "wrong")) := rfl
example : ¬ ValueHasType program (updated (.string "wrong")) (.structure 5) := by
  intro typed
  obtain ⟨value, evaluated, valueTyped⟩ := projectedValue_typed pathTyped typed
  have same : value = .string "wrong" := Except.ok.inj (evaluated.symm.trans rfl)
  subst value
  cases valueTyped

#print axioms cellWrite

end Lanius.Semantics.ProjectionTests
