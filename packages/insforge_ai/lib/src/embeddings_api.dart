import 'package:dio/dio.dart';

import 'errors.dart';
import 'models/embeddings.dart';

/// The `embeddings` sub-namespace.
class Embeddings {
  Embeddings(this._dio);

  final Dio _dio;

  /// Creates embeddings for [request].input (`POST /embeddings`).
  Future<EmbeddingsResponse> create(EmbeddingsRequest request) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/embeddings',
        data: request.toJson(),
      );
      return EmbeddingsResponse.fromJson(
        response.data ?? <String, dynamic>{},
      );
    } on DioException catch (e) {
      throw mapOpenRouterError(e);
    }
  }
}
