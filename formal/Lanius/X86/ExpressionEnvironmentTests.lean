import Lanius.X86.ExpressionEnvironment

namespace Lanius.X86.ExpressionEnvironmentTests

open Lanius Lanius.Core Lanius.Semantics
open Lanius.X86 Lanius.X86.Machine
open Lanius.X86.ExpressionEnvironment

example (environment : Environment coreBefore machineBefore) (entry : Entry coreBefore machineBefore) :
    (environment.extend entry).Relates entry.id entry.location entry.value :=
  Environment.extend_relates environment entry

example (environment : Environment coreBefore machineBefore) (entry : Entry coreBefore machineBefore)
    {id : VarId} {location : Location} {value : Int} (different : id ≠ entry.id)
    (related : environment.Relates id location value) :
    (environment.extend entry).Relates id location value :=
  Environment.extend_preserves environment entry different related

end Lanius.X86.ExpressionEnvironmentTests
