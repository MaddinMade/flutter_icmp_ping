import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_icmp_ping/src/base_ping_stream.dart';
import 'package:flutter_icmp_ping/src/models/ping_data.dart';
import 'package:flutter_icmp_ping/src/models/ping_error.dart';
import 'package:flutter_icmp_ping/src/models/ping_response.dart';
import 'package:flutter_icmp_ping/src/models/ping_summary.dart';

class PingiOS extends BasePing {
  PingiOS(
      String host, int? count, Duration? interval, Duration? timeout, bool? ipv6, int? size, int? ttl, bool? fragment)
      : super(host, count, interval, timeout, ipv6, size, ttl, fragment);

  static const _channelName = 'flutter_icmp_ping';
  static const _methodCh = MethodChannel('$_channelName/method');
  static const _eventCh = EventChannel('$_channelName/event');
  static Map<int, StreamController<PingData>> controllers = {};

  @override
  Future<void> onListen() async {
    await _methodCh.invokeMethod('start', {
      'hash': this.hashCode,
      'host': host,
      'count': count,
      'interval': interval,
      'timeout': timeout,
      'ipv6': ipv6,
    });
    controllers[this.hashCode] = controller;
    _eventCh
        .receiveBroadcastStream()
        .transform<Map<int, PingData>>(_iosTransformer)
        .listen((event) {
      controllers.forEach((key, controller) {
        final val = event[key];
        if (val != null) {
          controller.add(val);
          if (val.summary != null) {
            controller.close();
          }
        }
      });
      controllers.removeWhere((key, controller) => controller.isClosed);
    });
  }

  @override
  void stop() {
    _methodCh.invokeMethod('stop', {
      'hash': this.hashCode,
    }).then((_) {
      super.stop();
    });
  }

  /// StreamTransformer for iOS response from the event channel.
  StreamTransformer<dynamic, Map<int, PingData>> _iosTransformer =
      StreamTransformer.fromHandlers(
    handleData: (data, sink) {
      var err;
      switch (data['error']) {
        case 'RequestTimedOut':
          err = PingError.RequestTimedOut;
          break;
        case 'UnknownHost':
          err = PingError.UnknownHost;
          break;
      }
      var response;
      if (data['seq'] != null) {
        response = PingResponse(
          seq: data['seq'],
          ip: data['ip'],
          ttl: data['ttl'],
          time: Duration(
              microseconds:
                  (data['time'] * Duration.microsecondsPerSecond).floor()),
        );
      }
      var summary;
      if (data['received'] != null) {
        summary = PingSummary(
          received: data['received'],
          transmitted: data['transmitted'],
          time: Duration(
              microseconds:
                  (data['time'] * Duration.microsecondsPerSecond).floor()),
        );
      }
      sink.add({
        data['hash']: PingData(
          response: response,
          summary: summary,
          error: err,
        ),
      });
    },
  );
}
