import 'package:intl/intl.dart';

class MatrixPresenceFormatter {
  static String label({required bool online, DateTime? lastSeen, DateTime? now}) {
    if (online) return 'Online';
    if (lastSeen == null) return '';
    final current = now ?? DateTime.now();
    final local = lastSeen.toLocal();
    final elapsed = current.difference(local);
    final time = DateFormat('HH:mm').format(local);
    if (elapsed.inMinutes >= 1 && elapsed.inMinutes < 60) {
      return 'Last seen ${elapsed.inMinutes} ${elapsed.inMinutes == 1 ? 'min' : 'mins'} ago';
    }
    final today = DateTime(current.year, current.month, current.day);
    final day = DateTime(local.year, local.month, local.day);
    final difference = today.difference(day).inDays;
    if (difference == 0) return 'Last seen Today at $time';
    if (difference == 1) return 'Last seen Yesterday at $time';
    if (difference > 1 && difference < 7) {
      return 'Last seen ${DateFormat('EEE').format(local)} at $time';
    }
    if (local.year == current.year) {
      return 'Last seen ${DateFormat('MMM d').format(local)} at $time';
    }
    return 'Last seen ${DateFormat('MM/dd/yy').format(local)}';
  }
}

class MatrixPresenceVisibility {
  static const allowed = <String>{'everyone', 'contacts', 'approved_users', 'nobody'};

  static bool canView(String value, {required bool isContact, required bool isApproved}) {
    switch (value.trim().toLowerCase()) {
      case 'nobody':
        return false;
      case 'contacts':
      case 'contacts_only':
        return isContact;
      case 'approved_users':
      case 'approved':
        return isApproved;
      case 'everyone':
      case 'public':
      case '':
        return true;
      default:
        return false;
    }
  }
}
