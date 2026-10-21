import Lanius.Semantics.Typing.Pattern
import Lanius.Semantics.Typing.Parameters

namespace Lanius.Semantics.TypingTests

open Lanius Lanius.Core Lanius.Typing

private def outer : EnumDecl := { id := 5, variants := [[], [.scalar .bool, .enumeration 6]] }
private def inner : EnumDecl := { id := 6, variants := [[], [.scalar .string]] }
private def program : Program := { enumerations := [outer, inner] }
private def payload : Value := .enumeration 5 1 [.boolean false, .enumeration 6 1 [.string "hi"]]
private def nested (first second : VarId) : Pattern :=
  .enumVariant 5 1 [.bind first, .enumVariant 6 1 [.bind second]]
private def declarations (first second : VarId) : List (VarId × Ty) :=
  [(first, .scalar .bool), (second, .scalar .string)]
private def bindings (first second : VarId) : List (VarId × Value) :=
  [(first, .boolean false), (second, .string "hi")]

private theorem payloadTyped : ValueHasType program payload (.enumeration 5) :=
  .enumeration outer rfl rfl
    (.cons (.boolean false) (.cons (.enumeration inner rfl rfl (.cons (.string "hi") .nil)) .nil))

private theorem nestedTyped (first second : VarId) :
    PatternHasType program (nested first second) (.enumeration 5) (declarations first second) :=
  .enumVariant outer rfl rfl
    (.cons (.bind first) (.cons (.enumVariant inner rfl rfl (.cons (.bind second) .nil)) .nil))

-- Both nominal identity and payload shape matter, including nested mismatches.
example : matchPattern (nested 7 9) payload = some (bindings 7 9) := rfl
example : matchPattern (nested 7 9) (.enumeration 8 1 []) = none := rfl
example : matchPattern (nested 7 9) (.enumeration 5 0 []) = none := rfl
example : matchPattern (nested 7 9) (.enumeration 5 1 [.boolean false]) = none := rfl
example : matchPattern (nested 7 9)
    (.enumeration 5 1 [.boolean false, .enumeration 6 1 [.string "hi"], .unit]) = none := rfl
example : matchPattern (nested 7 9)
    (.enumeration 5 1 [.boolean false, .enumeration 6 0 []]) = none := rfl
example : matchPattern (nested 7 9)
    (.enumeration 5 1 [.boolean false, .enumeration 6 1 []]) = none := rfl
example : matchPattern (nested 7 9) (.boolean false) = none := rfl

example : BindingsHaveTypes program (bindings 7 9) (declarations 7 9) :=
  matchPattern_types (nestedTyped 7 9) payloadTyped rfl
example : BindingsHaveTypes program [] [] :=
  matchPattern_types (.wildcard : PatternHasType program .wildcard (.enumeration 5) []) payloadTyped rfl
example : BindingsHaveTypes program [(3, .boolean true)] [(3, .scalar .bool)] :=
  matchPattern_types (.bind 3) (.boolean true) rfl
example : BindingsHaveTypes program [] [] :=
  matchPattern_types (.literal (.boolean true)) (.boolean true) rfl
example : matchPattern (.literal (.boolean true)) (.boolean false) = none := rfl

private def caller : State := (({} : State).bindLocal 7 (.character 81)).bindLocal 11 (.boolean true)
private def context : Context := (Context.empty.bind 7 (.scalar .char)).bind 11 (.scalar .bool)
private theorem emptyFormed : ({} : State).CellsWellFormed := by simp [State.CellsWellFormed]
private theorem callerFormed : caller.CellsWellFormed :=
  (emptyFormed.bindLocal 7 (.character 81)).bindLocal 11 (.boolean true)
private theorem callerTyped : caller.LocalsHaveTypes program context :=
  ((State.LocalsHaveTypes.empty {} program).bindLocal emptyFormed (.character 81)).bindLocal
    (emptyFormed.bindLocal 7 (.character 81)) (.boolean true)

-- Installation changes the shadowed variable's type, retaining unrelated locals.
private theorem installed (first second : VarId) :
    (caller.bindLocals (bindings first second)).LocalsHaveTypes program
      (context.bindAll (declarations first second)) :=
  matchPattern_locals (nestedTyped first second) payloadTyped rfl callerTyped callerFormed

example : ∃ value, evalExpr 1 program (caller.bindLocals (bindings 7 9)) (.local 9) =
      .done value (caller.bindLocals (bindings 7 9)) ∧ ValueHasType program value (.scalar .string) :=
  (installed 7 9).evalLocal rfl 0
example : ∃ value, (caller.bindLocals (bindings 7 9)).local? 7 = some value ∧
    ValueHasType program value (.scalar .bool) := installed 7 9 7 _ rfl
example : ∃ value, (caller.bindLocals (bindings 7 9)).local? 11 = some value ∧
    ValueHasType program value (.scalar .bool) := installed 7 9 11 _ rfl

-- Duplicate names of different types agree on rightmost-wins shadowing.
example : ∃ value, (caller.bindLocals (bindings 7 7)).local? 7 = some value ∧
    ValueHasType program value (.scalar .string) := installed 7 7 7 _ rfl
example : (caller.bindLocals (bindings 7 7)).local? 7 = some (.string "hi") := rfl
example : evalMatchArms 2 program caller payload [(nested 7 9, .local 9)] =
    .done (.string "hi") (restoreLocals caller (caller.bindLocals (bindings 7 9))) := rfl
example : evalMatchArms 2 program caller payload [] = .trapped .nonExhaustiveMatch caller := rfl

-- Neither an uninitialized slot nor a reused frontier supports typed installation.
example : ¬ (({} : State).bindUninitialized 7).LocalsHaveTypes program
    (Context.empty.bind 7 (.scalar .bool)) := by
  intro typed
  obtain ⟨value, present, _⟩ := typed 7 _ rfl
  have missing : (({} : State).bindUninitialized 7).local? 7 = none := rfl
  rw [missing] at present
  cases present

private def invalidFrontier : State := {
  locals := [(7, 0)], cells := [{ id := 0, value := some (.character 81) }] }
example : ¬ (invalidFrontier.bindLocal 7 (.string "hi")).LocalsHaveTypes program
    (Context.empty.bind 7 (.scalar .string)) := by
  intro typed
  obtain ⟨value, present, valueTyped⟩ := typed 7 _ rfl
  have same : value = .character 81 := Option.some.inj (present.symm.trans rfl)
  subst value
  cases valueTyped

private def parameters : List (VarId × Ty) := declarations 7 9
private def arguments : List Value := [.boolean false, .string "hi"]
private theorem argumentsTyped : ValuesHaveTypes program arguments (parameters.map Prod.snd) :=
  .cons (.boolean false) (.cons (.string "hi") .nil)

example : ∃ bound, bindParameters parameters arguments = some bound ∧
    BindingsHaveTypes program bound parameters := bindParameters_types argumentsTyped
example : ∃ bound, bindParameters parameters arguments = some bound ∧
    (({ caller with locals := [] }).bindLocals bound).LocalsHaveTypes program
      (parameterContext parameters) := bindParameters_locals argumentsTyped callerFormed
example : bindParameters parameters arguments = some (bindings 7 9) := rfl
example : bindParameters parameters [.boolean false] = none := rfl
example : bindParameters parameters [.boolean false, .string "hi", .unit] = none := rfl
example : ∃ bound, bindParameters [] [] = some bound ∧ BindingsHaveTypes program bound [] :=
  bindParameters_types .nil
example : ∃ bound, bindParameters (declarations 7 7) arguments = some bound ∧
    (({ caller with locals := [] }).bindLocals bound).LocalsHaveTypes program
      (parameterContext (declarations 7 7)) :=
  bindParameters_locals (.cons (.boolean false) (.cons (.string "hi") .nil)) callerFormed

-- The same parameter computation is exercised by an actual internal call.
private def identityProgram : Program := { functions := [{
  id := 4, parameters := parameters, returnType := .scalar .string,
  body := some (.returnValue (some (.local 9))) }] }
example : evalExpr 5 identityProgram caller (.call 4 (arguments.map Expr.value)) =
    .done (.string "hi")
      (restoreLocals caller (({ caller with locals := [] }).bindLocals (bindings 7 9))) := rfl

#print axioms installed
#print axioms State.LocalsHaveTypes.evalLocal

end Lanius.Semantics.TypingTests
