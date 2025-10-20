import 'api_response.dart';

class RequestDeduplicator {
  final _inflight = <String, Future<ApiResponse<dynamic>>>{};

  Future<ApiResponse<T>> run<T>(String key, Future<ApiResponse<T>> Function() fn) {
    if (_inflight.containsKey(key)) {
      return _inflight[key]!.then((v) => v as ApiResponse<T>);
    }
    final f = fn();
    _inflight[key] = f.then((v) => v as ApiResponse<dynamic>);
    return f.whenComplete(() => _inflight.remove(key));
  }
}

