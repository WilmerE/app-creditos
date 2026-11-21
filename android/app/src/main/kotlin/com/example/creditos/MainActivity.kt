package com.example.creditos

import android.Manifest
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "app_creditos/media_gallery"
    private val writePermissionRequest = 7142
    private var pendingImage: Pair<String, ByteArray>? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "saveImage") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val fileName = call.argument<String>("fileName")
                val bytes = call.argument<ByteArray>("bytes")
                if (
                    fileName == null ||
                    fileName.isBlank() ||
                    bytes == null ||
                    bytes.isEmpty()
                ) {
                    result.error("invalid_image", "La imagen no es válida.", null)
                    return@setMethodCallHandler
                }

                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
                    ContextCompat.checkSelfPermission(
                        this,
                        Manifest.permission.WRITE_EXTERNAL_STORAGE,
                    ) != PackageManager.PERMISSION_GRANTED
                ) {
                    if (pendingResult != null) {
                        result.error("save_in_progress", "Ya hay un guardado en curso.", null)
                        return@setMethodCallHandler
                    }
                    pendingImage = fileName to bytes
                    pendingResult = result
                    requestPermissions(
                        arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                        writePermissionRequest,
                    )
                    return@setMethodCallHandler
                }

                saveToGallery(fileName, bytes, result)
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != writePermissionRequest) return

        val result = pendingResult ?: return
        val image = pendingImage
        pendingResult = null
        pendingImage = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED && image != null) {
            saveToGallery(image.first, image.second, result)
        } else {
            result.error(
                "gallery_permission_denied",
                "Se necesita permiso para guardar la imagen en la galería.",
                null,
            )
        }
    }

    private fun saveToGallery(
        fileName: String,
        bytes: ByteArray,
        result: MethodChannel.Result,
    ) {
        val resolver = contentResolver
        val collection = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        var legacyFilePath: String? = null
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
            put(MediaStore.Images.Media.MIME_TYPE, "image/png")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(
                    MediaStore.Images.Media.RELATIVE_PATH,
                    "${Environment.DIRECTORY_PICTURES}/V&S Inversiones",
                )
                put(MediaStore.Images.Media.IS_PENDING, 1)
            } else {
                val directory = File(
                    Environment.getExternalStoragePublicDirectory(
                        Environment.DIRECTORY_PICTURES,
                    ),
                    "V&S Inversiones",
                )
                if (!directory.exists() && !directory.mkdirs()) {
                    result.error("gallery_directory", "No se pudo crear la carpeta de imágenes.", null)
                    return
                }
                legacyFilePath = File(directory, fileName).absolutePath
                put(MediaStore.Images.Media.DATA, legacyFilePath)
            }
        }

        val uri = resolver.insert(collection, values)
        if (uri == null) {
            result.error("gallery_insert", "No se pudo crear la imagen en la galería.", null)
            return
        }
        try {
            resolver.openOutputStream(uri)?.use { output -> output.write(bytes) }
                ?: throw IllegalStateException("No se pudo abrir el archivo de galería.")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                resolver.update(
                    uri,
                    ContentValues().apply {
                        put(MediaStore.Images.Media.IS_PENDING, 0)
                    },
                    null,
                    null,
                )
            } else {
                legacyFilePath?.let { path ->
                    MediaScannerConnection.scanFile(
                        this,
                        arrayOf(path),
                        arrayOf("image/png"),
                        null,
                    )
                }
            }
            result.success("V&S Inversiones/$fileName")
        } catch (error: Exception) {
            resolver.delete(uri, null, null)
            result.error("gallery_write", error.message ?: "No se pudo guardar la imagen.", null)
        }
    }
}
