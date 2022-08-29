import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:location_permissions/location_permissions.dart';
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'mr6',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(title: 'Raspberry Pi BLE Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  final int dataCacheLength = 300;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  bool _foundDeviceWaitingToConnect = false;
  bool _scanStarted = false;
  bool _connected = false;
  String _serviceRead = '';
  List<FlSpot> _tempData = [];
  late DiscoveredDevice _ubiqueDevice;
  late StreamSubscription<List<int>> subscribeStream;
  final flutterReactiveBle = FlutterReactiveBle();
  late StreamSubscription<DiscoveredDevice> _scanStream;
  late QualifiedCharacteristic _rxCharacteristic;
  final Uuid serviceUuid = Uuid.parse("00000001-710e-4a5b-8d75-3e5b444bc3cf");
  final Uuid characteristicUuid =
      Uuid.parse("00000002-710e-4a5b-8d75-3e5b444bc3cf");

  void _startScan() async {
    // Platform permissions handling stuff
    bool permGranted = false;
    setState(() {
      _scanStarted = true;
    });
    PermissionStatus permission;
    if (Platform.isAndroid) {
      permission = await LocationPermissions().requestPermissions();
      if (permission == PermissionStatus.granted) permGranted = true;
    } else if (Platform.isIOS) {
      permGranted = true;
    }
    // Main scanning logic happens here ⤵️
    if (permGranted) {
      _scanStream =
          flutterReactiveBle.scanForDevices(withServices: []).listen((device) {
        // Change this string to what you defined in Zephyr
        if (device.name == 'Thermometer') {
          setState(() {
            _ubiqueDevice = device;
            _foundDeviceWaitingToConnect = true;
          });
        }
      });
    }
  }

  void _connectToDevice() {
    // We're done scanning, we can cancel it
    _scanStream.cancel();
    // Let's listen to our connection so we can make updates on a state change
    Stream<ConnectionStateUpdate> currentConnectionStream = flutterReactiveBle
        .connectToAdvertisingDevice(
            id: _ubiqueDevice.id,
            prescanDuration: const Duration(seconds: 1),
            withServices: [serviceUuid, characteristicUuid]);
    currentConnectionStream.listen((event) {
      switch (event.connectionState) {
        // We're connected and good to go!
        case DeviceConnectionState.connected:
          {
            _rxCharacteristic = QualifiedCharacteristic(
                serviceId: serviceUuid,
                characteristicId: characteristicUuid,
                deviceId: event.deviceId);
            subscribeStream = flutterReactiveBle
                .subscribeToCharacteristic(_rxCharacteristic)
                .listen((data) {
              setState(() {
                String readString = String.fromCharCodes(data);
                _serviceRead = readString;
                double temp = double.parse(readString.split(' ')[0]);
                _tempData.add(FlSpot(
                    _tempData.isEmpty ? 0.0 : _tempData.last.x + 1, temp));
                if (_tempData.length > widget.dataCacheLength * 2) {
                  _tempData.removeRange(
                      0, _tempData.length - widget.dataCacheLength);
                }
              });
            }, onError: (err) {});
            setState(() {
              _foundDeviceWaitingToConnect = false;
              _connected = true;
            });
            break;
          }
        // Can add various state state updates on disconnect
        case DeviceConnectionState.disconnected:
          {
            break;
          }
        default:
      }
    });
  }

  void _endConnection() {
    print("disconnect pressed");
    subscribeStream.cancel();
    setState(() {
      _connected = false;
      _scanStarted = false;
      _foundDeviceWaitingToConnect = false;
      _tempData = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      persistentFooterButtons: [
        _connected
            ? const Text("Connected 👍", style: TextStyle(fontSize: 15))
            : const Text("Not Connected 🥲", style: TextStyle(fontSize: 15)),
        _scanStarted
            ? ElevatedButton(
                style: ElevatedButton.styleFrom(
                    primary: Colors.grey, onPrimary: Colors.white),
                onPressed: () {},
                child: const Icon(Icons.search))
            : ElevatedButton(
                style: ElevatedButton.styleFrom(
                    primary: Colors.blue, onPrimary: Colors.white),
                onPressed: _startScan,
                child: const Icon(Icons.search)),
        _foundDeviceWaitingToConnect
            ? ElevatedButton(
                style: ElevatedButton.styleFrom(
                    primary: Colors.blue, onPrimary: Colors.white),
                onPressed: _connectToDevice,
                child: const Icon(Icons.bluetooth))
            : _connected
                ? ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        primary: Colors.blue, onPrimary: Colors.white),
                    onPressed: _endConnection,
                    child: const Icon(Icons.stop_rounded))
                : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        primary: Colors.grey, onPrimary: Colors.white),
                    onPressed: () {},
                    child: const Icon(Icons.bluetooth)),
      ],
      appBar: AppBar(
        title: Text(widget.title),
      ),
      body: Center(
        child: ListView(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 15),
              child: Center(
                  child: _connected
                      ? Text(_serviceRead)
                      : const Text('Not Connected')),
            ),
            Center(child: RealTimeGraph(data: _tempData, range: 100)),
            Center(child: RealTimeGraph(data: _tempData, range: 100)),
            Center(child: RealTimeGraph(data: _tempData, range: 100))
          ],
        ),
      ),
    );
  }
}

class RealTimeGraph extends StatefulWidget {
  const RealTimeGraph({Key? key, required this.data, required this.range})
      : super(key: key);

  final List<FlSpot> data;
  final int range;

  @override
  State<RealTimeGraph> createState() => _RealTimeGraphState();
}

class _RealTimeGraphState extends State<RealTimeGraph> {
  @override
  Widget build(BuildContext context) {
    return widget.data.isNotEmpty
        ? Container(
            padding: const EdgeInsets.all(3),
            margin: const EdgeInsets.all(3),
            height: MediaQuery.of(context).size.height * 0.2,
            child: LineChart(
              LineChartData(
                  titlesData: FlTitlesData(
                    bottomTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:
                        AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  maxX: widget.data.last.x,
                  minX: widget.data.last.x - widget.range,
                  maxY: 130.0,
                  minY: 90.0,
                  clipData: FlClipData.all(),
                  lineBarsData: [
                    LineChartBarData(
                        spots: widget.data,
                        // spots: widget.data.length < 200
                        //     ? widget.data
                        //     : widget.data.sublist(widget.data.length - 200),
                        dotData: FlDotData(show: false))
                  ]),
            ))
        : const Text("No Data");
  }
}
