enum ActivityEffort {
  quiet,
  normal,
  active;

  static ActivityEffort? fromString(String? value) {
    if (value == null) return null;

    switch (value.toUpperCase()) {
      case 'QUIET':
        return ActivityEffort.quiet;
      case 'NORMAL':
        return ActivityEffort.normal;
      case 'ACTIVE':
        return ActivityEffort.active;
      default:
        return null;
    }
  }

  String toJson() {
    return name.toUpperCase();
  }
}