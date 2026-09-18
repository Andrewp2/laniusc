import Lanius.X86.Select.Input
import Lanius.X86.Lower.Parameter

namespace Lanius.X86.Lower.Parameter

def Checked.selectorInput (checked : Checked function) : Select.Input where
  functionId := function.id
  ids := function.parameters.map Prod.fst
  position := ⟨checked.position.val, by rw [List.length_map]; exact checked.position.isLt⟩
  trailing := checked.trailingSkip
  countBound := by simpa using checked.registerArguments
  distinct := checked.distinct
  idsBound := by
    intro id member
    change id ∈ function.parameters.map Prod.fst at member
    obtain ⟨parameter, present, equal⟩ := List.mem_map.mp member
    rw [← equal]
    exact checked.idsBound parameter present
  functionBound := checked.functionIdBound

theorem Checked.selector_words (checked : Checked function) : checked.selectorInput.words = checked.words := by
  cases trailing : checked.trailingSkip <;>
    simp [Select.Input.words, Select.Input.headerWords, Select.Input.fieldWords, Select.Input.bodyWords,
      Select.Input.bodyLength, Select.Input.returnedId, Checked.words, Checked.selectorInput,
      trailing, List.flatMap_map, List.append_assoc]

theorem Checked.selector_position (checked : Checked function) :
    checked.selectorInput.position.val = checked.position.val := rfl

end Lanius.X86.Lower.Parameter
