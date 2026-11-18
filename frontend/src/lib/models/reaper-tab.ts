export interface ReaperTab {
	index: number;
	name: string;
	length: number; // in seconds
	dirty: boolean;
	tags?: Record<string, boolean>;
}
