import 'package:dio/dio.dart';
import 'package:insforge_ai/insforge_ai.dart';
import 'package:insforge_core/insforge_core.dart';
import 'package:test/test.dart';

void main() {
  RequestOptions reqOptions() => RequestOptions(path: '/chat/completions');

  group('mapOpenRouterError', () {
    test('maps a nested {error:{message,code}} body to InsforgeHttpException',
        () {
      final err = DioException(
        requestOptions: reqOptions(),
        response: Response<dynamic>(
          requestOptions: reqOptions(),
          statusCode: 400,
          data: <String, dynamic>{
            'error': <String, dynamic>{
              'message': 'model is required',
              'code': 'invalid_request',
            },
          },
        ),
        type: DioExceptionType.badResponse,
      );

      final mapped = mapOpenRouterError(err);
      expect(mapped, isA<InsforgeHttpException>());
      final http = mapped as InsforgeHttpException;
      expect(http.statusCode, 400);
      expect(http.message, 'model is required');
      expect(http.error, 'invalid_request');
    });

    test('falls back to the HTTP status code as error when code is an int', () {
      final err = DioException(
        requestOptions: reqOptions(),
        response: Response<dynamic>(
          requestOptions: reqOptions(),
          statusCode: 402,
          data: <String, dynamic>{
            'error': <String, dynamic>{
              'message': 'Insufficient credits',
              'code': 402,
            },
          },
        ),
        type: DioExceptionType.badResponse,
      );

      final http = mapOpenRouterError(err) as InsforgeHttpException;
      expect(http.statusCode, 402);
      expect(http.message, 'Insufficient credits');
      expect(http.error, '402');
    });

    test('tolerates a flat error string body', () {
      final err = DioException(
        requestOptions: reqOptions(),
        response: Response<dynamic>(
          requestOptions: reqOptions(),
          statusCode: 500,
          data: 'Internal Server Error',
        ),
        type: DioExceptionType.badResponse,
      );

      final http = mapOpenRouterError(err) as InsforgeHttpException;
      expect(http.statusCode, 500);
      expect(http.message, 'Internal Server Error');
    });

    test('maps timeouts to InsforgeNetworkException', () {
      final err = DioException(
        requestOptions: reqOptions(),
        type: DioExceptionType.receiveTimeout,
        message: 'timed out',
      );
      expect(mapOpenRouterError(err), isA<InsforgeNetworkException>());
    });

    test('maps connection errors to InsforgeNetworkException', () {
      final err = DioException(
        requestOptions: reqOptions(),
        type: DioExceptionType.connectionError,
        message: 'no connection',
      );
      expect(mapOpenRouterError(err), isA<InsforgeNetworkException>());
    });
  });
}
