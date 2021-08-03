/// Error code
class PingError {
  final String text;
  final ErrorType type;

  final String? rdns;
  final String? ip;

  const PingError(this.text, this.type, {this.rdns, this.ip});

  const PingError.liveExceeded(this.rdns, this.ip): type = ErrorType.LiveExceeded, text = 'rdns: $rdns, ip: $ip';


  static const RequestTimedOut = PingError('Request timed out', ErrorType.RequestTimedOut);
  static const UnknownHost = PingError('Unknown host', ErrorType.UnknownHost);
  static const Unknown = PingError('Unknown', ErrorType.Unknown);

  @override
  String toString() {
    return text;
  }
}

enum ErrorType{
  RequestTimedOut, UnknownHost, Unknown, LiveExceeded
}