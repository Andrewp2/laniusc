module

public import Lanius.Open.F5.BorrowHoldsAt.Stmt
public import Lanius.Open.F5.BorrowRefHeld.Stmt

@[expose] public section

open Lanius.Mini

/-- `BorrowRefHeld`'s word through `HoldsAt.ref`. -/
theorem Lanius.Open.BorrowHoldsAt.red1 (h : Lanius.Open.BorrowRefHeld) : Lanius.Open.BorrowHoldsAt :=
  fun sx bud places st hp c p t code ty cell path v cprog prog depth env scratch homes agree hcode res runs read nt => by
    obtain ⟨env', ex, held, keep⟩ :=
      h sx bud places st hp c p t code ty cell path v cprog prog depth env scratch homes agree hcode res runs read nt
    exact ⟨env', ex, .ref held, keep⟩
