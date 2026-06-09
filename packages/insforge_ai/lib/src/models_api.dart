import 'package:dio/dio.dart';

import 'errors.dart';
import 'models/ai_model.dart';

/// The `models` sub-namespace.
class Models {
  Models(this._dio);

  final Dio _dio;

  /// Lists the available models (`GET /models`).
  Future<List<AiModel>> list() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>('/models');
      final data = response.data?['data'];
      if (data is! List) return <AiModel>[];
      return data
          .whereType<Map<String, dynamic>>()
          .map(AiModel.fromJson)
          .toList();
    } on DioException catch (e) {
      throw mapOpenRouterError(e);
    }
  }
}
