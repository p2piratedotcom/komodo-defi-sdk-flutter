import 'dart:convert';

import 'package:komodo_defi_rpc_methods/src/internal_exports.dart';
import 'package:komodo_defi_types/komodo_defi_type_utils.dart';

class TaskStatusRequest
    extends BaseRequest<TaskStatusResponse, GeneralErrorResponse> {
  TaskStatusRequest({
    required this.taskId,
    required super.rpcPass,
    required super.method,
  }) : super(mmrpc: RpcVersion.v2_0);

  final int taskId;

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll({
      'userpass': rpcPass,
      'mmrpc': mmrpc,
      'method': method,
      'params': {'task_id': taskId, 'forget_if_finished': false},
    });

  @override
  TaskStatusResponse parse(Map<String, dynamic> json) {
    return TaskStatusResponse.parse(json);
  }
}

class TaskStatusResponse extends BaseResponse {
  TaskStatusResponse({
    required super.mmrpc,
    required this.status,
    required this.details,
    required this.isCompleted,
  });

  @override
  factory TaskStatusResponse.parse(Map<String, dynamic> json) {
    final rawDetails = json.valueOrNull<dynamic>('result', 'details');
    return TaskStatusResponse(
      mmrpc: json.value<String>('mmrpc'),
      status: json.value<String>('result', 'status'),
      // KDF can return structured details on completion. Keep the public
      // response type stable for task progress consumers.
      details: rawDetails is String
          ? rawDetails
          : rawDetails == null
          ? ''
          : jsonEncode(rawDetails),
      isCompleted: json.value<String>('result', 'status') == 'Ok',
    );
  }

  factory TaskStatusResponse.copyWith({
    required String mmrpc,
    required String status,
    required String details,
    required bool isCompleted,
  }) {
    return TaskStatusResponse(
      mmrpc: mmrpc,
      status: status,
      details: details,
      isCompleted: isCompleted,
    );
  }

  final String status;
  final String details;
  final bool isCompleted;

  @override
  Map<String, dynamic> toJson() => {
    'mmrpc': mmrpc,
    'result': {'status': status, 'details': details},
  };
}
