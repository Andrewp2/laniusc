module

public import Lanius.Faithful.SelfPre.HB
public import Lanius.Mini.Frontend.P.fileLexed
public import Lanius.Mini.Frontend.P.filesAfter
public import Lanius.Mini.Frontend.P.readCountedBytes
public import Lanius.Mini.Frontend.P.readCountedFiles
public import Lanius.Mini.Frontend.P.readFile
public import Lanius.Mini.Frontend.P.readFileEnd
public import Lanius.Mini.Frontend.P.readFileParents
public import Lanius.Mini.Frontend.P.readFiles

@[expose] public section

open Lanius.Mini
open Lanius.Faithful.SelfPre

/-- The files `readCountedFiles` reads from fewer than `2 ^ 31` words are
lower than `2 ^ 40` (a token's height counts its start, `SelfPre/HB`). -/
def Lanius.Open.ReadFilesHeight : Prop :=
  ∀ (W : List (BitVec 32)) (r : FilesRead), readCountedFiles W = some r → W.length < 2 ^ 31 →
    hb r.files < 2 ^ 40
