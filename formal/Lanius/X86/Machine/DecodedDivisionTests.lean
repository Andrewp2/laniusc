import Lanius.X86.Machine.DivisionEncoding

namespace Lanius.X86.Machine.DecodedDivisionTests

-- Decoding is not evidence that division can execute. This test fails if
-- the generic rule bypasses the divisor/range checks in `Step.divided`.
example (width : X86.Register.Width) (signed : Bool) (before : State) (divisor : Register)
    (loaded : CodeAt before.memory before.rip (divisionBytes width signed divisor)) : True := by
  fail_if_success
    have unchecked : Step before
        (execute (divisionInstruction width signed divisor)
          (divisionBytes width signed divisor).length before) := by
      apply Step.decoded _ loaded _ _ (division_decodes width signed divisor) rfl
      all_goals cases width <;> decide
  trivial

-- Legitimate division retains its actual success obligation and flags.
example (width : X86.Register.Width) (signed : Bool) (before : State) (divisor : Register)
    (loaded : CodeAt before.memory before.rip (divisionBytes width signed divisor))
    (success : DivisionSuccess width.bits signed before divisor quotient remainder) :
    Step before (before.divide width.bits divisor quotient remainder flags
      (divisionBytes width signed divisor).length) :=
  division_step width signed before _ divisor loaded quotient remainder flags success rfl

example (width : X86.Register.Width) (signed : Bool) (before : State) (divisor : Register)
    (loaded : CodeAt before.memory before.rip (divisionBytes width signed divisor))
    (zero : divisionByZero width.bits before divisor) : Fault before :=
  division_by_zero_fault width signed before divisor loaded zero

example (width : X86.Register.Width) (signed : Bool) (before : State) (divisor : Register)
    (loaded : CodeAt before.memory before.rip (divisionBytes width signed divisor))
    (overflow : divisionOverflow width.bits signed before divisor) : Fault before :=
  division_overflow_fault width signed before divisor loaded overflow

#print axioms division_step
#print axioms division_by_zero_fault
#print axioms division_overflow_fault

end Lanius.X86.Machine.DecodedDivisionTests
