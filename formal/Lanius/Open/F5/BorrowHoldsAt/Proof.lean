module

public import Lanius.Open.F5.BorrowHoldsAt.Red1
public import Lanius.Open.F5.BorrowRefHeld.Proof

@[expose] public section

theorem Lanius.Open.BorrowHoldsAt.proof : Lanius.Open.BorrowHoldsAt :=
  Lanius.Open.BorrowHoldsAt.red1 Lanius.Open.BorrowRefHeld.proof
