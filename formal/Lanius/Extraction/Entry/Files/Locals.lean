import Lanius.Extraction.Entry.Files.Loop

namespace Lanius.Extraction.Entry.Files
open Lanius.Core Lanius.Semantics

/-- A live pointer, slice, or string cannot share either signed cursor's
cell. Derive that separation from actual values when carrying locals into
the final suffix/packing phase. -/
theorem Result.carriedNonScalar {id : VarId} {value : Value}
    (result : Result checked context countId count sources outputRoot before completion after)
    (finished : completion = .next)
    (index : before.local? checked.argument = some (.signed .i32 indexValue))
    (position : before.local? checked.emitStage.position = some (.signed .i32 positionValue))
    (carried : File.Carried checked.pipeline checked.syntaxStage checked.resultsStage id)
    (read : before.local? id = some value)
    (notArray : ∀ elements, value ≠ .array elements)
    (notCursor : ∀ scalar, value ≠ .signed .i32 scalar) : after.local? id = some value := by
  apply result.carriedLocals finished id value carried read notArray
  · intro same
    have equal : before.local? id = before.local? checked.argument := by simp only [State.local?, same]
    exact notCursor _ (Option.some.inj (read.symm.trans (equal.trans index)))
  · intro same
    have equal : before.local? id = before.local? checked.emitStage.position := by simp only [State.local?, same]
    exact notCursor _ (Option.some.inj (read.symm.trans (equal.trans position)))

end Lanius.Extraction.Entry.Files
