module

public import Lanius.Open.F5.SourceRefsCorrect.Stmt

@[expose] public section

open Lanius.Mini

/-- While `compileSource` rejects every reference form, this is
`compileSource_correct`. -/
theorem Lanius.Open.SourceRefsCorrect.proof : Lanius.Open.SourceRefsCorrect := by
  intro sx sp binary compiled f func found args bits typed bitsLen fuel v final heap start zero small silent runs
    fits frameRoom statics ofSp
  exact compileSource_correct compiled found typed bitsLen start zero small silent runs fits frameRoom statics ofSp
