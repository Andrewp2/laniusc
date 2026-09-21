import Lanius.X86.EnvironmentConditionalCheck

namespace Lanius.X86.EnvironmentConditionalCheckTests

open Lanius Lanius.Core
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.DynamicComparison
open Lanius.X86.EnvironmentConditionalCheck

private def condition : Core.Expr := .binary .notEqual (.local 1) (.local 2)
private def thenBranch : Stmt := .expression (.value (.signed .i32 1))
private def elseBranch : Stmt := .expression (.value (.signed .i32 0))
private def source : Stmt := .ifThenElse condition thenBranch elseBranch
private def conditionBytes := localNotEqualBytes (.frame 2) (.frame 3) 4
private def thenBytes := immediateBytes .w32 resultRegister (BitVec.ofNat 32 1) 0
private def elseBytes := immediateBytes .w32 resultRegister (BitVec.ofNat 32 0) 0
private def emitted := conditionBytes ++ Machine.conditionalBytes thenBytes elseBytes

example : (check source emitted conditionBytes thenBytes elseBytes (.frame 2) (.frame 3) 4).isSome := by
  decide

end Lanius.X86.EnvironmentConditionalCheckTests
