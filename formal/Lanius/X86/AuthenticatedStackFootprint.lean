import Lanius.X86.ProgramCheck
import Lanius.X86.ProcessLayoutCheck

namespace Lanius.X86.AuthenticatedStackFootprint

open Lanius Lanius.Core
open Lanius.X86
open Lanius.X86.Machine
open Lanius.X86.ProgramCheck
open Lanius.X86.ProcessLayoutCheck

/- Offsets are measured downward from the machine RSP at the authenticated
   entrypoint.  The direct branch has the caller saved frame and one caller
   slot, the CALL return word, the callee saved frame, and then the callee's
   dynamic slots. -/
def direct (checked : DirectChecked executable image displacement) : List Nat :=
  [8, 16, 32, 40] ++
    match checked.calleeMode with
    | .body supported =>
        (List.range supported.checkedShape.1.allocations).map (fun slot => 48 + 8 * slot)
    | .literal _ => []
    | .literalParametersTrailing _ => []

def authenticated (checked : Authenticated executable image) : List Nat :=
  match checked with
  | .standard checked => entryStackFootprint checked.entrypoint.function
  | .direct _ checked => direct checked

def authenticatedStartupStackFootprint (checked : Authenticated executable image) : List Nat :=
  [8, 16, 24] ++ (authenticated checked).map (fun slot => 24 + slot)

def AuthenticatedImageStackDisjoint
    (checked : Authenticated executable image) (elf : List UInt8)
    (before : Machine.State) : Prop :=
  ∀ offset, offset < elf.length → ∀ slot,
    slot ∈ authenticatedStartupStackFootprint checked → ∀ lane : Fin 8,
    ImageCheck.lanius.base + BitVec.ofNat 64 offset ≠
      before.registers rspRegister - BitVec.ofNat 64 slot + BitVec.ofNat 64 lane.val

private theorem direct_startup_slot_subset
    {executable : Execution.Executable} {image : Image}
    {displacement : BitVec 32}
    (checked : DirectChecked executable image displacement) {slot : Nat}
    (member : slot ∈ startupStackFootprint checked.caller) :
    slot ∈ authenticatedStartupStackFootprint (.direct displacement checked) := by
  rcases checked.callerBodyShape with body | body
  · simp [startupStackFootprint, entryStackFootprint, body,
      authenticatedStartupStackFootprint, authenticated, direct] at member
    rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
      simp [authenticatedStartupStackFootprint, authenticated, direct]
  · simp [startupStackFootprint, entryStackFootprint, body,
      authenticatedStartupStackFootprint, authenticated, direct] at member
    rcases member with rfl | rfl | rfl | rfl | rfl | rfl | rfl <;>
      simp [authenticatedStartupStackFootprint, authenticated, direct]

theorem authenticatedImageStackDisjoint_implies
    {executable : Execution.Executable} {image : Image}
    {elf : List UInt8} {before : Machine.State}
    (checked : Authenticated executable image)
    (separation : AuthenticatedImageStackDisjoint checked elf before) :
    ImageStackDisjoint elf before checked.entrypoint.function := by
  unfold ImageStackDisjoint
  cases checked with
  | standard checked =>
      intro offset offsetBound slot member lane
      apply separation offset offsetBound slot ?_ lane
      simpa [AuthenticatedImageStackDisjoint, authenticatedStartupStackFootprint,
        authenticated, Authenticated.entrypoint, startupStackFootprint] using member
  | direct displacement checked =>
      intro offset offsetBound slot member lane
      apply separation offset offsetBound slot ?_ lane
      exact direct_startup_slot_subset checked member

theorem direct_saved_frame_mem
    (checked : DirectChecked executable image displacement) :
    8 ∈ direct checked := by
  cases checked.calleeMode <;> simp [direct]

theorem direct_caller_slot_mem
    (checked : DirectChecked executable image displacement) :
    16 ∈ direct checked := by
  cases checked.calleeMode <;> simp [direct]

theorem direct_call_return_mem
    (checked : DirectChecked executable image displacement) :
    32 ∈ direct checked := by
  cases checked.calleeMode <;> simp [direct]

theorem direct_callee_saved_frame_mem
    (checked : DirectChecked executable image displacement) :
    40 ∈ direct checked := by
  cases checked.calleeMode <;> simp [direct]

theorem direct_body_slot_mem
    (checked : DirectChecked executable image displacement)
    {supported : ExpressionFunctionCheck.BodySupported checked.callee
      checked.calleeImage.bytes}
    (mode : checked.calleeMode = .body supported)
    {slot : Nat} (slotBound : slot < supported.checkedShape.1.allocations) :
    48 + 8 * slot ∈ direct checked := by
  unfold direct
  rw [mode]
  apply List.mem_append.mpr
  right
  exact List.mem_map.mpr ⟨slot, by simp [slotBound], rfl⟩

theorem direct_body_allocation_bound
    (checked : DirectChecked executable image displacement)
    {supported : ExpressionFunctionCheck.BodySupported checked.callee
      checked.calleeImage.bytes}
    (_mode : checked.calleeMode = .body supported) :
    supported.checkedShape.1.allocations ≤ 2^28 :=
  supported.allocationsBound

/- The old direct entry footprint is exactly [8,16,32,40]; it omits the
   first dynamic callee slot at 48 (and therefore every later body slot). -/
theorem old_direct_footprint_omits_body_slot
    {caller callee : Function}
    (body : caller.body = some (.returnValue (some (.call callee.id []))) ∨
      caller.body = some (.sequence
        (.returnValue (some (.call callee.id []))) .skip)) :
    48 ∉ entryStackFootprint caller := by
  rcases body with body | body <;> simp [entryStackFootprint, body]

theorem direct_body_slot_beyond_zero_mem
    (checked : DirectChecked executable image displacement)
    {supported : ExpressionFunctionCheck.BodySupported checked.callee
      checked.calleeImage.bytes}
    (mode : checked.calleeMode = .body supported)
    (slotOne : 1 < supported.checkedShape.1.allocations) :
    56 ∈ direct checked := by
  simpa using direct_body_slot_mem checked mode slotOne

end Lanius.X86.AuthenticatedStackFootprint
