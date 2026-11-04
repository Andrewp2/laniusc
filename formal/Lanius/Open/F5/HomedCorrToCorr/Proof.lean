import Lanius.Open.F5.HomedCorrToCorr.Stmt

open Lanius.Mini

theorem Lanius.Open.HomedCorrToCorr.proof : Lanius.Open.HomedCorrToCorr :=
  fun _ _ _ _ _ _ _ hc apart =>
    ⟨hc.locals, apart, fun b mem => hc.values b mem fun x xm => apart x xm b mem,
      fun v vm b mem nv => hc.unviewed v vm b mem (fun x xm => apart x xm b mem) nv,
      fun b mem n hty => hc.viewed b mem (fun x xm => apart x xm b mem) n hty⟩
