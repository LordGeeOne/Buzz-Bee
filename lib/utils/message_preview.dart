import 'package:cloud_firestore/cloud_firestore.dart';

/// Canonical formatter for last-message previews shown in the dashboard
/// contact list. Used for both:
///   * the denormalized `connections/{id}.lastMessage` field, and
///   * legacy fallback when reading the latest `messages` doc directly.
///
/// The denormalized map stores the raw fields needed to format the
/// preview from either participant's perspective, so we never have to
/// fan out a separate read just to show "You:" vs no prefix.
class MessagePreview {
  MessagePreview._();

  /// Build the value to write into `connections/{id}.lastMessage`.
  /// Always pair this with `lastActivity` in the same write.
  ///
  /// The map intentionally mirrors the shape of a message doc so the
  /// same [format] function works on both.
  static Map<String, dynamic> buildLastMessage({
    required String type,
    required String fromUid,
    String? text,
    int? count,
    String? callOutcome,
  }) {
    return {
      'type': type,
      'fromUid': fromUid,
      if (text != null) 'text': text,
      if (count != null) 'count': count,
      if (callOutcome != null) 'callOutcome': callOutcome,
      'timestamp': FieldValue.serverTimestamp(),
    };
  }

  /// Format a message-shaped map into a human-readable preview, adding
  /// a "You: " prefix when [myUid] authored it.
  static String format(Map<String, dynamic> m, String myUid) {
    final type = (m['type'] as String?) ?? 'text';
    final mine = m['fromUid'] == myUid;
    final prefix = mine ? 'You: ' : '';
    switch (type) {
      case 'buzz':
        final count = ((m['count'] as num?) ?? 1).toInt();
        return '${prefix}Buzz${count > 1 ? ' ×$count' : ''}';
      case 'voice':
        return '${prefix}🎤 Voice message';
      case 'image':
        final count = ((m['count'] as num?) ?? 1).toInt();
        return '$prefix📷 ${count > 1 ? '$count photos' : 'Photo'}';
      case 'deleted':
        return mine ? 'You deleted a message' : 'Message deleted';
      case 'call':
        final outcome = (m['callOutcome'] as String?) ?? 'ended';
        switch (outcome) {
          case 'completed':
            return mine ? 'Outgoing call' : 'Incoming call';
          case 'missed':
            return mine ? 'No answer' : 'Missed call';
          case 'declined':
            return mine ? 'Call declined' : 'You declined';
          case 'failed':
            return "Call didn't connect";
          default:
            return 'Call';
        }
      case 'text':
      default:
        final text = ((m['text'] as String?) ?? '').trim();
        if (text.isEmpty) return '${prefix}Message';
        return '$prefix$text';
    }
  }

  /// Extract the timestamp from a message-shaped map (or null).
  static DateTime? timestampOf(Map<String, dynamic> m) {
    final ts = m['timestamp'];
    return ts is Timestamp ? ts.toDate() : null;
  }
}
