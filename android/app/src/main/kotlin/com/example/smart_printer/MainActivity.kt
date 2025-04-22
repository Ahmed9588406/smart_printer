package com.example.smart_printer

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.Intent
import android.os.AsyncTask
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.IOException
import java.io.OutputStream
import java.util.UUID

class MainActivity: FlutterActivity() {
    private val CHANNEL = "bluetooth.file.transfer"
    private val uuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB") // Standard SerialPortService ID

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableBluetooth" -> {
                    try {
                        val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
                        if (bluetoothAdapter != null && !bluetoothAdapter.isEnabled) {
                            val enableBtIntent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
                            startActivityForResult(enableBtIntent, 1)
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("BLUETOOTH_ERROR", "Error enabling Bluetooth", e.message)
                    }
                }
                "sendFile" -> {
                    val filePath = call.argument<String>("filePath")
                    val deviceAddress = call.argument<String>("deviceAddress")
                    
                    if (filePath != null && deviceAddress != null) {
                        SendFileTask(result, filePath, deviceAddress).execute()
                    } else {
                        result.error("INVALID_ARGUMENTS", "Missing filePath or deviceAddress", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private inner class SendFileTask(
        private val result: MethodChannel.Result,
        private val filePath: String,
        private val deviceAddress: String
    ) : AsyncTask<Void, Int, Boolean>() {
        private var exception: Exception? = null

        override fun doInBackground(vararg params: Void): Boolean {
            var socket: BluetoothSocket? = null
            var outputStream: OutputStream? = null
            var fileInputStream: FileInputStream? = null

            try {
                val bluetoothAdapter = BluetoothAdapter.getDefaultAdapter()
                if (bluetoothAdapter == null || !bluetoothAdapter.isEnabled) {
                    throw IOException("Bluetooth is not enabled")
                }

                val device: BluetoothDevice = bluetoothAdapter.getRemoteDevice(deviceAddress)
                socket = device.createRfcommSocketToServiceRecord(uuid)
                
                Log.d("BluetoothSender", "Connecting to device: ${device.name}")
                socket.connect()
                
                if (!socket.isConnected) {
                    throw IOException("Failed to connect to device")
                }
                
                Log.d("BluetoothSender", "Connected successfully")
                outputStream = socket.outputStream

                // Open the file
                val file = File(filePath)
                val buffer = ByteArray(1024)
                var bytesRead: Int
                
                fileInputStream = FileInputStream(file)
                
                // Send the file name first
                val fileNameBytes = file.name.toByteArray()
                outputStream.write(fileNameBytes.size)
                outputStream.write(fileNameBytes)
                
                // Send the file size
                val fileSize = file.length()
                for (i in 0..7) {
                    outputStream.write((fileSize shr (i * 8)).toInt() and 0xFF)
                }
                
                // Send the file content
                var totalBytesRead = 0L
                while (fileInputStream.read(buffer).also { bytesRead = it } != -1) {
                    outputStream.write(buffer, 0, bytesRead)
                    totalBytesRead += bytesRead
                    publishProgress((totalBytesRead * 100 / fileSize).toInt())
                }
                
                outputStream.flush()
                return true
            } catch (e: Exception) {
                Log.e("BluetoothSender", "Error sending file: ${e.message}", e)
                exception = e
                return false
            } finally {
                try {
                    fileInputStream?.close()
                    outputStream?.close()
                    socket?.close()
                } catch (e: Exception) {
                    Log.e("BluetoothSender", "Error closing connection", e)
                }
            }
        }

        override fun onPostExecute(success: Boolean) {
            if (success) {
                result.success(true)
            } else {
                result.error("TRANSFER_ERROR", "Failed to send file", exception?.message)
            }
        }
    }
}