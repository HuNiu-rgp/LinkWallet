import 'package:flutter/services.dart';

abstract class TransferNotifier {
  Future<bool> requestPermission();
  Future<void> show({
    required String id,
    required String title,
    required String body,
  });
}

class SystemTransferNotifier implements TransferNotifier {
  static const channel = MethodChannel('linkwallet/transfer_notifications');
  @override
  Future<bool> requestPermission() async =>
      await channel.invokeMethod<bool>('requestPermission') ?? false;
  @override
  Future<void> show({
    required String id,
    required String title,
    required String body,
  }) => channel.invokeMethod<void>('show', {
    'id': id,
    'title': title,
    'body': body,
  });
}
