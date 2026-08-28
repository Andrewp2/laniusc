export const PLAYBACK_MULTIPLIERS = [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 4, 8] as const;
export const DEFAULT_PLAYBACK_MULTIPLIER = 0.1;

export interface BounceState {
  progress: number;
  completed: number;
  forward: boolean;
}

/**
 * Map simulated elapsed time onto a repeating out-and-back course.
 * Each one-way traversal represents one completed compilation.
 */
export function bounceState(simulatedElapsedMs: number, durationMs: number): BounceState {
  if (!Number.isFinite(simulatedElapsedMs) || simulatedElapsedMs <= 0
    || !Number.isFinite(durationMs) || durationMs <= 0) {
    return { progress: 0, completed: 0, forward: true };
  }

  const traversals = simulatedElapsedMs / durationMs;
  const completed = Math.floor(traversals);
  const withinTraversal = traversals - completed;
  const forward = completed % 2 === 0;
  return {
    progress: forward ? withinTraversal : 1 - withinTraversal,
    completed,
    forward,
  };
}
