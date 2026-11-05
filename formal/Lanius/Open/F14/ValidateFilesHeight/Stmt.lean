module

public import Lanius.Faithful.SelfPre.HB
public import Lanius.Mini.Frontend.P.Inline_attachAfter
public import Lanius.Mini.Frontend.P.Inline_attachTerm
public import Lanius.Mini.Frontend.P.Inline_genericCloseAt
public import Lanius.Mini.Frontend.P.grammar
public import Lanius.Mini.Frontend.P.grammarPart13
public import Lanius.Mini.Frontend.P.grammarPart14
public import Lanius.Mini.Frontend.P.grammarPart15
public import Lanius.Mini.Frontend.P.grammarPart16
public import Lanius.Mini.Frontend.P.build
public import Lanius.Mini.Frontend.P.buildChecked
public import Lanius.Mini.Frontend.P.buildClosed
public import Lanius.Mini.Frontend.P.buildCollected
public import Lanius.Mini.Frontend.P.buildFiles
public import Lanius.Mini.Frontend.P.buildMono
public import Lanius.Mini.Frontend.P.consRoot
public import Lanius.Mini.Frontend.P.filesFuel
public import Lanius.Mini.Frontend.P.frontEnd
public import Lanius.Mini.Frontend.P.frontEndFiles
public import Lanius.Mini.Frontend.P.lxDigit
public import Lanius.Mini.Frontend.P.lxIdentContinue
public import Lanius.Mini.Frontend.P.lxIdentStart
public import Lanius.Mini.Frontend.P.lxSpace
public import Lanius.Mini.Frontend.P.untypedRejected
public import Lanius.Mini.Frontend.P.validateFiles
public import Lanius.Mini.Frontend.P.wideLeftFuncs
public import Lanius.Mini.Frontend.P.wideLeftStmt

@[expose] public section

open Lanius.Mini
open Lanius.Faithful.SelfPre

/-- The trees `validateFiles` builds with the self program's grammar from files
lower than `2 ^ 40` are lower than `2 ^ 61`: `build_files`'s height bound in
the front end. -/
def Lanius.Open.ValidateFilesHeight : Prop :=
  ∀ (fs : List FileInput) (ts : List CTree), validateFiles grammar fs = some ts → hb fs < 2 ^ 40 →
    hb ts < 2 ^ 61
