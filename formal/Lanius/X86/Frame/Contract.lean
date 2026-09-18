import Lanius.X86.Frame.Source
import Lanius.Extraction.Source.Call

namespace Lanius.X86.Frame

open Lanius.Core Lanius.Semantics Lanius.Properties Lanius.CallContracts

theorem displacement_spec (checked : CheckedDisplacement program) (slot : Nat) (bounded : slot ≤ 1048576) :
    checked.Spec [.signed .i32 slot] (.signed .i32 (displacement slot)) := by
  apply checked.specPure rfl
  intro before reads
  exact executesSequenceReturned (executesReturnValue (displacement_evaluates program.core slot bounded (reads 0 (by simp))))

end Lanius.X86.Frame
