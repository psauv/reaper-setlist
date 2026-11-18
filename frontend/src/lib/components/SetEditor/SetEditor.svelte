<script lang="ts" module>
	type SetlistLike = Setlist | NewSetlist;

	export interface SetEditorProps<T extends SetlistLike> {
		setlist: T;
		songs: Database<Song>;
		onSubmit: (setlist: T) => void;
	}
</script>

<script lang="ts">
	import { flip } from 'svelte/animate';
	import { fade, fly } from 'svelte/transition';
	import Button from '../Button/Button.svelte';
	import Form from '../Form/Form.svelte';

	import type { Database } from '$lib/models/database';
	import type { NewSetlist, Setlist } from '$lib/models/setlist';
	import type { Song } from '$lib/models/song';
	import { formatDuration } from '$lib/util';
	import DeleteIcon from 'virtual:icons/mdi/delete';
	import Draggable from '../Draggable/Draggable.svelte';

	// eslint-disable-next-line no-undef
	type T = $$Generic<SetlistLike>;

	let { setlist: initialSetlist, songs, onSubmit }: SetEditorProps<T> = $props();

	// Helper pour cloner proprement un objet réactif Svelte sans utiliser structuredClone
	function cloneSongTags(tags?: Record<string, Record<string, boolean>>): Record<string, Record<string, boolean>> {
		if (!tags) return {};
		const copy: Record<string, Record<string, boolean>> = {};
		for (const [songId, songTagMap] of Object.entries(tags)) {
			copy[songId] = { ...songTagMap };
		}
		return copy;
	}

	let setlist = $state({
		...initialSetlist,
		songTags: cloneSongTags(initialSetlist.songTags)
	});

	let remainingSongs = $derived(
		Object.values(songs)
			.filter((s) => !setlist.songs.includes(s.id))
			.toSorted((a, b) => a.name.localeCompare(b.name))
	);

	let newSongId = $state<string | null>(
		Object.values(songs)
			.filter((s) => !setlist.songs.includes(s.id))
			.toSorted((a, b) => a.name.localeCompare(b.name))[0]?.id || null
	);
	let totalTime = $derived(setlist.songs.reduce((acc, songId) => acc + (songs[songId]?.length ?? 0) || 0, 0));

	let draggingIndex: number | undefined = $state(undefined);
	let draggingTargetIndex: number | undefined = $state(undefined);
	let itemsRef: HTMLDivElement | undefined = $state(undefined);

	function addSongToSetlist() {
		if (!newSongId || !songs[newSongId]) return;
		const song = songs[newSongId];
		if (song) {
			setlist.songs.push(song.id);
			setlist.songTags[song.id] = { ...(song.defaultTags ?? {}) };
			newSongId = remainingSongs[0]?.id || null;
		}
	}

	function removeSongFromSetlist(index: number, songId: string) {
		setlist.songs.splice(index, 1);
		delete setlist.songTags[songId];
	}

	function toggleSongTag(songId: string, tagName: string) {
		if (!setlist.songTags[songId]) {
			setlist.songTags[songId] = { ...(songs[songId]?.defaultTags ?? {}) };
		}
		setlist.songTags[songId][tagName] = !setlist.songTags[songId][tagName];
	}

	function getMiddle(element: HTMLElement) {
		const rect = element.getBoundingClientRect();
		return rect.top + rect.height / 2;
	}

	function onDragMove(y: number) {
		if (!itemsRef) return;
		const childElements = Array.from(itemsRef.querySelectorAll<HTMLDivElement>('.list-item'));

		const closest = childElements.reduce((prev, curr) => (Math.abs(getMiddle(curr) - y) < Math.abs(getMiddle(prev) - y) ? curr : prev));
		if (y < getMiddle(closest)) {
			draggingTargetIndex = childElements.indexOf(closest);
		} else {
			draggingTargetIndex = childElements.indexOf(closest) + 1;
		}
	}

	function onDragStart(index: number) {
		draggingIndex = index;
	}

	function onDragEnd() {
		if (draggingIndex !== undefined && draggingTargetIndex !== undefined) {
			const removedItem = setlist.songs.splice(draggingIndex, 1)[0];
			const adjustedIndex = draggingTargetIndex > draggingIndex ? draggingTargetIndex - 1 : draggingTargetIndex;
			setlist.songs.splice(adjustedIndex, 0, removedItem);
		}
		draggingIndex = undefined;
		draggingTargetIndex = undefined;
	}
</script>

<Form onsubmit={() => onSubmit(setlist)}>
	<div class="form-group">
		<label for="venue">Venue:</label>
		<input type="text" id="venue" bind:value={setlist.venue} placeholder="Enter venue name" required />
	</div>

	<div class="form-group">
		<label for="date">Date:</label>
		<input
			type="date"
			id="date"
			value={new Date(setlist.date).toISOString().split('T')[0]}
			onchange={({ currentTarget: { value: v } }) => (setlist.date = v ? new Date(v).toISOString() : new Date().toISOString())}
			required
		/>
	</div>

	<div class="songs-container">
		<h2>Songs</h2>
		<dl>
			<dt>Total time:</dt>
			<dd>{formatDuration(totalTime)}</dd>
		</dl>
		<div class="items" bind:this={itemsRef}>
			{#each setlist.songs as songId, i (i)}
				<div class="item-container" animate:flip={{ duration: 300 }} transition:fly={{ duration: 300 }}>
					{#if draggingTargetIndex === i}
						<div class="drag-target" in:fade={{ duration: 200 }}></div>
					{/if}
					<div class="list-item" class:dragging={draggingIndex === i}>
						<Draggable onmove={(y) => onDragMove(y)} onstart={() => onDragStart(i)} onend={() => onDragEnd()} />
						<div class="song-info">
							<span class="song-name">{songs[songId]?.name}</span>
							<span class="song-duration">{formatDuration(songs[songId]?.length || 0)}</span>
							{#if setlist.songTags?.[songId] && Object.keys(setlist.songTags[songId]).length > 0}
								<div class="song-tags">
									{#each Object.entries(setlist.songTags[songId]) as [tagName, isActive] (tagName)}
										<button
											type="button"
											class="tag-toggle"
											class:active={isActive}
											onclick={() => toggleSongTag(songId, tagName)}
										>
											{tagName}: {isActive ? 'ON' : 'OFF'}
										</button>
									{/each}
								</div>
							{/if}
						</div>
						<Button color="delete" onclick={() => removeSongFromSetlist(i, songId)} variant="icon"><DeleteIcon /></Button>
					</div>
				</div>
			{/each}
			{#if draggingTargetIndex === setlist.songs.length}
				<div class="drag-target"></div>
			{/if}
		</div>
	</div>

	{#if remainingSongs.length > 0}
		<div class="form-group">
			<label for="new-song">Add Song:</label>
			<div class="add-song-container input-with-button">
				<select id="new-song" bind:value={newSongId}>
					{#each remainingSongs as song (song.id)}
						<option value={song.id}>{song.name}</option>
					{/each}
				</select>
				<Button elementType="button" onclick={addSongToSetlist} disabled={newSongId === null}>Add</Button>
			</div>
		</div>
	{:else}
		<p>No songs left to add</p>
	{/if}

	<div class="submit-section">
		<Button elementType="submit">Save</Button>
	</div>
</Form>

<style>
	.add-song-container {
		display: flex;
		gap: 0.5rem;
		align-items: center;
	}

	.add-song-container select {
		flex: 1;
	}

	.songs-container {
		margin-top: 1rem;
	}

	.songs-container h2 {
		margin-bottom: 1rem;
		font-size: 1.25rem;
		color: var(--foreground);
	}

	.songs-container dl {
		margin: 0 0 1rem 0;
		padding: 0;
		display: flex;
		gap: 1rem;
		align-items: center;
	}

	.songs-container dt {
		font-weight: 500;
		color: var(--foreground);
		margin: 0;
	}

	.songs-container dd {
		margin: 0;
		color: var(--foreground);
		font-family: monospace;
		font-weight: 600;
		font-size: 1.1rem;
	}

	.items {
		display: flex;
		flex-direction: column;
		gap: 0.5rem;
		margin-bottom: 1rem;
	}

	.list-item {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		padding: 0.75rem;
		background: var(--current-line);
		border-radius: 0.5rem;
		border: 1px solid transparent;
		transition: border-color 0.2s ease;
	}

	.song-name {
		color: var(--foreground);
		font-weight: 500;
	}

	.song-info {
		flex-grow: 1;
		display: flex;
		flex-direction: column;
		gap: 0.25rem;
	}

	.song-duration {
		color: var(--comment);
		font-family: monospace;
		font-size: 0.875rem;
	}

	.song-tags {
		display: flex;
		flex-wrap: wrap;
		gap: 0.375rem;
		margin-top: 0.25rem;
	}

	.tag-toggle {
		font-size: 0.75rem;
		padding: 0.2rem 0.5rem;
		border-radius: 0.25rem;
		border: 1px solid var(--comment);
		background: transparent;
		color: var(--comment);
		cursor: pointer;
		transition: all 0.15s ease;
	}

	.tag-toggle.active {
		background: var(--green, #50fa7b);
		border-color: var(--green, #50fa7b);
		color: var(--background, #282a36);
		font-weight: 600;
	}

	.dragging {
		background-color: var(--black);
		border-color: var(--orange);
	}

	.drag-target {
		height: 3px;
		background-color: var(--orange);
		width: 100%;
		border-radius: 1.5px;
		margin: 0.25rem 0;
	}
</style>
