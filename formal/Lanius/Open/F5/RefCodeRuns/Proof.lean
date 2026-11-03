import Lanius.Open.F5.RefCodeRuns.Stmt
import Lanius.Open.F5.RefCodeWithin.Proof

open Lanius.Mini

/-- `RefCodeWithin` gives `Stmt.within`; then `compileStmt_correct` and
`compileStmt_stops`. -/
theorem Lanius.Open.RefCodeRuns.proof : Lanius.Open.RefCodeRuns := by
  intro prog base arities results code depth env heap stmt pos brk cont m hcode placed pc agree onHeap
  have within : stmt.within base arities results = true := by
    obtain ⟨load, store, place⟩ := Lanius.Open.RefCodeWithin.proof
    rcases hcode with ⟨ty, r, target, lt, fits, rfl⟩ | ⟨ty, r, slot, lt, fits, rfl⟩ |
        ⟨c, t, p, ty, h, tlt, slots, idx⟩
    · exact (load ty r target base arities results lt fits).1
    · exact (store ty r slot base arities results lt fits).1
    · exact (place c t p stmt ty base arities results h tlt slots idx).1
  exact ⟨fun _ exec => compileStmt_correct exec pos brk cont m placed pc agree onHeap within,
    fun _ stops => compileStmt_stops stops pos brk cont m placed pc agree onHeap within⟩
