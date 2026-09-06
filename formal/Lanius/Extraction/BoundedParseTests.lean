import Lanius.Extraction.BoundedParse

namespace Lanius.Extraction.BoundedParseTests

private def grammar : Grammar := ⟨0, 1, 0, 0, 0, [], [⟨0, []⟩]⟩
private def nodes : List ParseNode :=
  [⟨0,0,0,0,[]⟩, ⟨0,0,0,0,[]⟩, ⟨0,0,0,0,[]⟩]

-- Uneven final chunk, empty table, and nonzero initial node id.
theorem uneven : checkNodesFromFast grammar [] nodes 0 nodes = true := by
  kernel_parse_bounded 2
example : checkNodesFromFast grammar [] nodes 0 nodes = true := by
  kernel_parse_bounded_known 2 3
example : checkNodesFromFast grammar [] [] 0 [] = true := by
  kernel_parse_bounded 2
example : checkNodesFromFast grammar [] nodes 7 nodes = true := by
  kernel_parse_bounded 1

-- A malformed production must not acquire a successful chunk certificate.
example : checkNodesFromFast grammar [] [⟨1,0,0,0,[]⟩] 0 [⟨1,0,0,0,[]⟩] = false := by
  fail_if_success kernel_parse_bounded 1
  kernel_rfl

#print axioms uneven
end Lanius.Extraction.BoundedParseTests
