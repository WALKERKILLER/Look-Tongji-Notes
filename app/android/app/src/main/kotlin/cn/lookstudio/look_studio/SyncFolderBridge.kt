package cn.lookstudio.look_studio

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import java.io.BufferedInputStream
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.Executors
import org.json.JSONArray

/** Private loopback file transport scoped to one persisted SAF tree grant. */
class SyncFolderBridge(private val context: Context, private val tree: Uri) {
    private val resolver = context.contentResolver
    private val rootId = DocumentsContract.getTreeDocumentId(tree)
    private val token = ByteArray(32).also { SecureRandom().nextBytes(it) }.joinToString("") { "%02x".format(it) }
    private val server = ServerSocket(0, 16, InetAddress.getByName("127.0.0.1"))
    private val workers = Executors.newFixedThreadPool(2)
    init {
        Thread {
            while (!server.isClosed) {
                try { val socket = server.accept(); workers.execute { handle(socket) } }
                catch (_: Exception) { if (server.isClosed) break }
            }
        }.apply { isDaemon = true; name = "look-folder"; start() }
    }
    fun descriptor() = mapOf("local_folder" to tree.toString(), "bridge_url" to "http://127.0.0.1:${server.localPort}", "bridge_token" to token)
    fun close() { server.close(); workers.shutdownNow() }
    private fun uri(id: String) = DocumentsContract.buildDocumentUriUsingTree(tree, id)
    private fun children(id: String): Map<String, String> {
        val found = linkedMapOf<String, String>()
        resolver.query(DocumentsContract.buildChildDocumentsUriUsingTree(tree, id), arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use { c ->
            while (c.moveToNext()) found[c.getString(1)] = c.getString(0)
        } ?: throw SecurityException("文件夹授权失效")
        return found
    }
    private fun resolve(path: String, createParents: Boolean = false): Pair<String, String> {
        val parts = path.split('/')
        require(parts.all { it.isNotBlank() && it != "." && it != ".." && !it.contains('\\') })
        require(path == "library.json" || (parts.size == 2 && (parts[0] == "objects" && parts[1].matches(Regex("[a-f0-9]{64}")) || parts[0] == "devices" && parts[1].matches(Regex("[a-f0-9]+\\.json")))))
        var parent = rootId
        for (name in parts.dropLast(1)) {
            parent = children(parent)[name] ?: if (createParents) {
                val created = DocumentsContract.createDocument(resolver, uri(parent), DocumentsContract.Document.MIME_TYPE_DIR, name) ?: throw SecurityException("目录不可写")
                DocumentsContract.getDocumentId(created)
            } else throw java.io.FileNotFoundException(path)
        }
        return parent to parts.last()
    }
    private fun line(input: InputStream): String {
        val b = java.io.ByteArrayOutputStream()
        while (b.size() <= 8192) { val c = input.read(); if (c < 0 || c == 10) break; if (c != 13) b.write(c) }
        require(b.size() <= 8192)
        return b.toString("UTF-8")
    }
    private fun reply(out: OutputStream, status: Int, body: ByteArray = byteArrayOf()) {
        out.write("HTTP/1.1 $status Result\r\nConnection: close\r\nContent-Length: ${body.size}\r\nContent-Type: application/json\r\n\r\n".toByteArray()); out.write(body); out.flush()
    }
    private fun handle(socket: Socket) {
        socket.use {
            socket.soTimeout = 120000
            val input = BufferedInputStream(socket.getInputStream()); val output = socket.getOutputStream()
            try {
                val request = line(input).split(' '); require(request.size == 3)
                val headers = mutableMapOf<String, String>()
                var headerCount = 0
                while (true) { val h = line(input); if (h.isBlank()) break; require(++headerCount <= 64); val pos = h.indexOf(':'); if (pos > 0) headers[h.substring(0, pos).lowercase()] = h.substring(pos+1).trim() }
                if (!MessageDigest.isEqual((headers["authorization"] ?: "").toByteArray(), "Bearer $token".toByteArray())) { reply(output, 403); return }
                val requestUri = Uri.parse(request[1]); val path = requestUri.getQueryParameter("path") ?: ""
                if (request[0] == "GET" && requestUri.path == "/list" && path == "devices") {
                    val devices = children(rootId)["devices"]
                    val names = if (devices == null) emptyList() else children(devices).keys.filter { it.endsWith(".json") }
                    reply(output, 200, JSONArray(names).toString().toByteArray()); return
                }
                require(requestUri.path == "/file")
                val (parent, name) = resolve(path, request[0] == "PUT")
                when (request[0]) {
                    "GET" -> {
                        val id = children(parent)[name] ?: throw java.io.FileNotFoundException(path)
                        resolver.openInputStream(uri(id))!!.use { source ->
                            output.write("HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Type: application/octet-stream\r\n\r\n".toByteArray()); source.copyTo(output); output.flush()
                        }
                    }
                    "PUT" -> {
                        val length = headers["content-length"]?.toLongOrNull() ?: throw IllegalArgumentException("需要文件长度")
                        require(length in 0..(3L*1024*1024*1024))
                        val temp = DocumentsContract.createDocument(resolver, uri(parent), "application/octet-stream", "$name.${System.nanoTime()}.tmp") ?: throw SecurityException("文件夹不可写")
                        try {
                            resolver.openOutputStream(temp, "wt")!!.use { dest ->
                                val buffer = ByteArray(65536); var left = length
                                while (left > 0) { val n = input.read(buffer, 0, minOf(left, buffer.size.toLong()).toInt()); if (n < 0) throw java.io.EOFException(); dest.write(buffer,0,n);left-=n }
                            }
                            children(parent)[name]?.let { DocumentsContract.deleteDocument(resolver, uri(it)) }
                            if (DocumentsContract.renameDocument(resolver,temp,name) == null) throw java.io.IOException("文件发布失败")
                            reply(output,200)
                        } catch (e: Exception) { try { DocumentsContract.deleteDocument(resolver,temp) } catch (_:Exception) {}; throw e }
                    }
                    else -> reply(output,405)
                }
            } catch (_: java.io.FileNotFoundException) { reply(output,404) }
              catch (_: SecurityException) { reply(output,403) }
              catch (_: Exception) { try { reply(output,400) } catch (_: Exception) {} }
        }
    }
    companion object {
        private var running: SyncFolderBridge? = null
        private var active: String? = null
        @Synchronized fun open(context: Context, tree: Uri): Map<String,String> {
            if (active != tree.toString() || running == null) { running?.close();running=SyncFolderBridge(context.applicationContext,tree);active=tree.toString() }
            return running!!.descriptor()
        }
    }
}
