import Lanius.TypedIR.Link
import Lanius.Execution

open Lanius
open Lanius.TypedIR.Intrinsic

private abbrev i32 : Core.Ty := .scalar (.signed .i32)
private def choice : Core.EnumDecl := ⟨0, [[], [i32]]⟩
private def signature : Signature :=
  { enumerations := [choice], functions := [⟨1, [], i32⟩] }
private def someChoice : VariantRef signature 0 [i32] := ⟨1, choice, rfl, rfl⟩
private def noneChoice : VariantRef signature 0 [] := ⟨0, choice, rfl, rfl⟩
private def number (value : Int) (lower : -2147483648 ≤ value) (upper : value ≤ 2147483647) :
    Expr signature context i32 := .literal (.signed .i32 value lower upper)

-- The function body is stored once. Its constructors supply type, scope, and
-- return guarantees; there is no matching ExprHasType/StmtHasType tree here.
private def mainFunction : Function signature :=
  { id := 1, parameters := [], result := i32, body := .defined
      (.letLocal 0 (.variant someChoice (.cons (number 7 (by decide) (by decide)) .nil))
        (.returnValue (.matchValue (.local ⟨0, rfl⟩)
          (.cons (.variant someChoice (.cons (.bind 1) .nil)) (.local ⟨1, rfl⟩)
            (.one (.variant noneChoice .nil) (number 0 (by decide) (by decide))))))) (.inr rfl) }

def choiceProgram : Program :=
  link signature [mainFunction] 1 rfl (by simp [signature]) rfl

-- This is an application of the shared erasure theorem, not generated proof
-- constructors, computation of a body checker, or an axiom.
theorem choiceWellTyped : Typing.ProgramWellTyped choiceProgram.core := choiceProgram.wellTyped
#print axioms choiceWellTyped

example : mainFunction.erase.body = some
    (.letLocal 0 (.enumeration 0) (.enumValue 0 1 [.value (.signed .i32 7)])
      (.returnValue (some (.matchValue (.local 0)
        [(.enumVariant 0 1 [.bind 1], .local 1),
         (.enumVariant 0 0 [], .value (.signed .i32 0))])))) := rfl

example : (match Execution.run 64 { program := choiceProgram.core, entrypoint := 1 } {} with
  | .returned (.signed .i32 7) _ => true | _ => false) = true := by decide

-- These must fail at construction, before linking or running a checker.
example : True := by
  fail_if_success
    have wrongLiteral : Expr signature Lanius.TypedIR.Intrinsic.Scope.empty i32 := .literal (.boolean true)
  fail_if_success
    have unbound : Local Lanius.TypedIR.Intrinsic.Scope.empty i32 := ⟨0, rfl⟩
  fail_if_success
    have wrongPayload : Expr signature Lanius.TypedIR.Intrinsic.Scope.empty (.enumeration 0) :=
      .variant someChoice (.cons (.literal (.boolean true)) .nil)
  fail_if_success
    have wrongCall : FunctionRef signature [] (.scalar .bool) := ⟨1, rfl⟩
  fail_if_success
    have breakOutsideLoop : Stmt signature i32 Lanius.TypedIR.Intrinsic.Scope.empty false false := .breakLoop
  fail_if_success
    have missingReturn : Body signature [] i32 := .defined .skip (.inr rfl)
  fail_if_success
    have forgedHost : Body signature [] i32 := .host .alloc rfl rfl
  trivial

-- Recursive references use the fixed signature, never a function body.
private def recursiveFunction : Function signature :=
  { id := 1, parameters := [], result := i32,
    body := .defined (.returnValue (.call ⟨1, rfl⟩ .nil)) (.inr rfl) }
private def recursiveProgram : Program :=
  link signature [recursiveFunction] 1 rfl (by simp [signature]) rfl
example : Typing.ProgramWellTyped recursiveProgram.core := recursiveProgram.wellTyped

-- A large constant table is well typed by construction. Keep the table name
-- in the reflexivity proof, rather than reducing the whole list to prove it.
private def manyLiterals : List (Constant .x86_64) :=
  Data.List.flatten (List.replicate 12 ((List.range 64).map fun id =>
    ⟨id, i32, .signed .i32 7 (by decide) (by decide)⟩))
private def manyConstants := Data.List.map Constant.erase manyLiterals
private def manySignature : Signature := { constants := manyConstants }
example : ∀ constant ∈ manyConstants, Typing.ConstantWellTyped manySignature.declarations constant :=
  constants_wellTyped manySignature.declarations manyLiterals (Eq.refl manyConstants)

-- Linking cannot replace the declared i32 function with a boolean body.
example : True := by
  fail_if_success
    have mismatch : (assemble signature
      [⟨1, [], .scalar .bool, .defined (.returnValue (.literal (.boolean true))) (.inr rfl)⟩]).functions.map
        FunctionType.ofCore = signature.functions := rfl
  trivial
