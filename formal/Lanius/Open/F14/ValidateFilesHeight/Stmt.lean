import Lanius.Faithful.SelfPre.HB
import Lanius.Mini.Frontend.P.grammarPart13
import Lanius.Mini.Frontend.P.wideLeftStmt

open Lanius.Mini
open Lanius.Faithful.SelfPre

/-- The trees `validateFiles` builds with the self program's grammar from files
lower than `2 ^ 40` are lower than `2 ^ 61`: `build_files`'s height bound in
the front end. -/
def Lanius.Open.ValidateFilesHeight : Prop :=
  ∀ (fs : List FileInput) (ts : List CTree), validateFiles grammar fs = some ts → hb fs < 2 ^ 40 →
    hb ts < 2 ^ 61
