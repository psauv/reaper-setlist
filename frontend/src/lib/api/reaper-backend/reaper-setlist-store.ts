import type { Setlist } from '$lib/models/setlist';
import type { Song } from '$lib/models/song';
import type { SetlistsStore } from '../api';
import { ReaperKVS } from './reaper-kvs';

export class ReaperSetlistStoreImpl extends ReaperKVS<Setlist> implements SetlistsStore {
	async deleteSongFromSets(id: string): Promise<void> {
		const setlists = await this.list();
		const updates: Promise<void>[] = [];
		for (const setlist of Object.values(setlists)) {
			if (setlist.songs.includes(id)) {
				setlist.songs = setlist.songs.filter((songId) => songId !== id);
				if (setlist.songTags) {
					delete setlist.songTags[id];
				}
				updates.push(this.update(setlist.id, setlist));
			}
		}
		await Promise.all(updates);
	}

	async syncSongTagsInSets(song: Song): Promise<void> {
		const setlists = await this.list();
		const defaultTags = song.defaultTags ?? {};
		const updates: Promise<void>[] = [];

		for (const setlist of Object.values(setlists)) {
			if (!setlist.songs.includes(song.id)) continue;

			if (!setlist.songTags) {
				setlist.songTags = {};
			}

			const currentTags = setlist.songTags[song.id] ?? {};
			const updatedTags: Record<string, boolean> = {};

			for (const [tagName, defaultValue] of Object.entries(defaultTags)) {
				updatedTags[tagName] = tagName in currentTags ? currentTags[tagName] : defaultValue;
			}

			setlist.songTags[song.id] = updatedTags;
			updates.push(this.update(setlist.id, setlist));
		}

		await Promise.all(updates);
	}
}
