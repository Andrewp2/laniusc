# FrontEndStmtDepthV2

- 11-03 (leafA): replaces FrontEndStmtDepth, for PreCompileWords.red4. The bound is the front end's
  `depth_limit()` check in `untyped_rejected` (`lim_funcs`), an implementation limit like the image limit
  (SEMANTIC_DECISIONS "The front end's implementation limits"). Proof: `SelfPre/Limits.lean`
  (`frontEndWords_limits`).
