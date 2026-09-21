import Lanius.Compiler.BackendBoundary

namespace Lanius.Compiler.BackendBoundaryTests

open Lanius Lanius.Core
open Lanius.Compiler.BackendBoundary

private def literalWords : List Int :=
  [2, 64, 7, 0, 0, 1, 11, 1, 64, 7, 1, 0, 5, 10, 1, 0, 1, 42]

private def parameterWords : List Int :=
  [2, 64, 7, 0, 0, 1, 12, 1, 64, 7, 1, 1, 4, 3, 1, 10, 1, 1, 3]

/- These executable checks exercise the trusted boundary with one accepted
   literal and two rejected emissions (a parameterized entrypoint and a
   trailing word). -/
#eval (check literalWords).isOk -- true
#eval (check parameterWords).isOk -- false
#eval (check (literalWords ++ [99])).isOk -- false

example : ∀ {checked : Checked literalWords}, check literalWords = .ok checked →
    Typing.ProgramWellTyped checked.executable.program := by
  intro checked accepted
  exact (check_sound accepted).1

end Lanius.Compiler.BackendBoundaryTests
