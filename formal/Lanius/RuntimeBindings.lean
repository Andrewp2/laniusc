import Lanius.ProgramElaboration

namespace Lanius.RuntimeBindings

open Lanius
open Lanius.Core
open Lanius.ProgramElaboration

def i32Ty : Ty := .scalar (.signed .i32)
def i64Ty : Ty := .scalar (.signed .i64)
def u32Ty : Ty := .scalar (.unsigned .u32)
def usizeTy : Ty := .scalar (.unsigned .usize)
def ptrTy : Ty := .scalar .rawPtr
def strTy : Ty := .scalar .string

def hostBinding (abi name : String) (service : HostService) : ExternalBinding := {
  abi := some abi
  name
  parameterTypes := service.parameterTypes
  returnType := service.returnType
  behavior := .host service
}

def unavailableBinding
    (abi name : String) (parameterTypes : List Ty) (returnType : Ty)
    (capability : Capability) : ExternalBinding := {
  abi := some abi
  name
  parameterTypes
  returnType
  behavior := .unavailable capability
}

def terminalBinding
    (abi name : String) (behavior : ExternalBehavior) : ExternalBinding := {
  abi := some abi
  name
  parameterTypes := []
  returnType := .unit
  behavior
}

def allocatorBindings : List ExternalBinding := [
  hostBinding "lanius_alloc" "alloc" .alloc,
  hostBinding "lanius_alloc" "realloc" .realloc,
  hostBinding "lanius_alloc" "dealloc" .dealloc,
  hostBinding "lanius_alloc" "alloc_failed" .allocFailed
]

def panicBindings : List ExternalBinding := [
  terminalBinding "lanius_panic" "panic" .panic,
  terminalBinding "lanius_panic" "unreachable" .unreachable
]

def filesystemBindings : List ExternalBinding := [
  hostBinding "lanius_std" "open_read" .openRead,
  hostBinding "lanius_std" "open_write" .openWrite,
  hostBinding "lanius_std" "open_append" .openAppend,
  hostBinding "lanius_std" "close" .close,
  hostBinding "lanius_std" "read" .read,
  hostBinding "lanius_std" "write" .write,
  hostBinding "lanius_std" "remove_file" .removeFile,
  hostBinding "lanius_std" "create_dir" .createDir,
  hostBinding "lanius_std" "remove_dir" .removeDir,
  hostBinding "lanius_std" "rename" .rename,
  hostBinding "lanius_std" "open_read_path" .openReadPath,
  hostBinding "lanius_std" "open_write_path" .openWritePath,
  hostBinding "lanius_std" "read_i32" .readI32,
  hostBinding "lanius_std" "close_file" .closeFile
]

def stdioBindings : List ExternalBinding := [
  hostBinding "lanius_std" "write_stdout" .writeStdout,
  hostBinding "lanius_std" "write_stderr" .writeStderr,
  hostBinding "lanius_std" "read_stdin" .readStdin,
  hostBinding "lanius_std" "write_text" .writeText,
  hostBinding "lanius_std" "write_i32" .writeI32,
  hostBinding "lanius_std" "write_byte" .writeByte,
  hostBinding "lanius_std" "write_newline" .writeNewline
]

def clockBindings : List ExternalBinding := [
  hostBinding "lanius_std" "monotonic_read" .monotonicRead,
  hostBinding "lanius_std" "system_read" .systemRead,
  hostBinding "lanius_std" "sleep_ms_i32" .sleepMsI32,
  hostBinding "lanius_std" "unix_seconds" .unixSeconds,
  unavailableBinding "lanius_std" "monotonic_now_ns" [] i64Ty .clock,
  unavailableBinding "lanius_std" "system_now_unix_ms" [] i64Ty .clock,
  unavailableBinding "lanius_std" "sleep_ms" [i64Ty] i32Ty .clock
]

def networkBindings : List ExternalBinding := [
  unavailableBinding "lanius_std" "tcp_connect" [ptrTy, usizeTy, i32Ty] i32Ty .network,
  unavailableBinding "lanius_std" "tcp_bind" [ptrTy, usizeTy, i32Ty] i32Ty .network,
  unavailableBinding "lanius_std" "tcp_listen" [i32Ty, i32Ty] i32Ty .network,
  unavailableBinding "lanius_std" "tcp_accept" [i32Ty] i32Ty .network,
  unavailableBinding "lanius_std" "tcp_close" [i32Ty] i32Ty .network,
  unavailableBinding "lanius_std" "tcp_send" [i32Ty, ptrTy, usizeTy] i32Ty .network,
  unavailableBinding "lanius_std" "tcp_recv" [i32Ty, ptrTy, usizeTy] i32Ty .network,
  unavailableBinding "lanius_std" "udp_bind" [ptrTy, usizeTy, i32Ty] i32Ty .network,
  unavailableBinding "lanius_std" "udp_send_to"
    [i32Ty, ptrTy, ptrTy, usizeTy] i32Ty .network,
  unavailableBinding "lanius_std" "udp_recv_from"
    [i32Ty, ptrTy, ptrTy, usizeTy] i32Ty .network
]

def threadBindings : List ExternalBinding := [
  unavailableBinding "lanius_std" "spawn" [u32Ty, u32Ty] i32Ty .thread,
  unavailableBinding "lanius_std" "join" [i32Ty] i32Ty .thread,
  unavailableBinding "lanius_std" "yield_now" [] i32Ty .thread,
  unavailableBinding "lanius_std" "current_id" [] i32Ty .thread
]

def randomBindings : List ExternalBinding := [
  hostBinding "lanius_std" "fill_secure_bytes" .fillSecureBytes,
  hostBinding "lanius_std" "secure_u32" .secureU32
]

def gpuBindings : List ExternalBinding := [
  unavailableBinding "lanius_std" "buffer_alloc" [usizeTy] u32Ty .gpu,
  unavailableBinding "lanius_std" "buffer_free" [u32Ty] i32Ty .gpu,
  unavailableBinding "lanius_std" "buffer_write" [u32Ty, ptrTy, usizeTy] i32Ty .gpu,
  unavailableBinding "lanius_std" "buffer_read" [u32Ty, ptrTy, usizeTy] i32Ty .gpu,
  unavailableBinding "lanius_std" "dispatch_1d" [u32Ty, u32Ty] i32Ty .gpu
]

def processBindings : List ExternalBinding := [
  hostBinding "lanius_std" "argc" .argc,
  hostBinding "lanius_std" "arg_len" .argLen,
  hostBinding "lanius_std" "arg_read" .argRead,
  hostBinding "lanius_std" "exit" .exit
]

def environmentBindings : List ExternalBinding := [
  hostBinding "lanius_std" "var_len" .varLen,
  hostBinding "lanius_std" "var_read" .varRead,
  hostBinding "lanius_std" "var_count" .varCount,
  hostBinding "lanius_std" "var_key_len" .varKeyLen,
  hostBinding "lanius_std" "var_key_read" .varKeyRead,
  hostBinding "lanius_std" "current_dir_read" .currentDirRead
]

/-- These are the 65 `extern` declarations in the current checked-in standard
    library.  Derived library functions are deliberately absent. -/
def stdlibExternalBindings : List ExternalBinding :=
  allocatorBindings ++ panicBindings ++ filesystemBindings ++ stdioBindings ++
    clockBindings ++ networkBindings ++ threadBindings ++ randomBindings ++
    gpuBindings ++ processBindings ++ environmentBindings

/-- Compiler-recognized source externs that are exercised outside the stdlib. -/
def compilerPrimitiveBindings : List ExternalBinding := [
  hostBinding "lanius_std" "i32_to_f32" .i32ToF32
]

def canonicalExternalBindings : List ExternalBinding :=
  stdlibExternalBindings ++ compilerPrimitiveBindings

def externalBindingWellFormed? (binding : ExternalBinding) : Bool :=
  match binding.behavior with
  | .host service =>
      decide (binding.parameterTypes = service.parameterTypes) &&
        decide (binding.returnType = service.returnType)
  | .panic | .unreachable =>
      decide (binding.parameterTypes = []) && decide (binding.returnType = .unit)
  | .unavailable _ | .opaque _ => true

def bindingsWellFormed? (bindings : List ExternalBinding) : Bool :=
  bindings.all externalBindingWellFormed?

def sameSelector? (left right : ExternalBinding) : Bool :=
  decide (left.abi = right.abi) && decide (left.name = right.name) &&
    decide (left.parameterTypes = right.parameterTypes) &&
    decide (left.returnType = right.returnType)

def bindingsCompatible? (left right : ExternalBinding) : Bool :=
  !sameSelector? left right || decide (left.behavior = right.behavior)

def BindingsCompatible (left right : ExternalBinding) : Prop :=
  left.abi = right.abi → left.name = right.name →
    left.parameterTypes = right.parameterTypes →
    left.returnType = right.returnType →
    left.behavior = right.behavior

def bindingsCoherent? : List ExternalBinding → Bool
  | [] => true
  | binding :: tail =>
      tail.all (bindingsCompatible? binding) && bindingsCoherent? tail

def BindingsWellFormed (bindings : List ExternalBinding) : Prop :=
  bindingsWellFormed? bindings = true

def BindingsCoherent (bindings : List ExternalBinding) : Prop :=
  bindingsCoherent? bindings = true

theorem external_binding_well_formed_of_check
    (binding : ExternalBinding)
    (checked : externalBindingWellFormed? binding = true) :
    ExternalBindingWellFormed binding := by
  cases binding with
  | mk abi name parameterTypes returnType behavior =>
      cases behavior <;>
        simp [externalBindingWellFormed?, ExternalBindingWellFormed] at checked ⊢ <;>
        exact checked

theorem member_well_formed_of_check
    (bindings : List ExternalBinding) (binding : ExternalBinding)
    (checked : BindingsWellFormed bindings) (member : binding ∈ bindings) :
    ExternalBindingWellFormed binding := by
  unfold BindingsWellFormed at checked
  induction bindings with
  | nil => simp at member
  | cons head tail inductionHypothesis =>
      simp only [bindingsWellFormed?, List.all_cons, Bool.and_eq_true] at checked
      simp only [List.mem_cons] at member
      rcases member with headEqual | tailMember
      · subst binding
        exact external_binding_well_formed_of_check head checked.1
      · exact inductionHypothesis checked.2 tailMember

theorem bindings_compatible_of_check
    (left right : ExternalBinding)
    (checked : bindingsCompatible? left right = true) :
    BindingsCompatible left right := by
  intro abi name parameters returned
  have behaviorChecked : decide (left.behavior = right.behavior) = true := by
    simpa [bindingsCompatible?, sameSelector?, abi, name, parameters, returned]
      using checked
  exact of_decide_eq_true behaviorChecked

private theorem compatible_with_member_of_all
    (left right : ExternalBinding) (bindings : List ExternalBinding)
    (checked : bindings.all (bindingsCompatible? left) = true)
    (member : right ∈ bindings) :
    BindingsCompatible left right := by
  induction bindings with
  | nil => simp at member
  | cons head tail inductionHypothesis =>
      simp only [List.all_cons, Bool.and_eq_true] at checked
      simp only [List.mem_cons] at member
      rcases member with headEqual | tailMember
      · subst right
        exact bindings_compatible_of_check left head checked.1
      · exact inductionHypothesis checked.2 tailMember

theorem members_compatible_of_coherent_check
    (bindings : List ExternalBinding) (left right : ExternalBinding)
    (checked : BindingsCoherent bindings)
    (leftMember : left ∈ bindings) (rightMember : right ∈ bindings) :
    BindingsCompatible left right := by
  unfold BindingsCoherent at checked
  induction bindings with
  | nil => simp at leftMember
  | cons head tail inductionHypothesis =>
      simp only [bindingsCoherent?, Bool.and_eq_true] at checked
      simp only [List.mem_cons] at leftMember rightMember
      rcases leftMember with leftHead | leftTail
      · subst left
        rcases rightMember with rightHead | rightTail
        · subst right
          intro _ _ _ _
          rfl
        · exact compatible_with_member_of_all head right tail checked.1 rightTail
      · rcases rightMember with rightHead | rightTail
        · subst right
          have reverse := compatible_with_member_of_all head left tail checked.1 leftTail
          intro abi name parameters returned
          exact (reverse abi.symm name.symm parameters.symm returned.symm).symm
        · exact inductionHypothesis checked.2 leftTail rightTail

theorem stdlib_external_binding_count : stdlibExternalBindings.length = 65 := by
  decide

theorem canonical_external_bindings_well_formed :
    BindingsWellFormed canonicalExternalBindings := by
  change bindingsWellFormed? canonicalExternalBindings = true
  decide

theorem canonical_external_bindings_coherent :
    BindingsCoherent canonicalExternalBindings := by
  change bindingsCoherent? canonicalExternalBindings = true
  decide

theorem member_selects_checked_binding
    (bindings : List ExternalBinding) (selected : ExternalBinding)
    (wellFormed : BindingsWellFormed bindings)
    (coherent : BindingsCoherent bindings)
    (member : selected ∈ bindings) :
    SelectsExternalBinding bindings selected.abi selected.name
      selected.parameterTypes selected.returnType selected := by
  refine ⟨member, rfl, rfl, rfl, rfl,
    member_well_formed_of_check bindings selected wellFormed member, ?_⟩
  intro candidate candidateMember abi name parameters returned
  exact members_compatible_of_coherent_check bindings candidate selected coherent
    candidateMember member abi name parameters returned

theorem canonical_exit_selects :
    SelectsExternalBinding canonicalExternalBindings (some "lanius_std") "exit"
      [i32Ty] .unit (hostBinding "lanius_std" "exit" .exit) := by
  apply member_selects_checked_binding canonicalExternalBindings
    (hostBinding "lanius_std" "exit" .exit)
    canonical_external_bindings_well_formed canonical_external_bindings_coherent
  decide

end Lanius.RuntimeBindings
