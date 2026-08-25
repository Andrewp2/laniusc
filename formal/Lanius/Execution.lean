import Lanius.Semantics
import Lanius.Typing

namespace Lanius.Execution

open Lanius
open Lanius.Core

structure Executable where
  program : Program
  entrypoint : FunctionId

inductive EntrypointReturnType : Ty → Prop where
  | unit : EntrypointReturnType .unit
  | boolean : EntrypointReturnType (.scalar .bool)
  | signed : EntrypointReturnType (.scalar (.signed type))
  | unsigned : EntrypointReturnType (.scalar (.unsigned type))
  | character : EntrypointReturnType (.scalar .char)

def ExecutableWellFormed (executable : Executable) : Prop :=
  ∃ function,
    executable.program.function? executable.entrypoint = some function ∧
      function.parameters = [] ∧
      EntrypointReturnType function.returnType ∧
      Lanius.Typing.FunctionWellTyped executable.program function

inductive Result where
  | returned (value : Value) (state : Semantics.State)
  | exited (code : Int) (state : Semantics.State)
  | trapped (reason : Trap) (state : Semantics.State)
  | outOfFuel

/-- Program observation is a call to the selected zero-argument entrypoint.
    A host `exit` remains observably different from an ordinary returned value. -/
def run (fuel : Nat) (executable : Executable)
    (initial : Semantics.State) : Result :=
  match Semantics.evalExpr fuel executable.program initial
      (.call executable.entrypoint []) with
  | .done value state => .returned value state
  | .exited code state => .exited code state
  | .trapped reason state => .trapped reason state
  | .outOfFuel => .outOfFuel

end Lanius.Execution
