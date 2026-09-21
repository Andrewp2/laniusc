import Lanius.X86.LocalExpressionCheck

namespace Lanius.X86.LocalExpressionCheckTests

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.LocalExpressionCheck

#check preserves
#check parameter_function
#check parameter_supported

example {coreBefore : Semantics.State} {machineBefore : Machine.State}
    (environment : Environment coreBefore machineBefore)
    {source : Core.Expr} {emitted : List UInt8}
    {checked : Supported environment source emitted}
    (accepted : check environment source emitted = some checked) :
    source = .local environment.id ∧ emitted = environment.location.bodyBytes :=
  (check_sound accepted).2

example {coreBefore : Semantics.State} {machineBefore : Machine.State}
    (environment : Environment coreBefore machineBefore)
    (program : Program) {source : Core.Expr} {emitted : List UInt8}
    (checked : Supported environment source emitted)
    (loaded : CodeAt machineBefore.memory machineBefore.rip emitted) :
    ∃ after, Executes program coreBefore
        (.returnValue (some source))
        (.returned (some (.signed .i32 environment.value))) coreBefore ∧
      Step machineBefore after :=
  let result := preserves checked program loaded
  ⟨result.choose, result.choose_spec.1, result.choose_spec.2.1⟩

end Lanius.X86.LocalExpressionCheckTests
