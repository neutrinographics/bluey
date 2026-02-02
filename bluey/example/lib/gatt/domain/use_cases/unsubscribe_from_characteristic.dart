import 'dart:async';

/// Use case for unsubscribing from characteristic notifications.
///
/// Note: This use case simply cancels the subscription that was created
/// by [SubscribeToCharacteristic]. The actual unsubscription is handled
/// by the Bluey library when the stream subscription is cancelled.
class UnsubscribeFromCharacteristic {
  UnsubscribeFromCharacteristic(dynamic _);

  /// Cancels the given [subscription].
  Future<void> call(StreamSubscription subscription) async {
    await subscription.cancel();
  }
}
