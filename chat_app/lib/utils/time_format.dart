// chat_app/lib/utils/time_format.dart
import 'package:intl/intl.dart';

/// 消息气泡内时间显示
String formatMsgTime(DateTime dt) {
  final now = DateTime.now();
  if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
    return DateFormat('HH:mm').format(dt);
  }
  return DateFormat('M/d HH:mm').format(dt);
}

/// 会话列表时间显示
String formatConversationTime(DateTime? dt) {
  if (dt == null) return '';
  final now = DateTime.now();
  final diff = now.difference(dt);

  if (diff.inSeconds < 60) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';

  final today = DateTime(now.year, now.month, now.day);
  final msgDate = DateTime(dt.year, dt.month, dt.day);
  final daysDiff = today.difference(msgDate).inDays;

  if (daysDiff == 0) return DateFormat('HH:mm').format(dt);
  if (daysDiff == 1) return '昨天';
  if (daysDiff < 7) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weekdays[dt.weekday - 1];
  }
  if (dt.year == now.year) return DateFormat('M/d').format(dt);
  return DateFormat('yyyy/M/d').format(dt);
}

/// 日期分隔头（用于聊天页的今天/昨天/日期）
String formatDateHead(DateTime d) {
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) return '今天';
  final yesterday = now.subtract(const Duration(days: 1));
  if (d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day) return '昨天';
  return '${d.month}月${d.day}日';
}
