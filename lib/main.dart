import 'package:flutter/material.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'dart:async';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
// import 'package:location/location.dart';
// import 'package:location_permissions/location_permissions.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;

Uuid _ESP32_UUID = Uuid.parse("053e3eda-9fca-48cb-9b59-0089e38c4d50");
Uuid _ESP32_WRITE = Uuid.parse("a90c323c-eabd-4121-94a5-7e36a6e99a23");

void main() {
  runApp(const JoystickExampleApp());
}

const ballSize = 20.0;
const step = 10.0;

class JoystickExampleApp extends StatelessWidget {
  const JoystickExampleApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Joystick Example'),
        ),
        body: const MainPage(),
      ),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({Key? key}) : super(key: key);

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final flutterReactiveBle = FlutterReactiveBle();
  List<DiscoveredDevice> _foundBleUARTDevices = [];
  // mark as late as scans and connections will be initialised later
  late StreamSubscription<DiscoveredDevice> _scanStream;
  late Stream<ConnectionStateUpdate> _currentConnectionStream;
  late StreamSubscription<ConnectionStateUpdate> _connection;
  late QualifiedCharacteristic _rxCharacteristic;
  bool _scanning = false;
  bool _connected = false;
  List<int> _controlBytes = [];
  String _logTexts = "";

  // Location location = new Location();
  late PermissionStatus _permissionGranted;
  void refreshScreen() {
    setState(() {});
  }

  void _sendData(double x, double y) async {
    if (!_connected) {
      return;
    }
    
    // Get X and Y from the Joystick.
    // Invert X
    // Calculate R+L (Call it V): V =(100-ABS(X)) * (Y/100) + Y
    // Calculate R-L (Call it W): W= (100-ABS(Y)) * (X/100) + X
    // Calculate R: R = (V+W) /2
    // Calculate L: L= (V-W)/2
    // Do any scaling on R and L your hardware may require.
    // Send those values to your Robot.
    // Go back to 1.
    // x = x * 100;
    // y = y * 100;
    x = -x;
    double v = (1 - x.abs()) * (y) + y;
    double w = (1 - y.abs()) * (x) + x;
    double rightMotor = -(v + w) / 2;
    double leftMotor = -(v - w) / 2;
    int motorControl = 0;

    // LEFT MOTOR A
    if (leftMotor < 0) {
      motorControl = motorControl + 1; 
      leftMotor = leftMotor.abs();
    } 
    if (rightMotor < 0) {
      motorControl = motorControl + 2;
      rightMotor = rightMotor.abs();
    }
    int motorA = (leftMotor * 255).toInt();
    int motorB = (rightMotor * 255).toInt();
    List<int> test = [motorControl, motorA, motorB];
    await flutterReactiveBle.writeCharacteristicWithResponse(_rxCharacteristic,
        value: test);
  }

  void _disconnect() async {
    await _connection.cancel();
    _connected = false;
    refreshScreen();
  }

  void _stopScan() async {
    await _scanStream.cancel();
    _scanning = false;
    refreshScreen();
  }

  void _startScan() async {
    // _permissionGranted = await location.hasPermission();
    // print(_permissionGranted);
    // if (_permissionGranted == PermissionStatus.denied) {
    //   _permissionGranted = await location.requestPermission();
    //   if (_permissionGranted != PermissionStatus.granted) {
    //     return;
    //   }
    // }
    var status = await Permission.bluetooth.status;

    if (status.isGranted) {
      // print('Location permission is granted');
      // scanForDevices();
    } else {
      // print('Location permission is not granted');
      await [
        Permission.location,
        Permission.bluetooth,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
      ].request();

      status = await Permission.location.status;

      // scanForDevices();
    }
    _foundBleUARTDevices = [];
    _scanning = true;
    refreshScreen();
    _scanStream = flutterReactiveBle
        .scanForDevices(withServices: [_ESP32_UUID]).listen((device) {
      // connect here
      if (_foundBleUARTDevices.every((element) => element.id != device.id)) {
        _foundBleUARTDevices.add(device);
        _logTexts = "Found device!";
        refreshScreen();
      }
      // if (_foundBleUARTDevices.every((element) =>
      // element.id != device.id)) {
      //   _foundBleUARTDevices.add(device);
      //   refreshScreen();
      // }
    }, onError: (Object error) {
      // print("ERROR while scanning:$error \n");
      _logTexts = "${_logTexts}ERROR while scanning:$error \n";
      refreshScreen();
    });
  }

  void onConnectDevice(device) {
    _currentConnectionStream = flutterReactiveBle.connectToAdvertisingDevice(
      id: device.id,
      prescanDuration: Duration(seconds: 1),
      withServices: [_ESP32_UUID],
    );
    _logTexts = "";
    refreshScreen();
    _connection = _currentConnectionStream.listen((event) {
      var id = event.deviceId.toString();
      // print(event);
      switch (event.connectionState) {
        case DeviceConnectionState.connecting:
          {
            
            _logTexts = "${_logTexts}Connecting to $id\n";
            break;
          }
        case DeviceConnectionState.connected:
          {
            _connected = true;
            _logTexts = "${_logTexts}Connected to $id\n";
            _rxCharacteristic = QualifiedCharacteristic(
                serviceId: _ESP32_UUID,
                characteristicId: _ESP32_WRITE,
                deviceId: event.deviceId);
            
            break;
          }
        case DeviceConnectionState.disconnecting:
          {
            _connected = false;
            _logTexts = "${_logTexts}Disconnecting from $id\n";
            break;
          }
        case DeviceConnectionState.disconnected:
          {
            _logTexts = "${_logTexts}Disconnected from $id\n";
            break;
          }
      }
      refreshScreen();
    }, onError: (Object error) {
      // print("ERROR while connecting:$error \n");
      _logTexts = "${_logTexts}ERROR while connecting:$error \n";
      refreshScreen();
    });
  }

  void connectToDevice() {
    if (_scanning) {
      _stopScan();
      if (_foundBleUARTDevices.isNotEmpty) {
        onConnectDevice(_foundBleUARTDevices[0]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
          child: Column(
        children: [
          const Text("Status messages:"),
          Container(
              margin: const EdgeInsets.all(3.0),
              width: 1400,
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.blue, width: 2)),
              height: 90,
              child: Scrollbar(
                  child: SingleChildScrollView(child: Text(_logTexts)))),
          Joystick(
            mode: JoystickMode.all,
            listener: (details) {
              _sendData(details.x, details.y);
            },
          ),
        ],
      )

          // child: Stack(
          //   children: [
          //     Container(
          //       color: Colors.green,
          //     ),
          //     Align(
          //       alignment: const Alignment(0, 0.8),
          //       child:
          //     ),
          //   ],
          // ),
          ),
      persistentFooterButtons: [
        Container(
          height: 35,
          child: Column(
            children: [
              if (_scanning)
                const Text("Scanning: Scanning")
              else
                const Text("Scanning: Idle"),
              if (_connected)
                const Text("Connected")
              else
                const Text("disconnected."),
            ],
          ),
        ),
        ElevatedButton(
          onPressed: !_scanning && !_connected ? _startScan : () {},
          child: Icon(
            Icons.play_arrow,
            color: !_scanning && !_connected ? Colors.blue : Colors.grey,
          ),
        ),
        ElevatedButton(
            onPressed: () => {
              connectToDevice()
            },
            child: Icon(
              Icons.stop,
              color: _scanning ? Colors.blue : Colors.grey,
            )),
        ElevatedButton(
            onPressed: _connected ? _disconnect : () {},
            child: Icon(
              Icons.cancel,
              color: _connected ? Colors.blue : Colors.grey,
            ))
      ],
    );
  }
}
