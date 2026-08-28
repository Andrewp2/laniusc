import Lanius.Extraction.CoreDecode
import Lanius.Extraction.SurfaceChecker

namespace Lanius.Extraction

/-! ## Structural validation of an extracted Core proposal

This is deliberately not the semantic certificate checker. It establishes the
representation invariants needed by that checker: the proposal is present,
its located nodes have unique dense identities, and machine-width bit patterns
are represented canonically rather than being silently truncated by decoding.
-/

mutual
  def corePatternNodeIds : CorePattern → List CoreNodeId
    | ⟨id, .wildcard⟩ | ⟨id, .bind _⟩ | ⟨id, .literal _⟩ => [id]
    | ⟨id, .enum_variant _ _ payload⟩ => corePatternNodeIdsList payload ++ [id]

  def corePatternNodeIdsList : List CorePattern → List CoreNodeId
    | [] => []
    | head :: tail => corePatternNodeIds head ++ corePatternNodeIdsList tail

  def coreExprNodeIds : CoreExpr → List CoreNodeId
    | ⟨id, .value _⟩ | ⟨id, .local _⟩ | ⟨id, .constant _⟩ => [id]
    | ⟨id, .cast _ operand⟩
    | ⟨id, .unary _ operand⟩
    | ⟨id, .array_to_slice _ operand⟩
    | ⟨id, .dereference operand⟩
    | ⟨id, .intrinsic _ operand⟩
    | ⟨id, .i32_array_data_ptr operand⟩ => coreExprNodeIds operand ++ [id]
    | ⟨id, .binary _ left right⟩
    | ⟨id, .index left right⟩
    | ⟨id, .alloc left right⟩
    | ⟨id, .load_byte left right⟩ =>
        coreExprNodeIds left ++ coreExprNodeIds right ++ [id]
    | ⟨id, .array _ elements⟩
    | ⟨id, .struct_value _ elements⟩
    | ⟨id, .enum_value _ _ elements⟩
    | ⟨id, .call _ elements⟩ => coreExprNodeIdsList elements ++ [id]
    | ⟨id, .match_value scrutinee arms⟩ =>
        coreExprNodeIds scrutinee ++ coreMatchArmNodeIds arms ++ [id]
    | ⟨id, .assign _ place value⟩ =>
        corePlaceNodeIds place ++ coreExprNodeIds value ++ [id]
    | ⟨id, .borrow _ place⟩ => corePlaceNodeIds place ++ [id]
    | ⟨id, .field base _⟩ => coreExprNodeIds base ++ [id]
    | ⟨id, .realloc pointer oldSize newSize alignment⟩ =>
        coreExprNodeIds pointer ++ coreExprNodeIds oldSize ++
          coreExprNodeIds newSize ++ coreExprNodeIds alignment ++ [id]
    | ⟨id, .dealloc pointer size alignment⟩ =>
        coreExprNodeIds pointer ++ coreExprNodeIds size ++
          coreExprNodeIds alignment ++ [id]
    | ⟨id, .store_byte pointer offset value⟩ =>
        coreExprNodeIds pointer ++ coreExprNodeIds offset ++
          coreExprNodeIds value ++ [id]

  def coreExprNodeIdsList : List CoreExpr → List CoreNodeId
    | [] => []
    | head :: tail => coreExprNodeIds head ++ coreExprNodeIdsList tail

  def coreMatchArmNodeIds : List (CorePattern × CoreExpr) → List CoreNodeId
    | [] => []
    | (pattern, expression) :: tail =>
        corePatternNodeIds pattern ++ coreExprNodeIds expression ++
          coreMatchArmNodeIds tail

  def corePlaceNodeIds : CorePlace → List CoreNodeId
    | ⟨id, .local _⟩ => [id]
    | ⟨id, .field base _⟩ => corePlaceNodeIds base ++ [id]
    | ⟨id, .index base index⟩ =>
        corePlaceNodeIds base ++ coreExprNodeIds index ++ [id]
end

mutual
  def coreStmtNodeIds : CoreStmt → List CoreNodeId
    | ⟨id, .skip⟩ | ⟨id, .break_loop⟩ | ⟨id, .continue_loop⟩ => [id]
    | ⟨id, .expression expression⟩ => coreExprNodeIds expression ++ [id]
    | ⟨id, .sequence first second⟩ =>
        coreStmtNodeIds first ++ coreStmtNodeIds second ++ [id]
    | ⟨id, .let_local _ _ initializer body⟩ =>
        coreExprNodeIds initializer ++ coreStmtNodeIds body ++ [id]
    | ⟨id, .let_uninitialized _ _ body⟩ => coreStmtNodeIds body ++ [id]
    | ⟨id, .if_then_else condition thenBranch elseBranch⟩ =>
        coreExprNodeIds condition ++ coreStmtNodeIds thenBranch ++
          coreStmtNodeIds elseBranch ++ [id]
    | ⟨id, .while_loop condition body⟩ =>
        coreExprNodeIds condition ++ coreStmtNodeIds body ++ [id]
    | ⟨id, .for_values _ iterable body⟩ =>
        coreExprNodeIds iterable ++ coreStmtNodeIds body ++ [id]
    | ⟨id, .for_range _ start stop _ body⟩ =>
        coreExprNodeIds start ++ coreOptionalExprNodeIds stop ++
          coreStmtNodeIds body ++ [id]
    | ⟨id, .return_value value⟩ => coreOptionalExprNodeIds value ++ [id]

  def coreOptionalExprNodeIds : Option CoreExpr → List CoreNodeId
    | none => []
    | some expression => coreExprNodeIds expression
end

def coreFunctionNodeIds (function : CoreFunction) : List CoreNodeId :=
  match function.body with
  | none => []
  | some body => coreStmtNodeIds body

def coreFunctionNodeIdsList : List CoreFunction → List CoreNodeId
  | [] => []
  | head :: tail => coreFunctionNodeIds head ++ coreFunctionNodeIdsList tail

def coreProgramNodeIds (program : CoreProgram) : List CoreNodeId :=
  coreFunctionNodeIdsList program.functions

def sortedCoreNodeIds (program : CoreProgram) : List CoreNodeId :=
  (coreProgramNodeIds program).mergeSort

def coreNodeIdsDense (program : CoreProgram) : Bool :=
  let ids := coreProgramNodeIds program
  ids.mergeSort == List.range ids.length

def CoreNodeIdsDense (program : CoreProgram) : Prop :=
  let ids := coreProgramNodeIds program
  ids.mergeSort = List.range ids.length

theorem coreNodeIdsDense_sound {program : CoreProgram}
    (accepted : coreNodeIdsDense program = true) :
    CoreNodeIdsDense program := by
  exact eq_of_beq accepted

mutual
  def coreValueCanonical : CoreValue → Bool
    | .f32_bits bits | .character bits => decide (bits < 2 ^ 32)
    | .f64_bits bits => decide (bits < 2 ^ 64)
    | .array elements | .structure _ elements | .enumeration _ _ elements =>
        coreValuesCanonical elements
    | .unit | .boolean _ | .signed _ _ | .unsigned _ _ | .string _ |
        .pointer _ | .slice _ _ _ _ _ | .reference _ _ _ => true

  def coreValuesCanonical : List CoreValue → Bool
    | [] => true
    | head :: tail => coreValueCanonical head && coreValuesCanonical tail
end

mutual
  def corePatternValuesCanonical : CorePattern → Bool
    | ⟨_, .literal value⟩ => coreValueCanonical value
    | ⟨_, .enum_variant _ _ payload⟩ => corePatternListValuesCanonical payload
    | _ => true

  def corePatternListValuesCanonical : List CorePattern → Bool
    | [] => true
    | head :: tail =>
        corePatternValuesCanonical head && corePatternListValuesCanonical tail
end

mutual
  def coreExprValuesCanonical : CoreExpr → Bool
    | ⟨_, .value value⟩ => coreValueCanonical value
    | ⟨_, .cast _ operand⟩
    | ⟨_, .unary _ operand⟩
    | ⟨_, .array_to_slice _ operand⟩
    | ⟨_, .field operand _⟩
    | ⟨_, .dereference operand⟩
    | ⟨_, .intrinsic _ operand⟩
    | ⟨_, .i32_array_data_ptr operand⟩ => coreExprValuesCanonical operand
    | ⟨_, .binary _ left right⟩
    | ⟨_, .index left right⟩
    | ⟨_, .alloc left right⟩
    | ⟨_, .load_byte left right⟩ =>
        coreExprValuesCanonical left && coreExprValuesCanonical right
    | ⟨_, .array _ elements⟩
    | ⟨_, .struct_value _ elements⟩
    | ⟨_, .enum_value _ _ elements⟩
    | ⟨_, .call _ elements⟩ => coreExprListValuesCanonical elements
    | ⟨_, .match_value scrutinee arms⟩ =>
        coreExprValuesCanonical scrutinee && coreMatchArmsValuesCanonical arms
    | ⟨_, .assign _ place value⟩ =>
        corePlaceValuesCanonical place && coreExprValuesCanonical value
    | ⟨_, .borrow _ place⟩ => corePlaceValuesCanonical place
    | ⟨_, .realloc pointer oldSize newSize alignment⟩ =>
        coreExprValuesCanonical pointer && coreExprValuesCanonical oldSize &&
          coreExprValuesCanonical newSize && coreExprValuesCanonical alignment
    | ⟨_, .dealloc pointer size alignment⟩ =>
        coreExprValuesCanonical pointer && coreExprValuesCanonical size &&
          coreExprValuesCanonical alignment
    | ⟨_, .store_byte pointer offset value⟩ =>
        coreExprValuesCanonical pointer && coreExprValuesCanonical offset &&
          coreExprValuesCanonical value
    | ⟨_, .local _⟩ | ⟨_, .constant _⟩ => true

  def coreExprListValuesCanonical : List CoreExpr → Bool
    | [] => true
    | head :: tail =>
        coreExprValuesCanonical head && coreExprListValuesCanonical tail

  def coreMatchArmsValuesCanonical : List (CorePattern × CoreExpr) → Bool
    | [] => true
    | (pattern, expression) :: tail =>
        corePatternValuesCanonical pattern && coreExprValuesCanonical expression &&
          coreMatchArmsValuesCanonical tail

  def corePlaceValuesCanonical : CorePlace → Bool
    | ⟨_, .local _⟩ => true
    | ⟨_, .field base _⟩ => corePlaceValuesCanonical base
    | ⟨_, .index base index⟩ =>
        corePlaceValuesCanonical base && coreExprValuesCanonical index
end

mutual
  def coreStmtValuesCanonical : CoreStmt → Bool
    | ⟨_, .skip⟩ | ⟨_, .break_loop⟩ | ⟨_, .continue_loop⟩ => true
    | ⟨_, .expression expression⟩ => coreExprValuesCanonical expression
    | ⟨_, .sequence first second⟩ =>
        coreStmtValuesCanonical first && coreStmtValuesCanonical second
    | ⟨_, .let_local _ _ initializer body⟩ =>
        coreExprValuesCanonical initializer && coreStmtValuesCanonical body
    | ⟨_, .let_uninitialized _ _ body⟩ => coreStmtValuesCanonical body
    | ⟨_, .if_then_else condition thenBranch elseBranch⟩ =>
        coreExprValuesCanonical condition && coreStmtValuesCanonical thenBranch &&
          coreStmtValuesCanonical elseBranch
    | ⟨_, .while_loop condition body⟩ =>
        coreExprValuesCanonical condition && coreStmtValuesCanonical body
    | ⟨_, .for_values _ iterable body⟩ =>
        coreExprValuesCanonical iterable && coreStmtValuesCanonical body
    | ⟨_, .for_range _ start stop _ body⟩ =>
        coreExprValuesCanonical start &&
          stop.all coreExprValuesCanonical && coreStmtValuesCanonical body
    | ⟨_, .return_value value⟩ => value.all coreExprValuesCanonical
end

def coreFunctionValuesCanonical (function : CoreFunction) : Bool :=
  match function.body with
  | none => true
  | some body => coreStmtValuesCanonical body

def coreFunctionsValuesCanonical : List CoreFunction → Bool
  | [] => true
  | head :: tail =>
      coreFunctionValuesCanonical head && coreFunctionsValuesCanonical tail

def coreConstantsValuesCanonical : List CoreConstant → Bool
  | [] => true
  | head :: tail =>
      coreValueCanonical head.value && coreConstantsValuesCanonical tail

def coreProgramValuesCanonical (program : CoreProgram) : Bool :=
  coreConstantsValuesCanonical program.constants &&
    coreFunctionsValuesCanonical program.functions

def checkCoreStructure (artifact : Artifact) : Bool :=
  checkSurfaceArtifact artifact &&
    match artifact.core_program with
    | none => false
    | some program => coreNodeIdsDense program && coreProgramValuesCanonical program

def CoreStructureValid (artifact : Artifact) : Prop :=
  SurfaceArtifactValid artifact ∧
    ∃ wire,
      artifact.core_program = some wire ∧
      CoreNodeIdsDense wire ∧
      coreProgramValuesCanonical wire = true

theorem checkCoreStructure_sound {artifact : Artifact}
    (accepted : checkCoreStructure artifact = true) :
    CoreStructureValid artifact := by
  unfold checkCoreStructure at accepted
  simp only [Bool.and_eq_true] at accepted
  rcases accepted with ⟨surfaceAccepted, coreAccepted⟩
  cases found : artifact.core_program with
  | none => simp [found] at coreAccepted
  | some wire =>
      simp only [found, Bool.and_eq_true] at coreAccepted
      exact ⟨checkSurfaceArtifact_sound surfaceAccepted, wire, found,
        coreNodeIdsDense_sound coreAccepted.1, coreAccepted.2⟩

def decodeCheckedCore (artifact : Artifact) : Option Core.Program := do
  if !checkCoreStructure artifact then none
  let wire ← artifact.core_program
  pure (CoreDecode.program wire)

end Lanius.Extraction
