import Lanius.Compiler.ProgramLowering

namespace Lanius.Compiler.EligibilityCheck

open Lanius
open Lanius.Compiler.ProgramLowering

inductive Failure
  | unsupported
  deriving DecidableEq, Repr

def namedParametersCheck : List Surface.Parameter → Bool
  | [] => true
  | .named _ _ :: parameters => namedParametersCheck parameters
  | _ :: _ => false

def checkItem : Surface.Item → Bool
  | .module _ | .importPath _ | .constant _ _ _ _ => true
  | .typeAlias _ _ parameters predicates _ => parameters.isEmpty && predicates.isEmpty
  | .function declaration =>
      declaration.genericParameters.isEmpty && declaration.wherePredicates.isEmpty &&
        namedParametersCheck declaration.parameters
  | .externFunction declaration =>
      declaration.abi.isNone && declaration.genericParameters.isEmpty &&
        declaration.wherePredicates.isEmpty && namedParametersCheck declaration.parameters
  | .structure declaration =>
      declaration.genericParameters.isEmpty && declaration.wherePredicates.isEmpty
  | _ => false

def checkItems (items : List Surface.Item) : Bool := items.all checkItem

def checkPack (pack : Declarations.SourcePack) : Bool :=
  pack.files.all (fun file => checkItems file.contents.items)

theorem namedParameters_sound {parameters : List Surface.Parameter}
    (h : namedParametersCheck parameters = true) : NamedParametersSupported parameters := by
  induction parameters with
  | nil => simp [NamedParametersSupported]
  | cons head tail ih =>
      cases head <;> simp [namedParametersCheck, NamedParametersSupported] at h ⊢
      exact ih h

theorem checkItem_sound {item : Surface.Item}
    (h : checkItem item = true) : SupportedItem item := by
  cases item <;> simp [checkItem, SupportedItem] at h ⊢
  all_goals
    first
    | exact ⟨h.1.1, h.1.2, namedParameters_sound h.2⟩
    | exact ⟨h.1.1.1, h.1.1.2, h.1.2, namedParameters_sound h.2⟩
    | exact h

theorem checkItems_sound {items : List Surface.Item} (h : checkItems items = true) :
    ∀ item, item ∈ items → SupportedItem item := by
  intro item member
  exact checkItem_sound ((List.all_eq_true.mp h) item member)

theorem checkPack_sound {pack : Declarations.SourcePack} (h : checkPack pack = true) :
    SupportedMonomorphic pack := by
  intro file fileMember item itemMember
  exact checkItems_sound ((List.all_eq_true.mp h) file fileMember) item itemMember

structure Checked (pack : Declarations.SourcePack) : Type where
  evidence : SupportedMonomorphic pack

def check (pack : Declarations.SourcePack) : Except Failure (Checked pack) :=
  if h : checkPack pack = true then .ok { evidence := checkPack_sound h }
  else .error .unsupported

end Lanius.Compiler.EligibilityCheck
