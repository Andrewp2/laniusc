import Lanius.TypedIR.Surface.Link
import Lanius.Execution

namespace Lanius.TypedIR.Surface.LinkTests
open Lanius
open scoped Surface

inductive Choice | none | some (value : I32)
inductive Box (α : Type) | mk (payload : α) (choices : Slice Choice)
inductive Unused | flag (value : Bool)
inductive Empty | mk
attribute [lanius_type enum 9] Choice
attribute [lanius_type record 7] Box
attribute [lanius_type enum 3] Unused
attribute [lanius_type record 1] Empty

private inductive Hidden | mk (value : I32)
attribute [lanius_type record 11] Hidden
def HiddenAlias := Hidden

def makeHidden : Function [] HiddenAlias :=
  function (id := 6, name := "makeHidden", arguments := [], bindings := []) do
    return { value := 7 : HiddenAlias }
example : makeHidden.core.body = some
    (.returnValue (some (.structValue 11 [.value (.signed .i32 7)]))) := rfl

-- Reject metadata that cannot describe a source nominal declaration.
def notAType := 7
/-- error: Lanius nominal metadata requires an inductive type -/
#guard_msgs in
attribute [lanius_type record 1] notAType
/-- error: Lanius record metadata requires exactly one constructor -/
#guard_msgs in
attribute [lanius_type record 1] Choice
/-- error: nominal kind must be record or enum -/
#guard_msgs in
attribute [lanius_type invalid 1] Choice

def main : Function [] I32 :=
  function (id := 5, name := "main", arguments := [], bindings := [1, 2]) do
    let choice : Choice := .some 7
    return match choice with
      | .none => 0
      | .some value => value

def program : Core.Program :=
  link (types := [Choice, Box I32, Unused, Empty],
    constants := [⟨42, .scalar .bool, .boolean true⟩], functions := [main.pack])

-- Partitioning keeps source order and IDs, including unused declarations.
example : program.structures =
    [⟨7, [.scalar (.signed .i32), .slice (.enumeration 9)]⟩, ⟨1, []⟩] := rfl
example : program.enumerations =
    [⟨9, [[], [.scalar (.signed .i32)]]⟩, ⟨3, [[.scalar .bool]]⟩] := rfl
example : program.constants = [⟨42, .scalar .bool, .boolean true⟩] := rfl
example : program.functions = [main.pack] := rfl
example : program.target = .x86_64 := rfl
-- Option names must remain ordinary identifiers for Core record updates.
example : ({ program with functions := [] } : Core.Program).functions = [] := rfl
example : (match Execution.run 128 { program, entrypoint := 5 } {} with
  | .returned (.signed .i32 7) _ => true | _ => false) = true := by decide

example : (link (types := [], constants := [], functions := []) : Core.Program) = {} := rfl

-- Linking transfers function declarations; it does not recheck Lanius typing.
example (fn : Core.Function) :
    (link (types := [], constants := [], functions := [fn]) : Core.Program).functions = [fn] := rfl

end Lanius.TypedIR.Surface.LinkTests
