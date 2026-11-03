# ValidateFilesHeight

- SelfPre/Validate.lean has the attach cursor invariant (attach_ok) and pre_validate_files; a tree's
  height is at most its node count plus its tokens' height, the node count at most the attach fuel.
- leafA 11-03: proved (Proof.lean) without node counts: attach's children with fuel f are at most
  f + T high (T bounds the cursor's tokens; a `>>` must start below T so its second half stays
  within T). validateTree's fuel 2*(prods+tokens)+2 gives hb root ≤ 5 * hb f + 5.
