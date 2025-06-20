import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../feature/common_widgets/custom_toast.dart';

abstract class NetworkInfo {
  Future<bool> get isConnected;
  Future<bool> get isSlow;
}

class NetworkInfoImplementation implements NetworkInfo {
  final Connectivity connectivity;
  final int slowThreshold = 2000;

  NetworkInfoImplementation(this.connectivity);

  @override
  Future<bool> get isConnected async {
    final result = await connectivity.checkConnectivity();
    print("Internet connection result is: $result");

    switch (result) {
      case ConnectivityResult.mobile:
      case ConnectivityResult.wifi:
      case ConnectivityResult.ethernet:
      case ConnectivityResult.bluetooth:
      case ConnectivityResult.vpn:
        return true;
      case ConnectivityResult.none:
        toast(msg: "Internet not available", isError: true);
        return false;
      default:
        return false;
    }
  }

  @override
  Future<bool> get isSlow async {
    try {
      final stopwatch = Stopwatch()..start();
      await InternetAddress.lookup('example.com'); // Replace with a reliable address
      final duration = stopwatch.elapsedMilliseconds;
      return duration > slowThreshold;
    } on SocketException catch (_) {
      return true; // Consider slow if lookup fails
    }
  }
}
