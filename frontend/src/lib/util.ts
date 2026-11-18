import type { ReaperMarker } from '$lib/models/reaper-marker';

export function formatDuration(seconds: number): string {
	const minutes = Math.floor(seconds / 60);
	const remainingSeconds = Math.floor(seconds % 60);
	return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`;
}

export function generateUUID(): string {
	if (typeof crypto !== 'undefined' && crypto.randomUUID) {
		return crypto.randomUUID();
	}

	// Fallback: generate a pseudo-UUID using Math.random()
	return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
		const r = (Math.random() * 16) | 0;
		const v = c === 'x' ? r : (r & 0x3) | 0x8;
		return v.toString(16);
	});
}

export function chunk<T>(item: T, chunkSize: number = 600): string[] {
	const str = JSON.stringify(item);
	const chunks: string[] = [];

	for (let i = 0; i < str.length; i += chunkSize) {
		const substr = str.substring(i, i + chunkSize);
		chunks.push(substr);
	}

	return chunks;
}

/**
 * Extrait tous les tags pilotables `[Nom du Tag](...)` depuis une liste de marqueurs REAPER.
 * Retourne un dictionnaire `{ "Nom du Tag": boolean }`.
 */
export function extractTagsFromMarkers(markers: ReaperMarker[]): Record<string, boolean> {
	const tags: Record<string, boolean> = {};
	const tagRegex = /\[([^\]]+)\]\(([^)]*)\)/g;

	for (const marker of markers) {
		let match: RegExpExecArray | null;
		while ((match = tagRegex.exec(marker.name)) !== null) {
			const tagName = match[1].trim();
			const content = match[2];

			// On retire temporairement les blocs entre accolades `{...}` pour ne pas analyser leurs espaces internes
			const outsideBraces = content.replace(/\{[^}]*\}/g, 'PLACEHOLDER').trim();

			// Si le contenu hors accolades contient au moins un espace entre tokens, le tag est actif (true).
			// S'il est vide ou collé par des `|` sans espace, il est inactif (false).
			const isActive = outsideBraces.length > 0 && /\s/.test(outsideBraces);

			tags[tagName] = isActive;
		}
	}

	return tags;
}