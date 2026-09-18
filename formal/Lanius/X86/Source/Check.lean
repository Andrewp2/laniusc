import Lanius.X86.Source.Patch
import Lanius.X86.Source.Fixed
import Lanius.X86.Source.Relative
import Lanius.X86.Source.Register
import Lanius.X86.Source.Encode
import Lanius.X86.Source.Direct
import Lanius.X86.Source.Condition
import Lanius.Extraction.CoreSynthesis.Provenance

namespace Lanius.X86.Source

open Lanius.Extraction Lanius.Extraction.CoreSynthesis.Program

/-- Keep exact source provenance alongside the authenticated emitter helpers.
Execution contracts consume these records, not unchecked function IDs. -/
structure CheckedBuffer (encoded : String) (sources : List SourceFile) where
  pack : CheckedCompactCoreSourcePack encoded sources
  produced : SourceBound pack
  registerValid : CheckedValidation pack.program .register
  widthValid : CheckedValidation pack.program .width
  rex : CheckedRex pack.program
  fits : CheckedFits pack.program
  registerForm : CheckedRegisterForm pack.program registerValid widthValid rex fits
  registerWrappers : (kind : RegisterWrapper) → CheckedRegisterWrapper pack.program registerForm kind
  condition : Condition.Checked pack.program registerForm
  word : CheckedWord pack.program
  patch : CheckedPatch pack.program fits word
  returnNear : CheckedFixed pack.program fits ["x86", "control"] "return_near" [195]
  syscall : CheckedFixed pack.program fits ["x86", "control"] "syscall" [15, 5]
  trap : CheckedFixed pack.program fits ["x86", "control"] "trap" [15, 11]
  relative : CheckedRelative pack.program fits word
  jump : CheckedDirect pack.program relative "jump" 233
  call : CheckedDirect pack.program relative "call" 232
  branch : CheckedBranch pack.program relative

def checkBuffer (encoded : String) (sources : List SourceFile) : Except String (CheckedBuffer encoded sources) :=
  match produced : checkCompactCoreSourcePack encoded sources with
  | .failure stage => .error ("source check failed: " ++ stage)
  | .success pack => do
      let some registerValid := checkValidation? pack.program .register
        | .error "x86.register.valid source body or signature differs"
      let some widthValid := checkValidation? pack.program .width
        | .error "x86.register.width_valid source body or signature differs"
      let some rex := checkRex? pack.program
        | .error "x86.register.rex source body or signature differs"
      let some fits := checkFits? pack.program
        | .error "x86.buffer.fits source body or signature differs"
      let some registerForm := checkRegisterForm? pack.program registerValid widthValid rex fits
        | .error "x86.encode.register_form source body, signature, or callees differ"
      let some move := checkRegisterWrapper? pack.program registerForm .move
        | .error "x86.encode.move_register source body, signature, or callee differs"
      let some multiply := checkRegisterWrapper? pack.program registerForm .multiply
        | .error "x86.encode.multiply source body, signature, or callee differs"
      let some signExtend := checkRegisterWrapper? pack.program registerForm .signExtend
        | .error "x86.encode.sign_extend_i32 source body, signature, or callee differs"
      let some zeroExtend := checkRegisterWrapper? pack.program registerForm .zeroExtend
        | .error "x86.encode.zero_extend_byte source body, signature, or callee differs"
      let some negate := checkRegisterWrapper? pack.program registerForm .negate
        | .error "x86.encode.negate source body, signature, or callee differs"
      let registerWrappers : (kind : RegisterWrapper) → CheckedRegisterWrapper pack.program registerForm kind :=
        fun | .move => move | .multiply => multiply | .signExtend => signExtend | .zeroExtend => zeroExtend | .negate => negate
      let some condition := Condition.check? pack.program registerForm
        | .error "x86.control.set_condition source body, signature, or callee differs"
      let some word := checkWord? pack.program
        | .error "x86.buffer.store_word source body or signature differs"
      let some patch := checkPatch? pack.program fits word
        | .error "x86.control.patch_relative source body, signature, or callees differ"
      let some returnNear := checkFixed? pack.program fits ["x86", "control"] "return_near" [195]
        | .error "x86.control.return_near source body, signature, or callee differs"
      let some syscall := checkFixed? pack.program fits ["x86", "control"] "syscall" [15, 5]
        | .error "x86.control.syscall source body, signature, or callee differs"
      let some trap := checkFixed? pack.program fits ["x86", "control"] "trap" [15, 11]
        | .error "x86.control.trap source body, signature, or callee differs"
      let some relative := checkRelative? pack.program fits word
        | .error "x86.control.relative source body, signature, or callees differ"
      let some jump := checkDirect? pack.program relative "jump" 233
        | .error "x86.control.jump source body, signature, or callee differs"
      let some call := checkDirect? pack.program relative "call" 232
        | .error "x86.control.call source body, signature, or callee differs"
      let some branch := checkBranch? pack.program relative
        | .error "x86.control.branch source body, signature, or callee differs"
      pure ⟨pack, produced, registerValid, widthValid, rex, fits, registerForm, registerWrappers, condition,
        word, patch, returnNear, syscall, trap, relative, jump, call, branch⟩

end Lanius.X86.Source
