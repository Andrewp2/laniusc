import Lanius.X86.Source.Constant
import Lanius.Extraction.Source.Call
import Lanius.Automation.Execute

namespace Lanius.X86.Source.Table

open Lanius.Core Lanius.Semantics Lanius.Extraction

/-- An authenticated scalar leaf, not an assumed evaluation result. -/
inductive Atom (program : Program) where
  | literal (value : Int)
  | constant (entry : IntegerConstant program)

def Atom.expression : Atom program → Expr
  | .literal value => .value (.signed .i32 value)
  | .constant entry => .constant entry.id

def Atom.value : Atom program → Int
  | .literal value => value
  | .constant entry => entry.value

def atom? (program : Program) : Expr → Option (Atom program)
  | .value (.signed .i32 value) => some (.literal value)
  | .constant id => (integerConstant? program id).map Atom.constant
  | _ => none

theorem Atom.evaluates (atom : Atom program) (state : State) :
    Evaluates program state atom.expression (.signed .i32 atom.value) state := by
  cases atom with
  | literal => core_eval []
  | constant entry => exact entry.evaluates

def values (rows : List (Atom program × Atom program)) : List (Int × Int) :=
  rows.map fun (key, result) => (key.value, result.value)

def lookup : List (Int × Int) → Int → Int
  | [], _ => -1
  | (key, result) :: rest, input => if input = key then result else lookup rest input

def body : List (Atom program × Atom program) → Stmt
  | [] => returned (.unary .negate (number 1))
  | (key, result) :: rest => .sequence
      (.ifThenElse (.binary .equal (read 0) key.expression) (returned result.expression) .skip) (body rest)

def rows? (program : Program) : Stmt → Option (List (Atom program × Atom program))
  | .sequence (.ifThenElse (.binary .equal (.local 0) key)
      (.sequence (.returnValue (some result)) .skip) .skip) rest => do
      pure ((← atom? program key, ← atom? program result) :: (← rows? program rest))
  | .sequence (.returnValue (some (.unary .negate (.value (.signed .i32 1))))) .skip => some []
  | _ => none

/-- One induction handles every row, preserving first-match semantics even
when keys repeat. Both table endpoints are read from actual scalar syntax. -/
theorem executes (rows : List (Atom program × Atom program)) (input : Int)
    (found : before.local? 0 = some (.signed .i32 input)) :
    Executes program before (body rows) (.returned (some (.signed .i32 (lookup (values rows) input)))) before := by
  induction rows with
  | nil => core_exec [body, values, lookup]
  | cons row rest ih =>
      have key := row.1.evaluates before
      have result := row.2.evaluates before
      by_cases same : input = row.1.value
      · simp only [values, List.map_cons, lookup, if_pos same]
        core_exec [body]
      · simp only [values, List.map_cons, lookup, if_neg same]
        core_exec [body]

structure Checked (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (modulePath : Names.ModulePath) (name : Surface.Name) (table : List (Int × Int)) where
  rows : List (Atom program.core × Atom program.core)
  valuesExact : values rows = table
  internal : Extraction.Source.CheckedInternal program modulePath name [(0, i32)] i32 (body rows)

def check? (program : CoreSynthesis.Program.CheckedProgram artifacts)
    (modulePath : Names.ModulePath) (name : Surface.Name) (table : List (Int × Int)) :
    Option (Checked program modulePath name table) := do
  let source ← CoreSynthesis.Program.checkSourceFunction? program modulePath name
  let rows ← rows? program.core (← source.function.body)
  if valuesExact : values rows = table then
    let internal ← Extraction.Source.checkInternal? program modulePath name [(0, i32)] i32 (body rows)
    pure ⟨rows, valuesExact, internal⟩
  else none

theorem Checked.spec (checked : Checked program modulePath name table) (input : Int) :
    checked.internal.Spec [.signed .i32 input] (.signed .i32 (lookup table input)) := by
  apply checked.internal.specPure rfl
  intro callee locals
  simpa only [checked.valuesExact] using executes checked.rows input (locals 0 (by simp))

end Lanius.X86.Source.Table
