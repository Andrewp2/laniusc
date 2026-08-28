<script lang="ts">
  import { onMount } from 'svelte';

  import { formatComparisonMs } from '../lib/format';
  import { bounceState, DEFAULT_PLAYBACK_MULTIPLIER, PLAYBACK_MULTIPLIERS } from '../lib/race';

  interface RaceValue {
    name: string;
    value: number;
    color: string;
    contextOnly?: boolean;
  }

  interface Props {
    values: RaceValue[];
    accessibleName?: string;
  }

  let { values, accessibleName = 'Animated compile time comparison' }: Props = $props();
  let stage: HTMLDivElement;
  let simulatedElapsedMs = $state(0);
  let speedIndex = $state(PLAYBACK_MULTIPLIERS.indexOf(DEFAULT_PLAYBACK_MULTIPLIER));
  let userPlaying = $state(true);
  let inViewport = $state(false);
  let pageVisible = $state(true);
  let reducedMotion = $state(false);
  const speed = $derived(PLAYBACK_MULTIPLIERS[speedIndex]);
  const states = $derived(values.map((value) => bounceState(simulatedElapsedMs, value.value)));

  $effect(() => {
    if (!userPlaying || !inViewport || !pageVisible) return;
    let frame = 0;
    let previous = performance.now();
    const tick = (now: number) => {
      const delta = Math.min(100, Math.max(0, now - previous));
      previous = now;
      simulatedElapsedMs += delta * speed;
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  });

  onMount(() => {
    const motionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
    reducedMotion = motionQuery.matches;
    if (reducedMotion) userPlaying = false;

    const updateMotionPreference = (event: MediaQueryListEvent) => {
      reducedMotion = event.matches;
      if (event.matches) userPlaying = false;
    };
    const updateVisibility = () => pageVisible = document.visibilityState === 'visible';
    const observer = new IntersectionObserver(([entry]) => inViewport = entry.isIntersecting, {
      rootMargin: '100px 0px',
    });
    observer.observe(stage);
    motionQuery.addEventListener('change', updateMotionPreference);
    document.addEventListener('visibilitychange', updateVisibility);

    return () => {
      observer.disconnect();
      motionQuery.removeEventListener('change', updateMotionPreference);
      document.removeEventListener('visibilitychange', updateVisibility);
    };
  });

  function restart(): void {
    simulatedElapsedMs = 0;
    userPlaying = true;
  }
</script>

<div class="race" bind:this={stage} role="group" aria-label={accessibleName}>
  <div class="race-stage">
    {#each values as value, index}
      {@const state = states[index]}
      <div class:context-only={value.contextOnly} class="race-row" style={`--series:${value.color}`}>
        <div class="race-identity">
          <span class="race-swatch"></span>
          <strong>{value.name}</strong>
        </div>
        <div class="race-track" aria-hidden="true">
          <span class:reverse={!state.forward} class="race-ball" style={`--race-progress:${state.progress}`}></span>
        </div>
        <strong class="race-time">{formatComparisonMs(value.value)}</strong>
        <span class="race-count" aria-label={`${state.completed.toLocaleString()} completed compiles`}>
          <strong>{state.completed.toLocaleString()}</strong>
          <small>compiles</small>
        </span>
      </div>
    {/each}
  </div>

  <div class="race-controls">
    <div class="playback-actions">
      <button type="button" class="primary-action" onclick={() => userPlaying = !userPlaying}>
        {userPlaying ? 'Pause' : 'Play'}
      </button>
      <button type="button" onclick={restart}>Restart</button>
    </div>
    <label class="speed-control">
      <span><strong>Playback speed</strong><output>{speed}×</output></span>
      <input
        type="range"
        min="0"
        max={PLAYBACK_MULTIPLIERS.length - 1}
        step="1"
        value={speedIndex}
        aria-valuetext={`${speed} times real time`}
        oninput={(event) => speedIndex = Number(event.currentTarget.value)}
      />
      <span class="speed-range"><small>{PLAYBACK_MULTIPLIERS[0]}×</small><small>real time</small><small>{PLAYBACK_MULTIPLIERS.at(-1)}×</small></span>
    </label>
  </div>

  {#if reducedMotion && !userPlaying}
    <p class="motion-note">Animation is paused to honor your reduced-motion preference. Press Play to preview it.</p>
  {/if}
</div>

<style>
  .race { min-height: 250px; }
  .race-stage {
    display: grid;
    grid-template-columns: max-content minmax(280px, 1fr) max-content 70px;
    column-gap: 8px;
    overflow: hidden;
    border-block: 1px solid var(--line);
    background: #0b1017;
  }
  .race-row {
    grid-column: 1 / -1;
    display: grid;
    grid-template-columns: subgrid;
    align-items: center;
    min-height: 54px;
    padding: 8px 12px;
  }
  .race-row + .race-row { border-top: 1px solid var(--line); }
  .race-row.context-only { opacity: .56; }
  .race-row.context-only .race-identity strong { text-decoration: line-through; }
  .race-identity { display: flex; align-items: center; gap: 9px; min-width: 0; }
  .race-identity strong {
    overflow: hidden;
    font-size: 11px;
    font-weight: 650;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .race-swatch { flex: 0 0 auto; width: 8px; height: 8px; border-radius: 50%; background: var(--series); }
  .race-track {
    position: relative;
    container-type: inline-size;
    height: 24px;
    border-radius: 999px;
    background:
      linear-gradient(90deg, transparent 49.8%, var(--line) 50%, transparent 50.2%),
      #080c12;
    box-shadow: inset 0 0 0 1px var(--line);
  }
  .race-ball {
    position: absolute;
    top: 3px;
    left: 0;
    width: 18px;
    height: 18px;
    border-radius: 50%;
    background: radial-gradient(circle at 35% 30%, color-mix(in srgb, white 76%, var(--series)), var(--series) 43%, color-mix(in srgb, black 48%, var(--series)) 100%);
    box-shadow: 0 2px 11px color-mix(in srgb, var(--series) 42%, transparent);
    transform: translate3d(calc(var(--race-progress) * (100cqw - 18px)), 0, 0);
    will-change: transform;
  }
  .race-ball::after {
    position: absolute;
    inset: 6px 3px 3px 8px;
    border-radius: 50%;
    background: rgb(0 0 0 / 22%);
    content: '';
    transform: rotate(-30deg);
  }
  .race-ball.reverse::after { inset: 6px 8px 3px 3px; transform: rotate(30deg); }
  .race-time, .race-count { font-variant-numeric: tabular-nums; white-space: nowrap; }
  .race-time { font-size: 11px; text-align: left; }
  .race-count { text-align: right; }
  .race-count { display: grid; justify-items: end; line-height: 1.15; }
  .race-count strong { font-size: 13px; }
  .race-count small { margin-top: 2px; font-size: 8px; letter-spacing: .07em; text-transform: uppercase; }
  .race-controls {
    display: grid;
    grid-template-columns: auto minmax(320px, 560px);
    justify-content: space-between;
    align-items: center;
    gap: 28px;
    margin-top: 16px;
  }
  .playback-actions { display: flex; gap: 7px; }
  .playback-actions button {
    min-width: 76px;
    min-height: 38px;
    border: 1px solid var(--line);
    border-radius: 7px;
    background: #0b1118;
    color: var(--muted);
    padding: 6px 13px;
    font: inherit;
    font-weight: 650;
  }
  .playback-actions button:hover { border-color: var(--line-strong); color: var(--text); }
  .playback-actions button.primary-action { border-color: color-mix(in srgb, var(--cyan) 52%, var(--line)); color: var(--cyan); }
  .playback-actions button:focus-visible, .speed-control input:focus-visible { outline: 2px solid var(--focus); outline-offset: 2px; }
  .speed-control { display: grid; gap: 7px; }
  .speed-control > span { display: flex; justify-content: space-between; align-items: baseline; gap: 20px; }
  .speed-control strong { color: var(--muted); font-size: 10px; letter-spacing: .08em; text-transform: uppercase; }
  .speed-control output { color: var(--text); font-size: 14px; font-weight: 750; font-variant-numeric: tabular-nums; }
  .speed-control input { width: 100%; height: 18px; margin: 0; accent-color: var(--cyan); cursor: pointer; }
  .speed-control .speed-range { color: var(--muted); }
  .speed-range small:nth-child(2) { text-transform: uppercase; letter-spacing: .08em; }
  .motion-note { margin-top: 12px; font-size: 11px; }

  @media (max-width: 760px) {
    .race-stage { display: block; }
    .race-controls { align-items: start; grid-template-columns: 1fr; }
    .race-row { grid-template-columns: minmax(0, 1fr) 78px 62px; gap: 8px 12px; padding-block: 10px; }
    .race-track { grid-column: 1 / -1; grid-row: 2; }
    .race-time { grid-column: 2; grid-row: 1; }
    .race-count { grid-column: 3; grid-row: 1; }
    .race-controls { gap: 18px; }
    .speed-control { width: 100%; }
  }

  @media (max-width: 520px) {
    .race-row { grid-template-columns: minmax(0, 1fr) 76px; }
    .race-count { display: none; }
    .playback-actions { width: 100%; }
    .playback-actions button { flex: 1; }
  }

  @media (prefers-reduced-motion: reduce) {
    .race-ball { will-change: auto; }
  }
</style>
