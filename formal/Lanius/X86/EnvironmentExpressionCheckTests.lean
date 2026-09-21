import Lanius.X86.EnvironmentExpressionCheck

namespace Lanius.X86.EnvironmentExpressionCheckTests

open Lanius Lanius.Core
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.DynamicComparison
open Lanius.X86.EnvironmentExpressionCheck

private def source : Core.Expr := .binary .notEqual (.local 1) (.local 2)
private def bytes := localNotEqualBytes (.frame 2) (.frame 3) 4

example : (check source bytes (.frame 2) (.frame 3) 4).isSome := by decide

example : (check source (bytes.set 0 0) (.frame 2) (.frame 3) 4).isNone := by decide

end Lanius.X86.EnvironmentExpressionCheckTests
