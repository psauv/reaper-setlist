<script lang="ts">
	import { notifications } from '$lib';
	import { getApi } from '$lib/api/api';

	import Button from '$lib/components/Button/Button.svelte';
	import type { ReaperMarker } from '$lib/models/reaper-marker';
	import type { ReaperTab } from '$lib/models/reaper-tab';
	import {
		PLAYSTATE_PAUSED,
		PLAYSTATE_PLAYING,
		PLAYSTATE_RECORDING,
		PLAYSTATE_STOPPED,
		type PlayState,
		type ReaperTransport
	} from '$lib/models/reaper-transport';
	import type { Chunkable } from '$lib/api/reaper-backend/reaper-rpc-client.svelte';
	import { extractTagsFromMarkers, formatDuration } from '$lib/util';
	import { onDestroy, onMount } from 'svelte';
	// Icons
	import PauseIcon from 'virtual:icons/mdi/pause';
	import PlayIcon from 'virtual:icons/mdi/play';
	import RecordIcon from 'virtual:icons/mdi/record';
	import SkipNextIcon from 'virtual:icons/mdi/skip-next';
	import SkipPreviousIcon from 'virtual:icons/mdi/skip-previous';
	import StopIcon from 'virtual:icons/mdi/stop';

	const api = getApi();

	// Player state
	let allTabs = $state<ReaperTab[] | null>(null);
	let currentSongIndex = $state<number>(0);
	let playState = $state<PlayState>(PLAYSTATE_STOPPED);
	let currentSongTime = $state<number>(0);
	let totalSetTime = $derived<number>(
		!allTabs
			? 0
			: allTabs.slice(0, currentSongIndex).reduce((total, tab) => {
					return total + (tab.length || 0);
				}, 0) + currentSongTime
	);
	let transportUpdateHandle = $state<number | null>(null);
	let tabsUpdateHandle = $state<number | null>(null);

	// Current song data
	const currentTab = $derived(!allTabs || currentSongIndex < 0 || currentSongIndex >= allTabs.length ? null : allTabs[currentSongIndex] || null);

	// Song markers (placeholder data - would come from Reaper)
	let songMarkers = $state<ReaperMarker[]>([]);
	// Tags extraits en temps réel des marqueurs de l'onglet actif dans REAPER
	let liveTags = $derived(extractTagsFromMarkers(songMarkers));
	// Marqueurs visibles pour la navigation (on masque les marqueurs d'action commençant par '!')
	let visibleMarkers = $derived(songMarkers.filter((marker) => !marker.name.trim().startsWith('!')));


	async function toggleTabTag(tabIndex: number, tagName: string, currentState: boolean) {
		try {
			const nextState = !currentState;
			await api.script.setSongMarkerTags(
				tabIndex.toString(),
				{ [tagName]: nextState } as Chunkable<Record<string, boolean>>
			);
			await refreshTabs();
			if (tabIndex === currentSongIndex) {
				await refreshMarkers();
			}
		} catch (error) {
			notifications.error(`Failed to toggle tag "${tagName}": ${(error as Error).message}`);
		}
	}


	// Time calculations
	const totalSongDuration = $derived(currentTab?.length || 0);
	const remainingSongTime = $derived(Math.max(0, totalSongDuration - currentSongTime));
	const totalSetDuration = $derived(
		!allTabs
			? 0
			: allTabs.reduce((total, tab) => {
					return total + (tab.length || 0);
				}, 0)
	);
	const remainingSetTime = $derived(
		!allTabs
			? 0
			: (() => {
					let remaining = 0;
					for (let i = currentSongIndex; i < allTabs.length; i++) {
						const tab = allTabs[i];
						const songDuration = tab.length || 0;
						if (i === currentSongIndex) {
							remaining += Math.max(0, songDuration - currentSongTime);
						} else {
							remaining += songDuration;
						}
					}
					return remaining;
				})()
	);

	// Progress percentages
	const songProgress = $derived(totalSongDuration === 0 ? 0 : Math.min(100, (currentSongTime / totalSongDuration) * 100));
	const setProgress = $derived(totalSetDuration === 0 ? 0 : Math.min(100, (totalSetTime / totalSetDuration) * 100));

	// Format time for display
	function formatTime(seconds: number): string {
		const mins = Math.floor(seconds / 60);
		const secs = Math.floor(seconds % 60);
		return `${mins}:${secs.toString().padStart(2, '0')}`;
	}

	function formatTitle(title: string): string {
		// strip file extension and trim whitespace
		return title.replace(/\.[^/.]+$/, ''); // Remove file extension
	}

	// Player controls
	async function togglePlayPause() {
		try {
			if (playState === PLAYSTATE_PLAYING) {
				const transport = await api.reaper.pause();
				updateTransport(transport);
			} else if (playState === PLAYSTATE_PAUSED || playState === PLAYSTATE_STOPPED) {
				const transport = await api.reaper.play();
				updateTransport(transport);
			}
		} catch (error) {
			notifications.error(`Failed to toggle playback: ${(error as Error).message}`);
		}
	}

	async function stop() {
		try {
			const transport = await api.reaper.stop();
			updateTransport(transport);
		} catch (error) {
			notifications.error(`Failed to stop playback: ${(error as Error).message}`);
		}
	}

	async function previousTrack() {
		if (currentSongIndex > 0) {
			currentSongIndex--;
			const result = await api.reaper.previousTab();
			updateMarkers(result.markers);
			updateTransport(result.transport);
		}
	}

	async function nextTrack() {
		if (allTabs && currentSongIndex < allTabs.length - 1) {
			currentSongIndex++;
			const result = await api.reaper.nextTab();
			updateMarkers(result.markers);
			updateTransport(result.transport);
		}
	}

	async function goToMarker(marker: ReaperMarker) {
		try {
			const transport = await api.reaper.goToMarker(marker.id);
			updateTransport(transport);
		} catch (error) {
			notifications.error(`Failed to jump to marker: ${(error as Error).message}`);
			console.error(`Failed to jump to marker:`, error);
		}
	}

	async function goToStart() {
		try {
			const transport = await api.reaper.goToStart();
			updateTransport(transport);
		} catch (error) {
			notifications.error(`Failed to jump to song start: ${(error as Error).message}`);
			console.error(`Failed to jump to song start:`, error);
		}
	}

	async function startRecording() {
		try {
			const transport = await api.reaper.record();
			updateTransport(transport);
		} catch (error) {
			notifications.error(`Failed to toggle recording: ${(error as Error).message}`);
			console.error(`Failed to toggle recording:`, error);
		}
	}

	function updateTransport(transport: ReaperTransport) {
		if (transport) {
			playState = transport.playState;
			currentSongTime = transport.positionSeconds;
		} else {
			playState = PLAYSTATE_STOPPED;
			currentSongTime = 0;
		}
	}

	function updateMarkers(markers: ReaperMarker[]) {
		songMarkers = markers;
	}

	async function refreshTransport() {
		try {
			const state = await api.reaper.getTransport();
			updateTransport(state);
		} catch (error) {
			console.error(`Failed to update transport:`, error);
		}
	}

	async function refreshMarkers() {
		try {
			const markers = await api.reaper.getMarkers();
			updateMarkers(markers);
		} catch (error) {
			console.error(`Failed to load markers:`, error);
		}
	}

	async function refreshTabs() {
		try {
			const response = await api.script.getOpenTabs();
			if (allTabs !== response.tabs || currentSongIndex !== response.activeIndex) {
				allTabs = response.tabs;
				currentSongIndex = response.activeIndex;
				await refreshMarkers(); // Refresh markers after tabs update
			}

			if (currentSongIndex < 0 || currentSongIndex >= allTabs.length) {
				currentSongIndex = 0; // Reset to first song if index is out of bounds
			}
		} catch (error) {
			console.error(`Failed to refresh tabs: ${(error as Error).message}`);
		}
	}

	// Load sample data (in real app, this would come from route params)
	onMount(async () => {
		try {
			tabsUpdateHandle = window.setInterval(refreshTabs, 5000); // Refresh tabs every 5 seconds
			transportUpdateHandle = window.setInterval(refreshTransport, 1000); // Update transport every second

			await refreshTabs(); // Load initial tabs
			await refreshMarkers(); // Load initial song markers
			await refreshTransport(); // Load initial transport state
		} catch (error) {
			notifications.error(`Failed to load initial data: ${(error as Error).message}`);
			console.error(`Failed to load data: ${(error as Error).message}`);
		}
	});

	// Cleanup
	onDestroy(() => {
		if (transportUpdateHandle) {
			window.clearInterval(transportUpdateHandle);
		}
		if (tabsUpdateHandle) {
			window.clearInterval(tabsUpdateHandle);
		}
	});
</script>

<meta:head>
	<title>Player - Reaper Setlist</title>
</meta:head>

<div class="player-container">
	<h1>Live Player</h1>

	{#if allTabs && currentTab}
		<!-- Encart 1 : Lecteur unifié & Progression -->
		<div class="player-card main-player-card">
			<div class="compact-header">
				<div class="current-track-block">
					<span class="song-number">Track {currentSongIndex + 1} of {allTabs.length}</span>
					<h2 class="song-title">{formatTitle(currentTab.name)}</h2>
				</div>

				<div class="next-up-block">
					<span class="next-up-label">Next Up</span>
					{#if currentSongIndex < allTabs.length - 1}
						{@const nextTab = allTabs[currentSongIndex + 1]}
						{#if nextTab}
							<span class="next-song-name">{formatTitle(nextTab.name)} ({formatDuration(nextTab.length)})</span>
						{/if}
					{:else}
						<span class="set-complete">Set Complete!</span>
					{/if}
				</div>
			</div>

			<!-- Barre de contrôle séparée : Transport à gauche / Navigation à droite -->
			<div class="unified-controls">
				<div class="control-group transport-group">
					<Button variant="icon" onclick={stop} color={playState === PLAYSTATE_PLAYING || playState === PLAYSTATE_PAUSED ? 'delete' : 'primary'}>
						<StopIcon />
					</Button>

					<Button variant="icon" onclick={togglePlayPause} color="success">
						{#if playState === PLAYSTATE_PLAYING}
							<PauseIcon />
						{:else}
							<PlayIcon />
						{/if}
					</Button>

					<Button variant="icon" onclick={startRecording} color={playState === PLAYSTATE_RECORDING ? 'delete' : 'primary'}>
						<RecordIcon />
					</Button>
				</div>

				<div class="control-group navigation-group">
					<Button variant="icon" onclick={previousTrack} disabled={currentSongIndex === 0} color="secondary">
						<SkipPreviousIcon />
					</Button>

					<Button variant="icon" onclick={nextTrack} disabled={!allTabs || currentSongIndex >= allTabs.length - 1} color="secondary">
						<SkipNextIcon />
					</Button>
				</div>
			</div>


			<!-- Barres de progression compactes -->
			<div class="compact-progress-list">
				<div class="progress-group">
					<div class="progress-label">
						<span>Song Progress</span>
						<span class="time-display">{formatTime(currentSongTime)} / {formatTime(totalSongDuration)} (-{formatTime(remainingSongTime)})</span>
					</div>
					<div class="progress-bar-container">
						<div class="progress-bar">
							<div class="progress-fill" style="width: {songProgress}%"></div>
							<div class="progress-handle" style="left: {songProgress}%"></div>
						</div>
					</div>
				</div>

				<div class="progress-group">
					<div class="progress-label">
						<span>Set Progress</span>
						<span class="time-display">{formatTime(totalSetTime)} / {formatTime(totalSetDuration)} (-{formatTime(remainingSetTime)})</span>
					</div>
					<div class="progress-bar-container">
						<div class="progress-bar set-progress-bar">
							<div class="progress-fill" style="width: {setProgress}%"></div>
							<div class="progress-handle" style="left: {setProgress}%"></div>
						</div>
					</div>
				</div>
			</div>
		</div>

		<!-- Encart 2 : Song Markers -->
		<div class="markers-section">
			<h3>Song Markers</h3>
			<div class="markers-grid">
				<button class="marker-button" onclick={() => goToStart()}>
					<div class="marker-name">Start</div>
					<div class="marker-time">{formatTime(0)}</div>
				</button>
				{#each visibleMarkers as marker (marker.id)}
					<button class="marker-button" onclick={() => goToMarker(marker)}>
						<div class="marker-name">{marker.name}</div>
						<div class="marker-time">{formatTime(marker.position)}</div>
					</button>
				{/each}
			</div>
		</div>

		<!-- Encart 3 : Vue d'ensemble des onglets & contrôle des tags à la volée -->
		<div class="tabs-overview-section">
			<h3>Setlist Tabs & Live Tags</h3>
			<div class="tabs-list">
				{#each allTabs as tab (tab.index)}
					<div class="tab-row" class:active-tab={tab.index === currentSongIndex}>
						<div class="tab-row-info">
							<span class="tab-index">#{tab.index + 1}</span>
							<span class="tab-title">{formatTitle(tab.name)}</span>
							<span class="tab-duration">{formatDuration(tab.length)}</span>
						</div>

						{#if tab.tags && Object.keys(tab.tags).length > 0}
							<div class="tab-tags">
								{#each Object.entries(tab.tags) as [tagName, isActive] (tagName)}
									<button
										type="button"
										class="live-tag-toggle"
										class:active={isActive}
										onclick={() => toggleTabTag(tab.index, tagName, isActive)}
									>
										{tagName}: {isActive ? 'ON' : 'OFF'}
									</button>
								{/each}
							</div>
						{/if}
					</div>
				{/each}
			</div>
		</div>
	{:else}
		<div class="no-setlist">
			<h2>No Setlist Loaded</h2>
			<p>Please load a setlist to begin playing.</p>
			<Button elementType="a" href="#/" color="primary">Browse Setlists</Button>
		</div>
	{/if}
</div>


<style>
	.player-container {
		margin: 0 auto;
		padding: 1.5rem;
		display: flex;
		flex-direction: column;
		gap: 1.25rem;
		width: 100%;
		box-sizing: border-box;
	}

	/* Encart 1 : Lecteur unifié compact */
	.main-player-card {
		display: flex;
		flex-direction: column;
		gap: 1.25rem;
		padding: 1.5rem;
		background: var(--background);
		border-radius: 1rem;
		border: 2px solid var(--current-line);
	}

	.compact-header {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: 1rem;
		flex-wrap: wrap;
	}

	.current-track-block {
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
	}

	.song-number {
		color: var(--comment);
		font-size: 0.9rem;
	}

	.song-title {
		margin: 0;
		font-size: 2rem;
		font-weight: 700;
		color: var(--primary);
	}

	.next-up-block {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 0.25rem;
		text-align: right;
	}

	.next-up-label {
		font-size: 0.85rem;
		color: var(--comment);
		text-transform: uppercase;
		letter-spacing: 0.05em;
	}

	.next-song-name {
		font-weight: 600;
		color: var(--foreground);
	}

	.set-complete {
		color: var(--green);
		font-weight: 600;
	}

	.unified-controls {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		align-items: center;
		gap: 1rem;
		padding: 0.75rem 0;
		border-top: 1px solid var(--current-line);
		border-bottom: 1px solid var(--current-line);
	}

	.control-group {
		display: flex;
		align-items: center;
		gap: 0.75rem;
	}

	@media (max-width: 480px) {
		.unified-controls {
			justify-content: center;
		}
	}

	.compact-progress-list {
		display: flex;
		flex-direction: column;
		gap: 0.85rem;
	}

	.progress-group {
		display: flex;
		flex-direction: column;
		gap: 0.35rem;
	}

	.progress-label {
		display: flex;
		justify-content: space-between;
		align-items: center;
		font-size: 0.9rem;
		font-weight: 600;
		color: var(--foreground);
	}

	.time-display {
		font-family: monospace;
		font-size: 0.95rem;
		color: var(--comment);
	}

	.progress-bar-container {
		padding: 0.25rem 0;
	}

	.progress-bar {
		position: relative;
		height: 8px;
		background: var(--current-line);
		border-radius: 4px;
		overflow: hidden;
	}

	.progress-fill {
		height: 100%;
		background: linear-gradient(90deg, var(--green), var(--cyan));
		border-radius: 4px;
		transition: width 0.3s ease;
	}

	.set-progress-bar .progress-fill {
		background: linear-gradient(90deg, var(--purple), var(--pink));
	}

	.progress-handle {
		position: absolute;
		top: 50%;
		transform: translate(-50%, -50%);
		width: 14px;
		height: 14px;
		background: var(--foreground);
		border-radius: 50%;
		border: 2px solid var(--background);
		transition: left 0.3s ease;
	}

	/* Encart 2 : Song Markers */
	.markers-section {
		background: var(--background);
		border-radius: 0.75rem;
		border: 1px solid var(--current-line);
		padding: 1.25rem;
	}

	.markers-section h3 {
		margin: 0 0 0.85rem 0;
		font-size: 1.1rem;
		color: var(--foreground);
	}

	.markers-grid {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
		gap: 0.65rem;
	}

	.marker-button {
		padding: 0.65rem;
		background: var(--current-line);
		border: 1px solid var(--comment);
		border-radius: 0.5rem;
		cursor: pointer;
		transition: all 0.2s ease;
		color: var(--foreground);
	}

	.marker-button:hover {
		background: var(--selection);
		border-color: var(--primary);
	}

	.marker-name {
		font-weight: 600;
		margin-bottom: 0.2rem;
	}

	.marker-time {
		font-size: 0.8rem;
		color: var(--comment);
		font-family: monospace;
	}

	/* Encart 3 : Vue d'ensemble des onglets & Tags live */
	.tabs-overview-section {
		background: var(--background);
		border-radius: 0.75rem;
		border: 1px solid var(--current-line);
		padding: 1.25rem;
	}

	.tabs-overview-section h3 {
		margin: 0 0 0.85rem 0;
		font-size: 1.1rem;
		color: var(--foreground);
	}

	.tabs-list {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
	}

	.tab-row {
		display: flex;
		justify-content: space-between;
		align-items: center;
		flex-wrap: wrap;
		gap: 0.75rem;
		padding: 0.75rem 1rem;
		background: var(--current-line);
		border-radius: 0.5rem;
		border-left: 4px solid transparent;
	}

	.tab-row.active-tab {
		border-left-color: var(--primary);
		background: hsl(from var(--current-line) h s calc(l * 1.15));
	}

	.tab-row-info {
		display: flex;
		align-items: center;
		gap: 0.65rem;
	}

	.tab-index {
		font-family: monospace;
		color: var(--comment);
		font-size: 0.85rem;
	}

	.tab-title {
		font-weight: 600;
		color: var(--foreground);
	}

	.tab-duration {
		font-family: monospace;
		font-size: 0.85rem;
		color: var(--comment);
	}

	.tab-tags {
		display: flex;
		flex-wrap: wrap;
		gap: 0.4rem;
	}

	.live-tag-toggle {
		font-size: 0.8rem;
		padding: 0.3rem 0.65rem;
		border-radius: 0.35rem;
		border: 1px solid var(--comment);
		background: var(--background);
		color: var(--comment);
		cursor: pointer;
		transition: all 0.15s ease;
	}

	.live-tag-toggle.active {
		background: var(--green, #50fa7b);
		border-color: var(--green, #50fa7b);
		color: var(--background, #282a36);
		font-weight: 600;
	}

	.no-setlist {
		text-align: center;
		padding: 4rem 2rem;
		background: var(--background);
		border-radius: 1rem;
		border: 2px dashed var(--current-line);
	}

	.no-setlist h2 {
		margin: 0 0 1rem 0;
		color: var(--comment);
	}

	.no-setlist p {
		margin: 0 0 2rem 0;
		color: var(--comment);
	}

	@media (max-width: 768px) {
		.player-container {
			padding: 1rem;
			gap: 1rem;
		}

		.main-player-card {
			padding: 1rem;
		}

		.song-title {
			font-size: 1.5rem;
		}

		.next-up-block {
			align-items: flex-start;
			text-align: left;
		}

		.unified-controls {
			gap: 0.65rem;
		}
	}
</style>

