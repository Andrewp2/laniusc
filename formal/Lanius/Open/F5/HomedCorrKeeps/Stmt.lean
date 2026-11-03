import Lanius.Mini.Refs.Homed
import Lanius.Mini.LowerStmt

open Lanius.Mini
open Lanius.Core (Value ValueProjection)
open Lanius.Semantics (State)

/-- **A call that writes through references.** A callee may change the
caller's homes' cells through the references it was passed: `Keeps places`
keeps every cell below the caller's next cell except the homes' and those a
view roots at. With the caller's locals restored, `HomedCorr` still holds:
the locals without homes keep their values (a viewed array's cell still holds
an array of in-range `i32`s), and the homes and reference locals still agree.
The homes themselves hold by the callee's `Homes` at its return. -/
def Lanius.Open.HomedCorrKeeps : Prop :=
  ∀ (sx : Statics) (places : List Addressed) (scope : List Binding) (frame : Nat → Nat) (c : RCtx)
    (st st' : State) (env : Env),
    HomedCorr sx places scope frame c st env → st.Fresh → Keeps places st.nextCell st st' →
    st'.locals = st.locals → HomedCorr sx places scope frame c st' env
