<script lang="ts" module>
	type SongLike = Song | NewSong;

	import { notifications } from '$lib';
	import { getApi } from '$lib/api/api';
	import Button from '$lib/components/Button/Button.svelte';
	import type { Database } from '$lib/models/database';
	import type { NewSong, Song } from '$lib/models/song';
	import { extractTagsFromMarkers } from '$lib/util';

	export interface SongEditorProps<T extends SongLike> {
		song: T;
		songs: Database<Song>;
		projects: string[];
		onSubmit: (song: T) => void;
	}
</script>

<script lang="ts">
	import Form from '../Form/Form.svelte';

	const api = getApi();

	// eslint-disable-next-line no-undef
	type T = $$Generic<SongLike>;
	let { song: originalSong, onSubmit, projects, songs }: SongEditorProps<T> = $props();
	const song = $state({
		...originalSong,
		defaultTags: { ...(originalSong.defaultTags ?? {}) }
	});
	const duration = $derived(getDuration(song.length));
	const tagEntries = $derived(
		Object.entries(song.defaultTags ?? {}).toSorted((a, b) => a[0].localeCompare(b[0]))
	);


	let hideUsedProjects = $state(true);

	const usedProjects = $derived(
		Object.values(songs)
			.filter((s) => s.id !== song.id)
			.map((s) => s.path)
	);

	const filteredProjects = $derived(
		hideUsedProjects ? projects.filter((project) => !usedProjects.includes(project)) : projects
	);

	function getDuration(length: number) {
		const minutes = Math.floor(length / 60);
		const seconds = length % 60;
		return `${minutes}:${seconds.toString().padStart(2, '0')}`;
	}

	function handleProjectSelect(projectPath: string) {
		song.path = projectPath;
		const pathSegments = projectPath.split(/[/\\]/);
		const filename = pathSegments[pathSegments.length - 1];
		const nameWithoutExtension = filename.replace(/\.[^/.]+$/, '');
		song.name = nameWithoutExtension;
	}

	async function handleGetFromReaperClick() {
		const openTabs = await api.script.getOpenTabs();
		const activeTab = openTabs.tabs[openTabs.activeIndex];
		let openedNewTab = false;

		if (!activeTab || !song.path.endsWith(activeTab.name)) {
			await api.reaper.newTab();
			await api.script.openProject(song.path);
			openedNewTab = true;
		}

		song.length = Math.ceil(await api.script.getProjectLength());
		const markers = await api.reaper.getMarkers();
		song.defaultTags = extractTagsFromMarkers(markers);

		if (openedNewTab) {
			await api.reaper.closeTab();
		}

		const tagCount = Object.keys(song.defaultTags).length;
		notifications.success(`Duration and ${tagCount} tag(s) retrieved from Reaper!`);
	}

	function toggleDefaultTag(tagName: string) {
		if (!song.defaultTags) song.defaultTags = {};
		song.defaultTags[tagName] = !song.defaultTags[tagName];
	}
</script>

<Form onsubmit={() => onSubmit(song)}>
	<div class="form-group">
		<label for="relative-path">Project File:</label>
		<select onchange={(e) => handleProjectSelect(e.currentTarget.value)} bind:value={song.path} id="relative-path" required>
			<option value="">Select project...</option>
			{#each filteredProjects as project (project)}
				<option value={project}>{project}</option>
			{/each}
		</select>
		<div class="checkbox-container">
			<label class="checkbox-label">
				<input type="checkbox" bind:checked={hideUsedProjects} />
				Hide projects already used by other songs
			</label>
		</div>
	</div>

	<div class="form-group">
		<label for="song-name">Song Name:</label>
		<input bind:value={song.name} type="text" id="song-name" placeholder="Enter song name" required />
	</div>

	<div class="form-group">
		<label for="duration">Duration (seconds):</label>
		<div class="input-with-button">
			<input bind:value={song.length} type="number" id="duration" placeholder="Duration in seconds" min="0" required />
			<Button elementType="button" onclick={handleGetFromReaperClick} disabled={song.path === ''}>Get from Reaper</Button>
		</div>
		<span class="duration-display">{duration}</span>
	</div>

	<div class="form-group">
		<label>Marker Tags (Default values):</label>
		{#if tagEntries.length === 0}
			<p class="no-tags">No tagged markers found. Click "Get from Reaper" to scan project markers.</p>
		{:else}
			<table class="tags-table">
				<thead>
					<tr>
						<th>Tag Name</th>
						<th>Default State</th>
					</tr>
				</thead>
				<tbody>
					{#each tagEntries as [tagName, isActive] (tagName)}
						<tr>
							<td>{tagName}</td>
							<td>
								<label class="toggle-label">
									<input type="checkbox" checked={isActive} onchange={() => toggleDefaultTag(tagName)} />
									<span>{isActive ? 'Enabled' : 'Disabled'}</span>
								</label>
							</td>
						</tr>
					{/each}
				</tbody>
			</table>
		{/if}
	</div>

	<div class="submit-section">
		<Button elementType="submit" disabled={song.name === '' || song.path === ''}>Save</Button>
	</div>
</Form>

<style>
	.duration-display {
		font-size: 0.875rem;
		color: var(--comment);
		font-style: italic;
		margin-top: 0.5rem;
	}

	.checkbox-container {
		margin-top: 0.5rem;
	}

	.checkbox-label {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		font-size: 0.875rem;
		color: var(--comment);
		cursor: pointer;
		font-weight: normal;
	}

	.checkbox-label input[type='checkbox'] {
		cursor: pointer;
		width: auto;
		margin: 0;
	}

	.no-tags {
		font-size: 0.875rem;
		color: var(--text-muted);
		font-style: italic;
		margin: 0.25rem 0;
	}

	.tags-table {
		width: 100%;
		border-collapse: collapse;
		margin-top: 0.5rem;
	}

	.tags-table th,
	.tags-table td {
		text-align: left;
		padding: 0.5rem;
		border-bottom: 1px solid var(--border, #333);
	}

	.toggle-label {
		display: inline-flex;
		align-items: center;
		gap: 0.5rem;
		cursor: pointer;
	}

	.toggle-label input[type='checkbox'] {
		width: auto;
		margin: 0;
		cursor: pointer;
	}
</style>
