import Lanius.Open.F5.KeepsConsAbove.Stmt

open Lanius.Mini

theorem Lanius.Open.KeepsConsAbove.proof : Lanius.Open.KeepsConsAbove :=
  fun x _ _ _ _ keeps above =>
    ⟨fun c below apart unrooted => keeps.cells c below (fun y my => by
        rcases List.mem_cons.mp my with rfl | my
        · omega
        · exact apart y my) unrooted,
      keeps.next, keeps.views, keeps.persist, keeps.arrays⟩
