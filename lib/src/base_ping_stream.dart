import 'dart:async';
import 'package:flutter_icmp_ping/src/models/ping_data.dart';

abstract class BasePing {
  BasePing(this.host, this.count, this.interval, this.timeout, this.ipv6, this.size, this.ttl, this.fragment) {
    controller = StreamController<PingData>(
        onListen: onListen,
        onCancel: _onCancel,
        onPause: () => subscription?.pause,
        onResume: () => subscription?.resume);
  }

  final String host;
  final int? count;
  final Duration? interval;
  final Duration? timeout;
  final int? size;
  final int? ttl;
  final bool? ipv6;
  final bool? fragment;
  late StreamController<PingData> controller;
  StreamSubscription<PingData>? subscription;

  Stream<PingData> get stream => controller.stream;

  void onListen();

  void _onCancel() {
    subscription?.cancel();
    subscription = null;
  }

  void stop() => controller.close();
}
