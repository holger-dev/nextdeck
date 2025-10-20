class ApiResponse<T> {
  final T? data;
  final String? etag;
  final DateTime? lastModified;
  final int status;
  bool get isNotModified => status == 304;
  const ApiResponse({this.data, this.etag, this.lastModified, required this.status});

  static ApiResponse<T> ok<T>(T data, {String? etag, DateTime? lastModified}) =>
      ApiResponse<T>(data: data, etag: etag, lastModified: lastModified, status: 200);
  static ApiResponse<T> notModified<T>() => ApiResponse<T>(status: 304);
}

