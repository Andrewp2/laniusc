module

public import Lanius.Open.F5.CallRefsHeld.Red1
public import Lanius.Open.F5.CallRefsAgree.Proof

@[expose] public section

theorem Lanius.Open.CallRefsHeld.proof : Lanius.Open.CallRefsHeld :=
  Lanius.Open.CallRefsHeld.red1 Lanius.Open.CallRefsAgree.proof
