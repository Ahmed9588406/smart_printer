import 'package:flutter/services.dart';

class BluetoothService {
  static const MethodChannel _channel =
      MethodChannel('bluetooth.file.transfer');

  Future<bool> sendFile(String filePath, String deviceAddress) async {
    try {
      final bool result = await _channel.invokeMethod('sendFile', {
        'filePath': filePath,
        'deviceAddress': deviceAddress,
      });
      return result;
    } on PlatformException catch (e) {
      print('Bluetooth transfer error: ${e.message}');
      throw Exception('Failed to send file: ${e.message}');
    }
  }
}
