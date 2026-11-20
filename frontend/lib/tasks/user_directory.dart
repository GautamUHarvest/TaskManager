import '../auth/auth_models.dart';
import 'task_models.dart';

/// The loaded team roster plus the signed-in user's id, with every
/// "how do we name this person" rule in one place. Each label degrades to
/// `User #id` while the roster is missing or doesn't know an id.
class UserDirectory {
  const UserDirectory(this.usersById, {this.currentUserId});

  static const UserDirectory empty = UserDirectory({});

  final Map<int, AuthUser> usersById;
  final int? currentUserId;

  List<AuthUser> get users => usersById.values.toList(growable: false);

  /// Short form for lists: "You", the display name, or "User #id".
  String shortLabel(int? id) {
    if (id == null) return 'Unassigned';
    if (id == currentUserId) return 'You';
    return usersById[id]?.displayName ?? 'User #$id';
  }

  /// Full form for detail views: "Display Name · EMP123". [ifNull] is what
  /// to show for a missing id ("Unassigned" for an assignee slot, "Unknown"
  /// for a creator).
  String fullLabel(int? id, {String ifNull = 'Unassigned'}) {
    if (id == null) return ifNull;
    final user = usersById[id];
    if (user == null) return 'User #$id';
    return '${user.displayName} · ${user.employeeId}';
  }

  /// Compact summary of a task's assignees for a list row:
  /// "Unassigned", "A", "A & B", or "A +2 others".
  String assigneesSummary(Task task) {
    final names = task.allAssigneeIds.map(shortLabel).toList();
    if (names.isEmpty) return 'Unassigned';
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} & ${names[1]}';
    return '${names[0]} +${names.length - 1} others';
  }

  /// Every assignee in full form, for the task detail header.
  String assigneesFull(Task task) {
    final ids = task.allAssigneeIds;
    if (ids.isEmpty) return 'Unassigned';
    return ids.map(fullLabel).join(' · ');
  }

  /// A never-empty name for [user]: display name, then employee id, then
  /// email, then "User #id" — the server may leave fields blank.
  static String nameOf(AuthUser user) {
    final name = user.displayName.trim();
    if (name.isNotEmpty) return name;
    if (user.employeeId.isNotEmpty) return user.employeeId;
    if (user.email.isNotEmpty) return user.email;
    return 'User #${user.id}';
  }
}
