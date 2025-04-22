import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:platform/platform.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bluetooth File Transfer',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[100],
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      darkTheme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[900],
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.grey[850],
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            elevation: 2,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      themeMode: ThemeMode.system,
      home: const BluetoothFileTransferPage(),
    );
  }
}

class BluetoothFileTransferPage extends StatefulWidget {
  const BluetoothFileTransferPage({Key? key}) : super(key: key);

  @override
  _BluetoothFileTransferPageState createState() => _BluetoothFileTransferPageState();
}

class _BluetoothFileTransferPageState extends State<BluetoothFileTransferPage> with SingleTickerProviderStateMixin {
  List<BluetoothDevice> devices = [];
  bool isScanning = false;
  File? selectedFile;
  BluetoothDevice? selectedDevice;
  StreamSubscription? _scanSubscription;
  String _statusMessage = 'Ready to scan';
  bool _isTransferring = false;
  double _transferProgress = 0.0;
  bool _isBluetoothEnabled = false;
  
  // For tab controller
  late TabController _tabController;

  // For animations
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  final List<BluetoothDevice> _animatedDevices = [];
  
  // Platform channel for Android-specific Bluetooth operations
  static const platform = MethodChannel('bluetooth.file.transfer');
  final LocalPlatform localPlatform = LocalPlatform();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkPermissions();
    _checkBluetoothStatus();
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _tabController.dispose();
    try {
      FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('Error stopping scan: $e');
    }
    super.dispose();
  }

  Future<void> _checkBluetoothStatus() async {
    try {
      // Check if Bluetooth is available
      final isAvailable = await FlutterBluePlus.isAvailable;
      if (!isAvailable) {
        setState(() {
          _isBluetoothEnabled = false;
          _statusMessage = 'Bluetooth is not available on this device';
        });
        return;
      }

      // Check if Bluetooth is on
      final adapterState = await FlutterBluePlus.adapterState.first;
      setState(() {
        _isBluetoothEnabled = adapterState == BluetoothAdapterState.on;
        if (!_isBluetoothEnabled) {
          _statusMessage = 'Please turn on Bluetooth';
        }
      });

      // Listen for adapter state changes
      FlutterBluePlus.adapterState.listen((state) {
        setState(() {
          _isBluetoothEnabled = state == BluetoothAdapterState.on;
          if (!_isBluetoothEnabled) {
            _statusMessage = 'Please turn on Bluetooth';
          } else {
            _statusMessage = 'Bluetooth is enabled';
          }
        });
      });
    } catch (e) {
      debugPrint('Error checking Bluetooth status: $e');
      setState(() {
        _isBluetoothEnabled = false;
        _statusMessage = 'Error checking Bluetooth status';
      });
    }
  }

  Future<void> _checkPermissions() async {
    if (localPlatform.isAndroid) {
      final statuses = await [
        Permission.bluetooth,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.location,
        Permission.storage,
      ].request();

      if (!statuses.values.every((status) => status.isGranted)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please grant all required permissions')),
          );
        }
      }
    }
  }

  Future<void> _enableBluetooth() async {
    if (localPlatform.isAndroid) {
      try {
        await platform.invokeMethod('enableBluetooth');
      } on PlatformException catch (e) {
        debugPrint('Failed to enable Bluetooth: ${e.message}');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable Bluetooth manually')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enable Bluetooth manually')),
      );
    }
  }

  Future<void> scanForDevices() async {
    if (!_isBluetoothEnabled) {
      _enableBluetooth();
      return;
    }

    setState(() {
      isScanning = true;
      devices.clear();
      _animatedDevices.clear();
      _statusMessage = 'Scanning...';
    });

    try {
      // Start scan
      await _scanSubscription?.cancel();
      await FlutterBluePlus.stopScan();

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        for (var result in results) {
          if (!devices.any((d) => d.remoteId == result.device.remoteId)) {
            setState(() {
              devices.add(result.device);
              
              // Add with animation
              if (!_animatedDevices.contains(result.device)) {
                _animatedDevices.add(result.device);
                if (_listKey.currentState != null) {
                  _listKey.currentState!.insertItem(_animatedDevices.length - 1);
                }
              }
            });
          }
        }
      }, onError: (e) {
        debugPrint('Scan error: $e');
        setState(() {
          _statusMessage = 'Scan error: ${e.toString()}';
        });
      });

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: false,
      );

      await Future.delayed(const Duration(seconds: 15));
      await FlutterBluePlus.stopScan();

      setState(() {
        _statusMessage = 'Scan completed. Found ${devices.length} devices';
      });
    } catch (e) {
      debugPrint('Error during scan: $e');
      setState(() {
        _statusMessage = 'Error: ${e.toString()}';
      });
    } finally {
      setState(() {
        isScanning = false;
      });
    }
  }

  Future<void> pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          selectedFile = File(result.files.single.path!);
        });
      }
    } catch (e) {
      debugPrint('File picker error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking file: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> sendFile() async {
    if (selectedFile == null || selectedDevice == null) return;

    setState(() {
      _isTransferring = true;
      _transferProgress = 0.0;
      _statusMessage = 'Starting transfer...';
    });

    try {
      if (localPlatform.isAndroid) {
        // For Android, use platform channel to handle classic Bluetooth
        await _sendFileViaAndroid();
      } else {
        // For iOS/other platforms, use BLE
        await _sendFileViaBLE();
      }

      setState(() {
        _statusMessage = 'File sent successfully!';
      });
      
      // Show success dialog
      if (mounted) {
        _showTransferSuccessDialog();
      }
    } catch (e) {
      debugPrint('Transfer error: $e');
      setState(() {
        _statusMessage = 'Transfer failed: ${e.toString()}';
      });
      
      // Show error dialog
      if (mounted) {
        _showTransferErrorDialog(e.toString());
      }
    } finally {
      setState(() {
        _isTransferring = false;
        _transferProgress = 1.0;
      });
    }
  }

  void _showTransferSuccessDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transfer Complete'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 16),
            Text('File "${path.basename(selectedFile!.path)}" successfully sent to ${selectedDevice!.name.isNotEmpty ? selectedDevice!.name : "device"}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showTransferErrorDialog(String errorMessage) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transfer Failed'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(errorMessage),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendFileViaAndroid() async {
    try {
      // Simulating progress updates since the actual method doesn't provide them
      for (int i = 1; i <= 10; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        setState(() {
          _transferProgress = i / 10;
          _statusMessage = 'Sending... ${(_transferProgress * 100).toStringAsFixed(1)}%';
        });
      }
      
      final result = await platform.invokeMethod('sendFile', {
        'filePath': selectedFile!.path,
        'deviceAddress': selectedDevice!.remoteId.toString(),
      });

      if (result != true) {
        throw Exception('File transfer failed');
      }
    } on PlatformException catch (e) {
      throw Exception('Failed to send file: ${e.message}');
    }
  }

  Future<void> _sendFileViaBLE() async {
    try {
      // Connect to device
      await selectedDevice!.connect(autoConnect: false, timeout: const Duration(seconds: 15));
      
      // Discover services
      List<BluetoothService> services = await selectedDevice!.discoverServices();
      
      // Look for a service with file transfer characteristics
      BluetoothCharacteristic? writeCharacteristic;
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          if (characteristic.properties.write || characteristic.properties.writeWithoutResponse) {
            writeCharacteristic = characteristic;
            break;
          }
        }
        if (writeCharacteristic != null) break;
      }

      if (writeCharacteristic == null) {
        throw Exception('No writable characteristic found');
      }

      // Read file
      final fileBytes = await selectedFile!.readAsBytes();
      final totalBytes = fileBytes.length;
      int bytesSent = 0;

      // Send in chunks
      const chunkSize = 512;
      for (int i = 0; i < totalBytes; i += chunkSize) {
        final end = (i + chunkSize > totalBytes) ? totalBytes : i + chunkSize;
        final chunk = fileBytes.sublist(i, end);

        await writeCharacteristic.write(chunk);
        
        bytesSent += chunk.length;
        setState(() {
          _transferProgress = bytesSent / totalBytes;
          _statusMessage = 'Sending... ${(_transferProgress * 100).toStringAsFixed(1)}%';
        });
      }

      // Disconnect
      await selectedDevice!.disconnect();
    } catch (e) {
      await selectedDevice!.disconnect();
      rethrow;
    }
  }

  Widget _buildDeviceList() {
    if (devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bluetooth_searching, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              isScanning ? 'Scanning for devices...' : 'No devices found',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 24),
            if (!isScanning)
              ElevatedButton.icon(
                onPressed: scanForDevices,
                icon: const Icon(Icons.refresh),
                label: const Text('Scan Again'),
              ),
          ],
        ),
      );
    }

    return AnimatedList(
      key: _listKey,
      initialItemCount: _animatedDevices.length,
      itemBuilder: (context, index, animation) {
        final device = _animatedDevices[index];
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          )),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Card(
              elevation: selectedDevice?.remoteId == device.remoteId ? 4 : 1,
              color: selectedDevice?.remoteId == device.remoteId 
                ? Theme.of(context).colorScheme.primaryContainer 
                : null,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.withOpacity(0.8),
                  child: Icon(
                    device.name.toLowerCase().contains('print') 
                      ? Icons.print 
                      : (device.name.toLowerCase().contains('laptop') || device.name.toLowerCase().contains('pc')) 
                        ? Icons.laptop 
                        : Icons.bluetooth,
                    color: Colors.white,
                  ),
                ),
                title: Text(
                  device.name.isNotEmpty ? device.name : 'Unknown Device',
                  style: TextStyle(
                    fontWeight: selectedDevice?.remoteId == device.remoteId 
                      ? FontWeight.bold 
                      : FontWeight.normal,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device.remoteId.toString()),
                    Text(
                      'Bluetooth Device',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.secondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                trailing: selectedDevice?.remoteId == device.remoteId
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : const Icon(Icons.chevron_right),
                onTap: () {
                  setState(() {
                    selectedDevice = device;
                  });
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFileSelector() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (selectedFile == null) ...[
            const Icon(Icons.upload_file, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No file selected',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: pickFile,
              icon: const Icon(Icons.add),
              label: const Text('Select File'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ] else ...[
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getFileIcon(path.extension(selectedFile!.path)),
                      size: 64,
                      color: _getFileColor(path.extension(selectedFile!.path)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      path.basename(selectedFile!.path),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatFileSize(selectedFile!.lengthSync()),
                      style: TextStyle(
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ElevatedButton.icon(
                          onPressed: pickFile,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Change File'),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              selectedFile = null;
                            });
                          },
                          icon: const Icon(Icons.delete),
                          label: const Text('Remove'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case '.pdf':
        return Icons.picture_as_pdf;
      case '.doc':
      case '.docx':
        return Icons.description;
      case '.xls':
      case '.xlsx':
        return Icons.table_chart;
      case '.ppt':
      case '.pptx':
        return Icons.slideshow;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
        return Icons.image;
      case '.mp3':
      case '.wav':
      case '.aac':
        return Icons.audio_file;
      case '.mp4':
      case '.mov':
      case '.avi':
        return Icons.video_file;
      case '.zip':
      case '.rar':
      case '.7z':
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(String extension) {
    switch (extension.toLowerCase()) {
      case '.pdf':
        return Colors.red;
      case '.doc':
      case '.docx':
        return Colors.blue;
      case '.xls':
      case '.xlsx':
        return Colors.green;
      case '.ppt':
      case '.pptx':
        return Colors.orange;
      case '.jpg':
      case '.jpeg':
      case '.png':
      case '.gif':
        return Colors.purple;
      case '.mp3':
      case '.wav':
      case '.aac':
        return Colors.deepPurple;
      case '.mp4':
      case '.mov':
      case '.avi':
        return Colors.red;
      case '.zip':
      case '.rar':
      case '.7z':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth File Transfer'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Select File'),
            Tab(text: 'Devices'),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_isBluetoothEnabled ? Icons.bluetooth_connected : Icons.bluetooth_disabled),
            onPressed: _isBluetoothEnabled ? null : _enableBluetooth,
            tooltip: _isBluetoothEnabled ? 'Bluetooth enabled' : 'Enable Bluetooth',
          ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          if (_isTransferring || _statusMessage.isNotEmpty)
            Container(
              color: _isTransferring ? Colors.blue : Colors.grey[200],
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(
                children: [
                  if (_isTransferring)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  if (_isTransferring)
                    const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: TextStyle(
                        color: _isTransferring ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  if (_isTransferring)
                    Text(
                      '${(_transferProgress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                ],
              ),
            ),
            
          // Progress bar
          if (_isTransferring)
            LinearProgressIndicator(
              value: _transferProgress,
              backgroundColor: Colors.blue[100],
              color: Colors.blue,
            ),
            
          // Main content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // File selector tab
                _buildFileSelector(),
                
                // Devices list tab
                Stack(
                  children: [
                    _buildDeviceList(),
                    if (isScanning)
                      Positioned(
                        bottom: 16,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Scanning...',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          
          // Bottom action bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isTransferring)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      'Transferring to ${selectedDevice?.name.isNotEmpty ?? false ? selectedDevice!.name : 'device'}...',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: (selectedFile != null && selectedDevice != null && !_isTransferring && _isBluetoothEnabled)
                            ? sendFile
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.send),
                        label: const Text('Send File'),
                      ),
                    ),
                    if (_tabController.index == 1 && !isScanning)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: IconButton(
                          onPressed: _isBluetoothEnabled ? scanForDevices : _enableBluetooth,
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Refresh device list',
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
