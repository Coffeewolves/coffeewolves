String normalizeUserRole(Object? storedRole) {
  if (storedRole is! String) return 'user';
  final role = storedRole.trim().toLowerCase();
  if (role == 'cliente') return 'user';
  if (const {
    'gerencia',
    'gerente',
    'manager',
    'management',
    'administrator',
  }.contains(role)) {
    return 'admin';
  }
  return const {'user', 'barista', 'cajero', 'admin'}.contains(role)
      ? role
      : 'user';
}
