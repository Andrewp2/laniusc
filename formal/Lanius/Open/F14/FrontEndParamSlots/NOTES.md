# FrontEndParamSlots

- 11-03 (leafA): for leafB (PreCompileSourceV3 looked false: `params_size` adds 2^43 parameters of 2^22 slots
  past 2^64). The bound is the front end's `lim_param_slots` check in `lim_funcs`. Struct fields need no
  statement of their own: a struct's size is its fields' total, at most `weightLimit` by FrontEndTypeSlots.
  `frame_block` (a sum over every let of a body, not along one scope) is not covered.
  Proof: `SelfPre/Limits.lean` (`frontEndWords_limits`).
