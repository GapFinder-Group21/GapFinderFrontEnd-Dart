// Sign up form rules. Same rules the backend checks in RegisterRequest.
class RegisterValidators {
  static const nameMax = 50;
  static const emailMax = 100;
  static const phoneLength = 10;
  static const semesterMaxDigits = 2;
  static const passwordMin = 8;
  static const passwordMax = 64;

  // Chars allowed while typing or pasting in each field
  static final nameAllowedChars = RegExp(r'[A-Za-zÁÉÍÓÚáéíóúÑñÜü ]');
  static final emailAllowedChars = RegExp(r'[A-Za-z0-9@._-]');
  static final passwordAllowedChars = RegExp(r'[\x21-\x7E]'); // visible ASCII, no space

  static final _name = RegExp(r'^[A-Za-zÁÉÍÓÚáéíóúÑñÜü]+( [A-Za-zÁÉÍÓÚáéíóúÑñÜü]+)*$');
  static final _email = RegExp(r'^[a-z0-9]+([._-][a-z0-9]+)*@(gmail|outlook)\.com$');
  static final _phone = RegExp(r'^3\d{9}$');
  static final _password = RegExp(r'^[\x21-\x7E]+$');

  // Each check returns the error message, or null when the value is valid
  static String? name(String v) {
    if (v.isEmpty) return 'Ingresa tu nombre';
    if (v.length < 2 || v.length > nameMax) {
      return 'El nombre debe tener entre 2 y $nameMax caracteres';
    }
    if (!_name.hasMatch(v)) return 'El nombre solo puede tener letras y espacios';
    return null;
  }

  static String? email(String v) {
    if (v.isEmpty || v.length > emailMax || !_email.hasMatch(v)) {
      return 'Ingrese una dirección válida (@gmail.com o @outlook.com)';
    }
    return null;
  }

  static String? semester(String v) {
    final n = int.tryParse(v);
    if (n == null || n < 1 || n > 12) return 'El semestre debe ser un número entre 1 y 12';
    return null;
  }

  static String? phone(String v) {
    if (v.isEmpty) return 'Ingresa tu número de teléfono';
    if (!_phone.hasMatch(v)) return 'El teléfono debe tener 10 dígitos y empezar por 3';
    return null;
  }

  static String? password(String v) {
    if (v.length < passwordMin || v.length > passwordMax) {
      return 'La contraseña debe tener entre $passwordMin y $passwordMax caracteres';
    }
    if (!_password.hasMatch(v)) return 'La contraseña no puede tener espacios, tildes ni emojis';
    return null;
  }

  static String? confirmPassword(String password, String confirm) =>
      password == confirm ? null : 'Las contraseñas no coinciden';

  // Trims ends and keeps one space between words
  static String normalizeName(String v) => v.trim().replaceAll(RegExp(r'\s+'), ' ');
}
