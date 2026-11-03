package cn.lookstudio.look_studio

import java.io.IOException
import org.junit.Assert.*
import org.junit.Test

class FolderDocumentPublicationTest {
    private class Documents {
        val names = linkedMapOf("old" to "abc.json", "new" to "upload.tmp")
        var failBackup = false
        var failPublish = false
        var failRestore = false
        var failCleanup = false
        fun rename(id: String, name: String): String {
            if (name.endsWith(".previous") && failBackup) throw IOException("provider refused backup")
            if (name == "abc.json" && (id == "new" && failPublish || id == "old" && failRestore)) {
                throw IOException("provider refused rename")
            }
            check(id in names)
            check(name !in names.values)
            names[id] = name
            return id
        }
        fun delete(id: String) {
            if (id == "old" && failCleanup) throw IOException("provider refused cleanup")
            names.remove(id)
        }
        fun publish() = publishFolderDocument("new", "old", "abc.json", "abc.json.previous", ::rename, ::delete)
    }

    @Test fun firstPublicationNeedsNoPreviousDocument() {
        val docs = Documents().apply { names.remove("old") }
        publishFolderDocument("new", null, "abc.json", "abc.json.previous", docs::rename, docs::delete)
        assertEquals(mapOf("new" to "abc.json"), docs.names)
    }

    @Test fun failedBackupLeavesOriginalDocumentInPlace() {
        val docs = Documents().apply { failBackup = true }
        assertThrows(IOException::class.java) { docs.publish() }
        assertEquals("abc.json", docs.names["old"])
        assertEquals("upload.tmp", docs.names["new"])
    }

    @Test fun failedPublishRestoresPreviousManifest() {
        val docs = Documents().apply { failPublish = true }
        assertThrows(IOException::class.java) { docs.publish() }
        assertEquals("abc.json", docs.names["old"])
        assertEquals("upload.tmp", docs.names["new"])
        docs.failPublish = false
        docs.publish()
        assertEquals(mapOf("new" to "abc.json"), docs.names)
    }

    @Test fun failedRollbackRetainsRecoverablePreviousBytes() {
        val docs = Documents().apply { failPublish = true; failRestore = true }
        val error = assertThrows(IOException::class.java) { docs.publish() }
        assertEquals("abc.json.previous", docs.names["old"])
        assertEquals(1, error.suppressed.size)
    }

    @Test fun cleanupFailureDoesNotInvalidateSuccessfulPublication() {
        val docs = Documents().apply { failCleanup = true }
        docs.publish()
        assertEquals("abc.json", docs.names["new"])
        assertEquals("abc.json.previous", docs.names["old"])
    }
}
