import Lanius.Faithful.SelfPre.HB
import Lanius.Mini.Frontend.P.readCountedBytes

open Lanius.Mini
open Lanius.Faithful.SelfPre

/-- The files `readCountedFiles` reads from fewer than `2 ^ 31` words are
lower than `2 ^ 40` (a token's height counts its start, `SelfPre/HB`). -/
def Lanius.Open.ReadFilesHeight : Prop :=
  ∀ (W : List (BitVec 32)) (r : FilesRead), readCountedFiles W = some r → W.length < 2 ^ 31 →
    hb r.files < 2 ^ 40
