import assert from 'node:assert/strict';
import test from 'node:test';

import { bounceState, DEFAULT_PLAYBACK_MULTIPLIER, PLAYBACK_MULTIPLIERS } from './race.ts';

test('playback speeds include slow video-friendly options without changing the default', () => {
  assert.equal(PLAYBACK_MULTIPLIERS[0], 0.005);
  assert.equal(DEFAULT_PLAYBACK_MULTIPLIER, 0.1);
  assert.ok(PLAYBACK_MULTIPLIERS.every((value, index) => index === 0 || value > PLAYBACK_MULTIPLIERS[index - 1]));
});

test('one-way trips represent completed compilations and alternate direction', () => {
  assert.deepEqual(bounceState(0, 100), { progress: 0, completed: 0, forward: true });
  assert.deepEqual(bounceState(50, 100), { progress: 0.5, completed: 0, forward: true });
  assert.deepEqual(bounceState(100, 100), { progress: 1, completed: 1, forward: false });
  assert.deepEqual(bounceState(150, 100), { progress: 0.5, completed: 1, forward: false });
  assert.deepEqual(bounceState(200, 100), { progress: 0, completed: 2, forward: true });
});

test('different durations preserve their relative compile rates', () => {
  const fast = bounceState(1_000, 50);
  const slow = bounceState(1_000, 200);

  assert.equal(fast.completed, 20);
  assert.equal(slow.completed, 5);
  assert.equal(fast.completed / slow.completed, 4);
});

test('invalid timing inputs remain at the starting edge', () => {
  const stopped = { progress: 0, completed: 0, forward: true };
  assert.deepEqual(bounceState(Number.NaN, 100), stopped);
  assert.deepEqual(bounceState(100, 0), stopped);
  assert.deepEqual(bounceState(100, Number.POSITIVE_INFINITY), stopped);
});
