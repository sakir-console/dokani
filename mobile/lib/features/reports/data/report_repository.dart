import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'report_models.dart';

class ReportRepository {
  ReportRepository(this._dio);

  final Dio _dio;

  Future<ReportSummary> summary(ReportRange range) => _guard(() async {
        final response = await _dio.get<Map<String, dynamic>>('/reports/summary', queryParameters: range.toQuery());
        return ReportSummary.fromJson(response.data!);
      });

  Future<PaymentMethodsReport> paymentMethods(ReportRange range) => _guard(() async {
        final response =
            await _dio.get<Map<String, dynamic>>('/reports/payment-methods', queryParameters: range.toQuery());
        return PaymentMethodsReport.fromJson((response.data!['data'] as Map).cast<String, dynamic>());
      });

  Future<List<BestSeller>> bestSellers(ReportRange range, {bool byRevenue = false}) => _guard(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/reports/best-sellers',
          queryParameters: {...range.toQuery(), 'by': byRevenue ? 'revenue' : 'quantity', 'limit': 10},
        );
        return (response.data!['data'] as List)
            .map((e) => BestSeller.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      });

  /// Downloads a report file into the app's temporary folder.
  ///
  /// The file is fetched by the app (the request needs the login token, so a
  /// browser link would not work) and then handed to the phone's share sheet.
  Future<ExportedFile> export(ExportReport report, ExportFormat format, ReportRange range) => _guard(() async {
        final response = await _dio.get<List<int>>(
          '/reports/${report.apiValue}/export',
          queryParameters: {...range.toQuery(), 'format': format.name},
          options: Options(responseType: ResponseType.bytes),
        );

        final name = _fileName(response.headers.value('content-disposition')) ?? '${report.apiValue}.${format.name}';
        final file = File('${Directory.systemTemp.path}/$name');
        await file.writeAsBytes(response.data!, flush: true);

        return ExportedFile(path: file.path, name: name);
      });

  /// `attachment; filename="sales-20261112-101500.csv"` → the file name, kept to safe characters.
  static String? _fileName(String? contentDisposition) {
    final match = RegExp('filename="?([^";]+)"?').firstMatch(contentDisposition ?? '');
    final name = match?.group(1)?.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return (name == null || name.isEmpty) ? null : name;
  }

  Future<T> _guard<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (error) {
      // With a bytes response the error body is bytes too; the status still tells what happened.
      throw ApiException.fromDio(error);
    }
  }
}

final reportRepositoryProvider = Provider((ref) => ReportRepository(ref.watch(dioProvider)));

final reportSummaryProvider = FutureProvider.autoDispose
    .family<ReportSummary, ReportRange>((ref, range) => ref.watch(reportRepositoryProvider).summary(range));

final paymentMethodsReportProvider = FutureProvider.autoDispose
    .family<PaymentMethodsReport, ReportRange>((ref, range) => ref.watch(reportRepositoryProvider).paymentMethods(range));

typedef BestSellersQuery = ({ReportRange range, bool byRevenue});

final bestSellersProvider = FutureProvider.autoDispose.family<List<BestSeller>, BestSellersQuery>(
  (ref, query) => ref.watch(reportRepositoryProvider).bestSellers(query.range, byRevenue: query.byRevenue),
);
