import Lanius.Declarations
import Lanius.Core

namespace Lanius.Compiler.RuntimeImports

/-- The runtime subset implemented by the Lanius-written compiler. ABI and
    source name select a service; matching its signature alone is insufficient. -/
def service : String → Surface.Name → Option Core.HostService
  | "lanius_alloc", "alloc" => some .alloc
  | "lanius_std", "open_read" => some .openRead
  | "lanius_std", "close" => some .close
  | "lanius_std", "read" => some .read
  | "lanius_std", "write_stdout" => some .writeStdout
  | "lanius_std", "write_byte" => some .writeByte
  | "lanius_std", "argc" => some .argc
  | "lanius_std", "arg_len" => some .argLen
  | "lanius_std", "arg_read" => some .argRead
  | _, _ => none

/-- An omitted ABI uses the caller's explicit external policy. An explicit
    ABI must denote the actual service, even if that policy is supplied by an
    untrusted caller. Signature validation remains a separate obligation. -/
def Matches (declaration : Surface.ExternFunction)
    (external : Option Core.ExternalBehavior) : Prop :=
  match declaration.abi with
  | none => True
  | some abi => match service abi declaration.name with
    | none => False
    | some expected => external = some (.host expected)

instance (declaration : Surface.ExternFunction) (external : Option Core.ExternalBehavior) :
    Decidable (Matches declaration external) := by
  unfold Matches
  split <;> first | infer_instance | (split <;> infer_instance)

/-- The native compiler's default policy, applied to an authenticated header.
    `Matches` separately authenticates explicit ABIs against the source. -/
def resolve (header : Declarations.DeclarationHeader) : Option Core.ExternalBehavior := do
  if header.kind != .externalFunction then none else
    let name ← header.name
    let found ← (service "lanius_alloc" name).or (service "lanius_std" name)
    some (.host found)

end Lanius.Compiler.RuntimeImports
