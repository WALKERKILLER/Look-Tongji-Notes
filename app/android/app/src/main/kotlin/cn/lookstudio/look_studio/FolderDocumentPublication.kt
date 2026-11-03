package cn.lookstudio.look_studio

/** SAF providers need not support replace-on-rename. Retain the old document
 * until publication succeeds; a failed rollback leaves a recoverable backup. */
internal fun <T : Any> publishFolderDocument(
    temporary: T,
    previous: T?,
    name: String,
    backupName: String,
    rename: (T, String) -> T,
    delete: (T) -> Unit,
) {
    val backup = previous?.let { rename(it, backupName) }
    try {
        rename(temporary, name)
    } catch (failure: Exception) {
        if (backup != null) {
            try { rename(backup, name) }
            catch (rollback: Exception) { failure.addSuppressed(rollback) }
        }
        throw failure
    }
    // The new document is authoritative even if cleanup is temporarily denied.
    if (backup != null) {
        try { delete(backup) } catch (_: Exception) { }
    }
}
