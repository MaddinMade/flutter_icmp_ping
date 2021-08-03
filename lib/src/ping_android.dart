import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:flutter_icmp_ping/src/base_ping_stream.dart';
import 'package:flutter_icmp_ping/src/models/ping_data.dart';
import 'package:flutter_icmp_ping/src/models/ping_error.dart';
import 'package:flutter_icmp_ping/src/models/ping_response.dart';
import 'package:flutter_icmp_ping/src/models/ping_summary.dart';

import '../flutter_icmp_ping.dart';

class PingAndroid extends BasePing {
  PingAndroid(String host, int? count, Duration? interval, Duration? timeout, bool? ipv6, int? size, int? ttl, bool? fragment)
      : super(host, count, interval, timeout, ipv6, size, ttl, fragment);

  static final _resRegex = RegExp(r'from (.*): icmp_seq=(\d+) ttl=(\d+) time=((\d+).?(\d+))');
  static final _liveExceededRegex = RegExp(r'(F|f)rom ([^\s:]*)( \(([^)]+)\))?(:)? icmp_seq=(\d+) (T|t)ime to live exceeded');
  static final _seqRegex = RegExp(r'icmp_seq=(\d+)');
  static final _summaryRegexes = [
    RegExp(r'(\d+) packets transmitted'),
    RegExp(r'(\d+) received'),
    RegExp(r'time (\d+)ms'),
  ];

  Process? _process;

  @override
  Future<void> onListen() async {
    if (_process != null) {
      throw Exception('ping is already running');
    }
    var params = ['-O', '-n'];
    if (count != null) params.add('-c $count');
    if (timeout != null) params.add('-W ${timeout!.inMicroseconds / 1000000}');
    if (interval != null) params.add('-i ${interval!.inMicroseconds / 1000000}');
    if (size != null) params.add('-s $size');
    if (ttl != null) params.add('-t $ttl');
    if (fragment != null) params.add('-M ${(fragment!)?'dont':'do'}');
    _process = await Process.start((ipv6 ?? false) ? 'ping6' : 'ping', [...params, host]);
    if (_process == null) {
      throw Exception('failed to start ping.');
    }

    _process?.exitCode.then((value) {
      controller.close();
    });

    subscription = StreamGroup.merge([_process!.stderr, _process!.stdout])
        .transform(utf8.decoder)
        .transform(LineSplitter())
        .transform<PingData>(_androidTransformer)
        .listen(controller.add);
  }

  @override
  void stop() {
    _process?.kill(ProcessSignal.sigint);
    _process = null;
  }

  /// StreamTransformer for Android response from process stdout/stderr.
  static StreamTransformer<String, PingData> _androidTransformer = StreamTransformer.fromHandlers(
    handleError: (data, trace, sink) {print(data.toString()); sink.add(PingData(error: PingError(data.toString(), ErrorType.Unknown)));},
    handleData: (data, sink) {
      if (data.contains('unknown host')) {
        sink.add(
          PingData(
            error: PingError.UnknownHost,
          ),
        );
      }
      if (data.contains('bytes from')) {
        final match = _resRegex.firstMatch(data);
        if (match == null) {
          return;
        }
        final seq = match.group(2);
        final ttl = match.group(3);
        final time = match.group(4);
        sink.add(
          PingData(
            response: PingResponse(
              ip: match.group(1),
              seq: seq == null ? null : int.parse(seq) - 1,
              ttl: ttl == null ? null : int.parse(ttl),
              time: time == null ? null : Duration(microseconds: ((double.parse(time)) * 1000).floor()),
            ),
          ),
        );
        return;
      }
      if (data.contains('no answer yet')) {
        final match = _seqRegex.firstMatch(data);
        if (match == null) {
          return;
        }
        final seq = match.group(1);
        sink.add(
          PingData(
            response: PingResponse(
              seq: seq == null ? null : int.parse(seq) - 1,
            ),
            error: PingError.RequestTimedOut,
          ),
        );
        return;
      }
      if (data.contains('packet loss')) {
        final transmitted = _summaryRegexes[0].firstMatch(data);
        final received = _summaryRegexes[1].firstMatch(data);
        final time = _summaryRegexes[2].firstMatch(data);
        if (transmitted == null || received == null || time == null) {
          return;
        }
        final group1 = transmitted.group(1);
        final group2 = received.group(1);
        final group3 = time.group(1);
        sink.add(
          PingData(
            summary: PingSummary(
              transmitted: group1 == null ? null : int.parse(group1),
              received: group2 == null ? null : int.parse(group2),
              time: group3 == null ? null : Duration(milliseconds: int.parse(group3)),
            ),
          ),
        );
        return;
      }
      final match = _liveExceededRegex.firstMatch(data);
      if(match != null){
        String? rdns = match.group(2);
        String? ip = match.group(4);

        if(ip == null){
          ip = rdns;
          rdns = null;
        }
        sink.add(PingData(error: PingError.liveExceeded(rdns, ip)));
        return;
      }
    },
  );
}
