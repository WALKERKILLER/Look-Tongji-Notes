// Conversations sync between devices (lookd's data sync carries
// agent/sessions), and each device keeps its library at another path. Pi's
// SessionManager filters a custom session folder by the cwd recorded in each
// file, which hides a conversation started on another device ("会话不存在").
// These helpers find sessions whatever cwd they recorded and run them in this
// device's library.
import { SessionManager } from "@earendil-works/pi-coding-agent";

export class Sessions {
	/** @param {string} dir the session folder; @param {string} cwd this device's library */
	constructor(dir, cwd) {
		this.dir = dir;
		this.cwd = cwd;
	}

	/** Every conversation in the folder, from any device. */
	list() {
		return SessionManager.listAll(this.dir);
	}

	/** The file of conversation id, or undefined. */
	async find(id) {
		// Header-only lookup for this device's own conversations; a full scan for synced ones.
		return SessionManager.findById(this.cwd, id, this.dir) ?? (await this.list()).find((s) => s.id === id)?.path;
	}

	/** Opens a conversation file to continue in this device's library. */
	open(path) {
		return SessionManager.open(path, this.dir, this.cwd);
	}

	create() {
		return SessionManager.create(this.cwd, this.dir);
	}
}
