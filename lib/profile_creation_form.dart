import 'dart:async';
import 'dart:convert';

import 'package:country_code_picker/country_code_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';

import 'chat_credit_service.dart';
import 'username_registry_service.dart';

const _maxProfileImageBytes = 200 * 1024;

Uint8List compressProfileImageBytes(Uint8List sourceBytes) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(sourceBytes);
  } on RangeError {
    throw const FormatException('No se pudo leer el archivo de imagen.');
  }
  if (decoded == null) {
    throw const FormatException('No se pudo leer el archivo de imagen.');
  }
  final oriented = img.bakeOrientation(decoded);

  for (final maxDimension in [512, 384, 256, 192]) {
    final resized = img.copyResize(
      oriented,
      width: oriented.width >= oriented.height ? maxDimension : null,
      height: oriented.height > oriented.width ? maxDimension : null,
    );
    for (final quality in [80, 65, 50, 35, 25]) {
      final compressed = Uint8List.fromList(
        img.encodeJpg(resized, quality: quality),
      );
      if (compressed.length <= _maxProfileImageBytes) return compressed;
    }
  }
  throw const FormatException(
    'No se pudo reducir la foto a menos de 200 KB. Elige otra imagen.',
  );
}

enum ProfileAuthMode { signIn, register }

class ProfileAuthForm extends StatefulWidget {
  const ProfileAuthForm({
    super.key,
    required this.initialMode,
    required this.onAuthenticated,
    this.onAvatarSelected,
    this.showSignOutButton = true,
  });

  final ProfileAuthMode initialMode;
  final ValueChanged<User> onAuthenticated;
  final ValueChanged<Uint8List>? onAvatarSelected;
  final bool showSignOutButton;

  @override
  State<ProfileAuthForm> createState() => _ProfileAuthFormState();
}

class _ProfileAuthFormState extends State<ProfileAuthForm> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _imagePicker = ImagePicker();
  late ProfileAuthMode _mode;
  String _phoneCountryCode = '+591';
  String _phoneCountryIsoCode = 'BO';
  DateTime? _birthDate;
  Uint8List? _avatarBytes;
  bool _birthdayMarketingConsent = false;
  bool _isLoading = false;
  bool _passwordVisible = false;
  bool _authCallbackSent = false;
  bool _birthdaySyncFailed = false;
  String? _errorMessage;

  static const _gold = Color(0xFFC6A06A);
  static const _cream = Color(0xFFE9DCCB);
  static const _muted = Color(0xFFB7AA9D);
  static const _panel = Color(0xFF211D19);
  static const _blockedUsernameWords = {
    'boludo',
    'cabron',
    'cabrón',
    'coño',
    'culo',
    'fuck',
    'mierda',
    'pendejo',
    'puta',
    'puto',
    'shit',
    'verga',
  };

  bool get _isRegistering => _mode == ProfileAuthMode.register;
  User? get _currentUser => FirebaseAuth.instance.currentUser;
  bool get _isAdult => _birthDate != null && _ageOn(_birthDate!) >= 18;
  bool get _canUploadProfilePhoto {
    final user = _currentUser;
    return user != null && _hasVerifiedIdentity(user);
  }

  bool _hasVerifiedIdentity(User user) =>
      user.emailVerified || (user.phoneNumber?.trim().isNotEmpty ?? false);
  bool get _isPasswordLongEnoughForHighlight =>
      _passwordController.text.length >= 8;
  bool _hasEmailAddress(String value) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim());
  String get _normalizedPhoneNumber =>
      _phoneController.text.replaceAll(RegExp(r'\D'), '');

  bool get _isPhoneNumberValid {
    final fullNumber = '$_phoneCountryCode$_normalizedPhoneNumber';
    final digitCount = fullNumber.replaceAll(RegExp(r'\D'), '').length;
    return _normalizedPhoneNumber.length >= 7 &&
        digitCount <= 15 &&
        RegExp(r'^\+[1-9][0-9]{6,14}$').hasMatch(fullNumber);
  }

  bool get _canSubmit {
    if (_isLoading) return false;

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (password.isEmpty) return false;
    if (!_hasEmailAddress(email)) return false;
    if (!_isRegistering) return true;
    return _validateFullName(_fullNameController.text) == null &&
        _validateUsername(_usernameController.text) == null &&
        _isAdult &&
        password.length >= 8;
  }

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _fullNameController.text = _currentUser?.displayName ?? '';
    if (_isRegistering) _emailController.text = _currentUser?.email ?? '';
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _normalizeUsername(String value) {
    return value
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  String? _validateUsername(String? value) {
    final username = value?.trim() ?? '';
    final formatError = UsernameRegistryService.validate(username);
    if (formatError != null) return formatError;
    final normalized = _normalizeUsername(username);
    final words = normalized.split(' ').toSet();
    final compact = normalized.replaceAll(' ', '');
    if (_blockedUsernameWords.any(
      (word) {
        final blocked = _normalizeUsername(word).replaceAll(' ', '');
        return words.contains(blocked) || compact.contains(blocked);
      },
    )) {
      return 'Ese nombre contiene una palabra no permitida.';
    }
    return null;
  }

  String? _validateFullName(String? value) {
    final fullName = value?.trim() ?? '';
    final nameParts = fullName.split(RegExp(r'\s+'));
    if (fullName.length > 80 || nameParts.length < 2) {
      return 'Ingresa tu nombre y apellido.';
    }
    return null;
  }

  int _ageOn(DateTime birthDate) {
    final today = DateTime.now();
    var age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  String _formatBirthDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  Future<void> _pickBirthDate() async {
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate:
          _birthDate ?? DateTime(today.year - 18, today.month, today.day),
      firstDate: DateTime(1900),
      lastDate: today,
      helpText: 'SELECCIONA TU FECHA DE NACIMIENTO',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _gold,
            onPrimary: Color(0xFF171411),
            surface: _panel,
            onSurface: _cream,
          ),
          dialogTheme: const DialogThemeData(backgroundColor: _panel),
        ),
        child: child!,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _birthDate = selected;
      _errorMessage = null;
    });
  }

  String _formatBirthDateForStorage(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  DateTime? _dateFromStoredValue(Object? value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Future<void> _completeBirthDate() async {
    final today = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(today.year - 18, today.month, today.day),
      firstDate: DateTime(1900),
      lastDate: today,
      helpText: 'SELECCIONA TU FECHA DE NACIMIENTO',
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: _gold,
            onPrimary: Color(0xFF171411),
            surface: _panel,
            onSurface: _cream,
          ),
          dialogTheme: const DialogThemeData(backgroundColor: _panel),
        ),
        child: child!,
      ),
    );
    if (selected == null || !mounted) return;
    await _saveBirthdayDetails(
      selected,
      _birthdayMarketingConsent,
    );
  }

  Future<void> _saveBirthdayConsent(
    DateTime birthDate,
    bool consent,
  ) =>
      _saveBirthdayDetails(birthDate, consent);

  Future<void> _saveBirthdayDetails(
    DateTime birthDate,
    bool marketingConsent,
  ) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('saveBirthdayDetails')
          .call({
        'birthDate': _formatBirthDateForStorage(birthDate),
        'birthdayMarketingConsent': marketingConsent,
      });
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _birthdayMarketingConsent = marketingConsent;
        _errorMessage = 'Fecha y preferencias de cumpleaños guardadas.';
      });
    } on FirebaseFunctionsException catch (error, stackTrace) {
      debugPrint(
          'No se pudieron guardar los datos de cumpleaños: ${error.code}');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.message ??
            'No se pudieron guardar los datos de cumpleaños (${error.code}).';
      });
    } catch (error, stackTrace) {
      debugPrint('Error al guardar los datos de cumpleaños: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'No se pudieron guardar los datos de cumpleaños.';
      });
    }
  }

  Future<void> _pickAvatar() async {
    final user = _currentUser;
    if (user == null || !_hasVerifiedIdentity(user)) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            '⚠️ Confirma tu identidad por correo o teléfono para poder subir '
            'una foto de perfil.';
      });
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: _panel,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'AGREGA TU FOTO DE PERFIL',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _cream,
                  fontSize: 13,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                key: const ValueKey('profile-avatar-camera'),
                onPressed: () => Navigator.pop(context, ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('PERMITIR CÁMARA Y TOMAR FOTO'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('profile-avatar-gallery'),
                onPressed: () => Navigator.pop(context, ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('ELEGIR FOTO'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Si el navegador pregunta, selecciona “Permitir cámara”. '
                'La foto se revisará antes de guardarse.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;

    try {
      final image = await _imagePicker.pickImage(
        source: source,
        imageQuality: 95,
        maxWidth: 1200,
        maxHeight: 1200,
      );
      if (image == null || !mounted) return;
      final sourceBytes = await image.readAsBytes();
      final bytes = await compute(compressProfileImageBytes, sourceBytes);
      if (!mounted) return;
      setState(() => _avatarBytes = bytes);
      await _moderateAndSaveAvatar(user, bytes);
    } catch (error, stackTrace) {
      debugPrint('No se pudo seleccionar la foto de perfil: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _errorMessage = _avatarErrorMessage(error);
      });
    }
  }

  String _avatarErrorMessage(Object error) {
    final details = error.toString().toLowerCase();
    final permissionDenied = error is PlatformException &&
            (error.code.toLowerCase().contains('denied') ||
                error.code.toLowerCase().contains('permission')) ||
        details.contains('notallowederror') ||
        details.contains('permission denied') ||
        details.contains('camera_access_denied');
    if (permissionDenied) {
      return 'Para tomar la foto, permite el acceso a la cámara cuando Chrome '
          'lo solicite. Si ya lo bloqueaste, cambia el permiso de Cámara en '
          'la configuración del sitio. También puedes elegir una foto.';
    }
    if (error is FirebaseFunctionsException &&
        error.message == 'profile-photo-rejected') {
      return 'No pudimos aprobar esta foto. Acércate al Coffee Wolves que te '
          'quede más cerca y nuestro equipo te ayudará a verificarla.';
    }
    if (error is FirebaseFunctionsException &&
        error.code == 'failed-precondition') {
      return 'Confirma tu identidad por correo o teléfono antes de subir '
          'una foto de perfil.';
    }
    return 'No pudimos verificar la foto ahora. Acércate al Coffee Wolves '
        'que te quede más cerca y nuestro equipo te ayudará.';
  }

  Future<bool> _authenticateOnDeviceIfAvailable() async {
    if (kIsWeb) return true;
    try {
      final localAuth = LocalAuthentication();
      if (!await localAuth.isDeviceSupported() ||
          !await localAuth.canCheckBiometrics) {
        return true;
      }
      return await localAuth.authenticate(
        localizedReason: 'Confirma el registro de tu cuenta Coffee Wolves',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('No se pudo usar la biometría del dispositivo: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _errorMessage =
              'No se pudo completar la comprobación biométrica. Inténtalo '
              'otra vez o usa el navegador para registrarte.';
        });
      }
      return false;
    }
  }

  Future<void> _moderateAndSaveAvatar(User user, Uint8List bytes) async {
    if (!_hasVerifiedIdentity(user)) {
      throw FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Confirma tu identidad por correo o teléfono.',
      );
    }
    if (bytes.length > _maxProfileImageBytes) {
      throw FirebaseFunctionsException(
        code: 'invalid-argument',
        message: 'La imagen supera el límite de 200 KB.',
      );
    }
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'us-central1',
      ).httpsCallable('moderateProfilePhoto');
      final result = await callable.call<Map<String, dynamic>>({
        'imageBase64': base64Encode(bytes),
      });
      final path = result.data['path'];
      if (path is! String || path.isEmpty) {
        throw StateError('La moderación no devolvió la ruta de la foto.');
      }
      final photoUrl =
          await FirebaseStorage.instance.ref(path).getDownloadURL();
      await user.updatePhotoURL(photoUrl);
      await user.reload();
      if (!mounted) return;
      widget.onAvatarSelected?.call(bytes);
      setState(() {
        _isLoading = false;
        _errorMessage = 'Foto aprobada y perfil verificado por correo.';
      });
    } on FirebaseFunctionsException {
      if (!mounted) rethrow;
      setState(() => _isLoading = false);
      rethrow;
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
      rethrow;
    }
  }

  void _refreshSubmitButton(String _) {
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isLoading = true;
      _authCallbackSent = false;
      _birthdaySyncFailed = false;
      _errorMessage = null;
    });

    var verificationEmailSent = false;
    try {
      if (_isRegistering && !await _authenticateOnDeviceIfAvailable()) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage =
                'No se confirmó la biometría. No se creó la cuenta.';
          });
        }
        return;
      }
      final auth = FirebaseAuth.instance;
      final identifier = _emailController.text.trim();
      final credential = _isRegistering
          ? await auth.createUserWithEmailAndPassword(
              email: identifier,
              password: _passwordController.text,
            )
          : await auth.signInWithEmailAndPassword(
              email: identifier,
              password: _passwordController.text,
            );
      final user = credential.user;
      if (user == null) {
        throw FirebaseAuthException(
          code: 'missing-user',
          message: 'Firebase no devolvió una cuenta autenticada.',
        );
      }

      if (_isRegistering) {
        final firestore = FirebaseFirestore.instance;
        final userReference = firestore.collection('users').doc(user.uid);
        try {
          await firestore.runTransaction<void>((transaction) async {
            final existingProfile = await transaction.get(userReference);
            final profileData = {
              'email': user.email,
              'displayName': _fullNameController.text.trim(),
              'username': _usernameController.text.trim(),
              'role': 'user',
              'birthDate': _formatBirthDateForStorage(_birthDate!),
              'phoneNumber': '$_phoneCountryCode$_normalizedPhoneNumber',
              'phoneCountryCode': _phoneCountryCode,
              'phoneCountryIsoCode': _phoneCountryIsoCode,
              'phoneNationalNumber': _normalizedPhoneNumber,
              'phoneVerified': false,
              'messageCredits': startingChatCredits,
              'messageCreditsUpdatedAt': FieldValue.serverTimestamp(),
              'createdAt': FieldValue.serverTimestamp(),
              'isVerified': false,
            };
            await UsernameRegistryService.reserveInTransaction(
              transaction: transaction,
              firestore: firestore,
              uid: user.uid,
              username: _usernameController.text,
              role: 'user',
              previousUsername: existingProfile.data()?['username'] as String?,
            );
            transaction.set(userReference, profileData);
          });
        } on UsernameAlreadyTakenException {
          await user.delete();
          rethrow;
        }
        await user.updateDisplayName(_fullNameController.text.trim());
        await user.reload();
        final registeredUser = FirebaseAuth.instance.currentUser ?? user;
        try {
          await registeredUser.sendEmailVerification();
          verificationEmailSent = true;
        } on FirebaseAuthException catch (error, stackTrace) {
          debugPrint(
            'La cuenta se creó, pero no se pudo enviar el correo de '
            'verificación (${error.code}).',
          );
          debugPrintStack(stackTrace: stackTrace);
        }
        try {
          await FirebaseFunctions.instanceFor(region: 'us-central1')
              .httpsCallable('saveBirthdayDetails')
              .call({
            'birthDate': _formatBirthDateForStorage(_birthDate!),
            'birthdayMarketingConsent': _birthdayMarketingConsent,
          });
        } on FirebaseFunctionsException catch (error, stackTrace) {
          debugPrint(
            'No se pudieron completar los datos de cumpleaños: ${error.code}',
          );
          debugPrintStack(stackTrace: stackTrace);
          _birthdaySyncFailed = true;
        }
      }

      final activeUser = FirebaseAuth.instance.currentUser ?? user;
      final refreshedUser = activeUser;
      if (!_isRegistering &&
          !refreshedUser.isAnonymous &&
          !refreshedUser.emailVerified) {
        _completeAuthentication(refreshedUser);
        return;
      }
      if (_avatarBytes != null) {
        await _moderateAndSaveAvatar(refreshedUser, _avatarBytes!);
      }
      if (_isRegistering && !refreshedUser.isAnonymous) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = verificationEmailSent
                ? 'Cuenta creada. Revisa tu correo y confirma la dirección '
                    'antes de entrar a Coffee Wolves.'
                : 'La cuenta se creó, pero no se pudo enviar el correo. '
                    'Usa el botón para reenviarlo.';
          });
        }
        return;
      }
      if (_isRegistering && _birthdaySyncFailed && mounted) {
        setState(() {
          _errorMessage =
              'Tu cuenta se creó, pero no se pudo guardar la preferencia de '
              'cumpleaños. Podrás configurarla en tu perfil.';
        });
      }
      _completeAuthentication(refreshedUser);
    } on UsernameAlreadyTakenException catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    } on FirebaseAuthException catch (error) {
      debugPrint(
        'Firebase Authentication rechazó la operación (${error.code}).',
      );
      if (!mounted) return;
      setState(() {
        _errorMessage = _messageForAuthError(error);
        _isLoading = false;
      });
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
        'No se pudo completar la operación de Firebase (${error.code}).',
      );
      if (!mounted) return;
      setState(() {
        _errorMessage = _avatarErrorMessage(error);
        _isLoading = false;
      });
    } catch (error) {
      debugPrint('No se pudo completar el flujo de autenticación: $error');
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'No se pudo completar la solicitud. Inténtalo de nuevo.';
        _isLoading = false;
      });
    }
  }

  void _completeAuthentication(User user) {
    if (_authCallbackSent || !mounted) return;
    _authCallbackSent = true;
    widget.onAuthenticated(user);
  }

  Future<void> _signOutAndClearAccount() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      _emailController.clear();
      _passwordController.clear();
      _formKey.currentState?.reset();
      _authCallbackSent = false;
      setState(() {
        _isLoading = false;
        _mode = ProfileAuthMode.signIn;
        _errorMessage = 'Sesión cerrada. Ya puedes ingresar otra cuenta.';
      });
    } on FirebaseAuthException catch (error, stackTrace) {
      debugPrint(
        'No se pudo cerrar la sesión de Coffee Wolves (${error.code}).',
      );
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            'No se pudo cerrar la sesión (${error.code}). Inténtalo de nuevo.';
      });
    } catch (error, stackTrace) {
      debugPrint('Error al cerrar la sesión de Coffee Wolves: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'No se pudo cerrar la sesión. Inténtalo de nuevo.';
      });
    }
  }

  String _messageForAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-email':
        return 'El correo no tiene un formato válido.';
      case 'user-disabled':
        return 'Esta cuenta está deshabilitada.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
      case 'invalid-login-credentials':
        return 'Correo o contraseña incorrectos.';
      case 'account-exists-with-different-credential':
        return 'Esta cuenta usa otro método de acceso.';
      case 'email-already-in-use':
        return 'Ya existe una cuenta con ese correo. Inicia sesión.';
      case 'weak-password':
        return 'La contraseña debe tener al menos 8 caracteres.';
      case 'operation-not-allowed':
        return 'Activa Correo/Contraseña en Firebase Authentication.';
      case 'network-request-failed':
        return 'No hay conexión. Revisa tu internet e inténtalo otra vez.';
      case 'unauthorized-domain':
        return 'Este dominio no está autorizado en Firebase Authentication. '
            'Agrega localhost y el dominio de tu app en Authentication > '
            'Configuración > Dominios autorizados.';
      case 'invalid-api-key':
        return 'La configuración de Firebase no es válida. Revisa el apiKey '
            'y el proyecto configurado en la app.';
      case 'internal-error':
        return 'Firebase no pudo completar el acceso. Inténtalo otra vez; '
            'si continúa, revisa el estado de Authentication en Firebase.';
      case 'too-many-requests':
        return 'Firebase bloqueó temporalmente los intentos desde este '
            'dispositivo por actividad inusual. Espera antes de volver a '
            'intentarlo; cerrar sesión no quita ese bloqueo.';
      case 'missing-user':
      case 'missing-verification':
        return error.message ?? 'No se pudo confirmar la cuenta.';
      default:
        return 'No se pudo completar el acceso. Inténtalo de nuevo.';
    }
  }

  Future<void> _sendPasswordReset() async {
    final emailController = TextEditingController();
    ModalRoute<dynamic>? recoveryDialogRoute;
    String? email;
    try {
      email = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          recoveryDialogRoute = ModalRoute.of(dialogContext);
          return AlertDialog(
            backgroundColor: _panel,
            title: const Text(
              'Recuperar contraseña',
              style: TextStyle(color: _cream),
            ),
            content: TextField(
              controller: emailController,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Correo de recuperación',
                hintText: 'correo@ejemplo.com',
                prefixIcon: Icon(Icons.email_outlined),
              ),
              onSubmitted: (value) =>
                  Navigator.of(dialogContext).pop(value.trim()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('CANCELAR'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext)
                    .pop(emailController.text.trim()),
                child: const Text('ENVIAR ENLACE'),
              ),
            ],
          );
        },
      );
      await recoveryDialogRoute?.completed;
    } finally {
      emailController.dispose();
    }
    if (email == null || !mounted) return;
    if (!_hasEmailAddress(email)) {
      setState(
        () => _errorMessage =
            'Escribe un correo válido para recuperar la cuenta.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Si esa dirección corresponde a una cuenta, recibirás un enlace '
            'para restablecer la contraseña.';
      });
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _messageForAuthError(error);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'No se pudo enviar el enlace: $error';
      });
    }
  }

  void _changeMode(ProfileAuthMode mode) {
    setState(() {
      _mode = mode;
      _emailController.clear();
      _passwordController.clear();
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && !user.isAnonymous) {
      return _buildAuthenticatedProfile(context, user);
    }
    return _buildAuthForm(context);
  }

  Widget _buildAuthenticatedProfile(BuildContext context, User user) {
    final profileStream = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: profileStream,
      builder: (context, snapshot) {
        final profile = snapshot.data?.data();
        final storedName = (profile?['displayName'] as String?)?.trim();
        final name = storedName?.isNotEmpty == true
            ? storedName!
            : user.displayName?.trim().isNotEmpty == true
                ? user.displayName!.trim()
                : 'Usuario Wolves';
        final email = (profile?['email'] as String?)?.trim();
        final storedPhone = (profile?['phoneNumber'] as String?)?.trim();
        final phone =
            storedPhone?.isNotEmpty == true ? storedPhone : user.phoneNumber;
        final birthDate = profile?['birthDate'] ?? profile?['dateOfBirth'];

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'MI PERFIL',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _cream,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: CircleAvatar(
                radius: 44,
                backgroundColor: _panel,
                child: user.photoURL?.isNotEmpty == true
                    ? ClipOval(
                        child: Image.network(
                          user.photoURL!,
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                            Icons.person_outline,
                            color: _gold,
                            size: 36,
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.person_outline,
                        color: _gold,
                        size: 36,
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _cream,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (profile?['isVerified'] == true) ...[
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.verified,
                    key: ValueKey('verified-user-badge'),
                    color: Color(0xFF42A5F5),
                    size: 19,
                  ),
                ],
              ],
            ),
            TextButton.icon(
              onPressed: _isLoading || !_hasVerifiedIdentity(user)
                  ? null
                  : _pickAvatar,
              icon: const Icon(Icons.camera_alt_outlined, size: 16),
              label: Text(
                profile?['isVerified'] == true
                    ? 'Tomar otra selfie y verificar'
                    : 'Tomar selfie para tu foto de perfil',
              ),
            ),
            if (!_hasVerifiedIdentity(user))
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Confirma tu identidad por correo o teléfono para subir una foto.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              ),
            const SizedBox(height: 16),
            _profileValue(
              icon: Icons.email_outlined,
              label: 'CORREO ELECTRÓNICO',
              value: email?.isNotEmpty == true
                  ? email!
                  : user.email ?? 'No disponible',
            ),
            if (phone?.isNotEmpty == true)
              _profileValue(
                icon: Icons.phone_outlined,
                label: 'CELULAR',
                value: phone!,
              ),
            _profileValue(
              icon: Icons.cake_outlined,
              label: 'FECHA DE NACIMIENTO',
              value: _formatStoredBirthDate(birthDate),
            ),
            if (_dateFromStoredValue(birthDate) == null)
              OutlinedButton.icon(
                key: const ValueKey('profile-add-birth-date'),
                onPressed: _isLoading ? null : _completeBirthDate,
                icon: const Icon(Icons.calendar_month_outlined, size: 17),
                label: const Text('REGISTRAR FECHA DE NACIMIENTO'),
              )
            else
              SwitchListTile(
                key: const ValueKey('birthday-marketing-consent'),
                contentPadding: EdgeInsets.zero,
                value: profile?['birthdayMarketingConsent'] == true,
                activeColor: _gold,
                title: const Text(
                  'Invitación de cumpleaños',
                  style: TextStyle(color: _cream, fontSize: 13),
                ),
                subtitle: const Text(
                  'Acepto recibir una felicitación e invitación promocional '
                  'por correo. Puedo retirar mi consentimiento.',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
                onChanged: _isLoading
                    ? null
                    : (consent) => _saveBirthdayConsent(
                          _dateFromStoredValue(birthDate)!,
                          consent,
                        ),
              ),
            if (_dateFromStoredValue(birthDate) == null)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  'La fecha solo se usa para validar edad y, si lo autorizas, '
                  'preparar una felicitación de cumpleaños.',
                  style: TextStyle(color: _muted, fontSize: 10),
                ),
              ),
            if (snapshot.hasError)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'No se pudieron cargar los datos adicionales del perfil.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFFFF8A80), fontSize: 12),
                ),
              ),
            const SizedBox(height: 16),
            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _errorMessage!.startsWith('Foto aprobada')
                      ? const Color(0xFFB8C89A)
                      : const Color(0xFFFF8A80),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (widget.showSignOutButton)
              OutlinedButton.icon(
                onPressed: _isLoading ? null : _signOutAndClearAccount,
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout),
                label: Text(_isLoading ? 'CERRANDO SESIÓN…' : 'CERRAR SESIÓN'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _gold,
                  side: BorderSide(color: _gold.withValues(alpha: 0.55)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _profileValue({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _gold.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: _gold, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 9,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: const TextStyle(color: _cream, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatStoredBirthDate(Object? value) {
    DateTime? date;
    if (value is Timestamp) date = value.toDate();
    if (value is DateTime) date = value;
    if (value is String) date = DateTime.tryParse(value);
    if (date == null) return 'No registrada en el perfil';
    return _formatBirthDate(date);
  }

  Widget _buildAuthForm(BuildContext context) {
    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: _panel,
      labelStyle: const TextStyle(color: _muted),
      prefixIconColor: _gold,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _gold.withValues(alpha: 0.28)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _gold),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFFF8A80)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFFF8A80)),
      ),
    );
    return Form(
      key: _formKey,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isRegistering ? 'ÚNETE A LA MANADA' : 'QUÉ BUENO VERTE',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _cream,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isRegistering
                ? 'Crea tu cuenta Coffee Wolves'
                : 'Inicia sesión en tu cuenta Coffee Wolves.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted),
          ),
          const SizedBox(height: 22),
          if (_isRegistering) ...[
            Center(
              child: Column(
                children: [
                  InkWell(
                    key: const ValueKey('profile-avatar-picker'),
                    onTap: _isLoading || !_canUploadProfilePhoto
                        ? null
                        : _pickAvatar,
                    customBorder: const CircleBorder(),
                    child: CircleAvatar(
                      radius: 42,
                      backgroundColor: _canUploadProfilePhoto
                          ? _panel
                          : _panel.withValues(alpha: 0.55),
                      backgroundImage: _avatarBytes == null
                          ? null
                          : MemoryImage(_avatarBytes!),
                      child: _avatarBytes == null
                          ? Icon(
                              _canUploadProfilePhoto
                                  ? Icons.add_a_photo_outlined
                                  : Icons.lock_outline,
                              color: _canUploadProfilePhoto ? _gold : _muted,
                              size: 28,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Foto de perfil',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                  if (!_canUploadProfilePhoto)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        'Confirma tu identidad por correo o teléfono para subir una foto.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _muted, fontSize: 10),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _fullNameController,
              enabled: !_isLoading,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              style: const TextStyle(color: _cream),
              decoration: inputDecoration.copyWith(
                labelText: 'Nombre y apellido',
                prefixIcon: const Icon(Icons.badge_outlined),
                helperText: 'Escribe tu nombre y al menos un apellido.',
              ),
              validator: _validateFullName,
              onChanged: _refreshSubmitButton,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _usernameController,
              enabled: !_isLoading,
              textCapitalization: TextCapitalization.none,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              autofillHints: const [AutofillHints.nickname],
              style: const TextStyle(color: _cream),
              decoration: inputDecoration.copyWith(
                labelText: 'Username',
                prefixIcon: const Icon(Icons.alternate_email),
                helperText: 'Debe ser único en toda la app.',
              ),
              validator: _validateUsername,
              onChanged: _refreshSubmitButton,
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: _isLoading ? null : _pickBirthDate,
              borderRadius: BorderRadius.circular(14),
              child: InputDecorator(
                decoration: inputDecoration.copyWith(
                  labelText: 'Fecha de nacimiento',
                  prefixIcon: const Icon(Icons.calendar_month_outlined),
                ),
                child: Text(
                  _birthDate == null
                      ? 'Selecciona tu fecha de nacimiento'
                      : _formatBirthDate(_birthDate!),
                  style: TextStyle(
                    color: _birthDate == null ? _muted : _cream,
                  ),
                ),
              ),
            ),
            if (_birthDate != null && !_isAdult)
              const Padding(
                padding: EdgeInsets.only(top: 6, left: 12),
                child: Text(
                  'Debes ser mayor de 18 años para unirte a la manada',
                  style: TextStyle(color: Color(0xFFFF8AB3), fontSize: 12),
                ),
              ),
            if (_birthDate == null)
              const Padding(
                padding: EdgeInsets.only(top: 6, left: 12),
                child: Text(
                  'Debes ser mayor de 18 años para unirte a la manada',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              ),
            CheckboxListTile(
              key: const ValueKey('register-birthday-marketing-consent'),
              contentPadding: EdgeInsets.zero,
              value: _birthdayMarketingConsent,
              activeColor: _gold,
              checkColor: const Color(0xFF171411),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (value) => setState(
                () => _birthdayMarketingConsent = value ?? false,
              ),
              title: const Text(
                'Quiero recibir una felicitación e invitación promocional por '
                'correo en mi cumpleaños. Es opcional y puedo retirar mi permiso.',
                style: TextStyle(color: _cream, fontSize: 11, height: 1.35),
              ),
            ),
            const SizedBox(height: 14),
          ],
          TextFormField(
            controller: _emailController,
            enabled: !_isLoading,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            style: const TextStyle(color: _cream),
            decoration: inputDecoration.copyWith(
              labelText: _isRegistering
                  ? 'Correo para recuperar tu cuenta'
                  : 'Correo electrónico',
              hintText: _isRegistering
                  ? 'Se usará solo para recuperar el acceso'
                  : 'correo@ejemplo.com',
              prefixIcon: const Icon(Icons.email_outlined),
            ),
            validator: (value) {
              final identifier = value?.trim() ?? '';
              if (!_hasEmailAddress(identifier)) {
                return 'Ingresa un correo válido.';
              }
              return null;
            },
            onChanged: _refreshSubmitButton,
          ),
          if (_isRegistering)
            const Padding(
              padding: EdgeInsets.only(top: 5, left: 12),
              child: Text(
                'No necesitas verificar el correo para entrar.',
                style: TextStyle(color: _muted, fontSize: 10),
              ),
            ),
          if (_isRegistering) ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: _phoneController,
              enabled: !_isLoading,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.telephoneNumber],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: const TextStyle(color: _cream),
              decoration: inputDecoration.copyWith(
                labelText: 'Teléfono celular',
                hintText: 'Escribe tu número',
                prefixIcon: CountryCodePicker(
                  initialSelection: 'BO',
                  favorite: const ['BO', 'AR', 'BR', 'CL', 'PE', 'US'],
                  showCountryOnly: false,
                  showOnlyCountryWhenClosed: false,
                  alignLeft: false,
                  padding: EdgeInsets.zero,
                  textStyle: const TextStyle(color: _cream),
                  dialogTextStyle: const TextStyle(color: _cream),
                  searchDecoration: const InputDecoration(
                    hintText: 'Buscar país',
                  ),
                  onChanged: (country) {
                    setState(() {
                      _phoneCountryCode = country.dialCode ?? '+591';
                      _phoneCountryIsoCode = country.code ?? 'BO';
                    });
                    _refreshSubmitButton(_phoneController.text);
                  },
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 112,
                  minHeight: 48,
                ),
              ),
              validator: (_) => _isPhoneNumberValid
                  ? null
                  : 'Ingresa un número válido con al menos 7 dígitos.',
              onChanged: _refreshSubmitButton,
            ),
          ],
          const SizedBox(height: 14),
          TextFormField(
            controller: _passwordController,
            enabled: !_isLoading,
            obscureText: !_passwordVisible,
            textInputAction: TextInputAction.next,
            autofillHints: [
              _isRegistering
                  ? AutofillHints.newPassword
                  : AutofillHints.password,
            ],
            style: const TextStyle(color: _cream),
            decoration: inputDecoration.copyWith(
              labelText: 'Contraseña',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: _passwordVisible
                    ? 'Ocultar contraseña'
                    : 'Mostrar contraseña',
                onPressed: _isLoading
                    ? null
                    : () => setState(
                          () => _passwordVisible = !_passwordVisible,
                        ),
                icon: Icon(
                  _passwordVisible ? Icons.visibility_off : Icons.visibility,
                  color: _muted,
                ),
              ),
            ),
            validator: (value) {
              final password = value ?? '';
              if (_isRegistering && password.length < 8) {
                return 'Usa al menos 8 caracteres.';
              }
              if (password.isEmpty) return 'Ingresa tu contraseña.';
              return null;
            },
            onChanged: _refreshSubmitButton,
          ),
          if (_isRegistering) ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirmPasswordController,
              enabled: !_isLoading,
              obscureText: !_passwordVisible,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              style: const TextStyle(color: _cream),
              decoration: inputDecoration.copyWith(
                labelText: 'Vuelve a escribir la contraseña',
                prefixIcon: const Icon(Icons.lock_reset_outlined),
              ),
              validator: (value) {
                if ((value ?? '').isEmpty) {
                  return 'Confirma tu contraseña.';
                }
                if (value != _passwordController.text) {
                  return 'Las contraseñas no coinciden.';
                }
                return null;
              },
              onChanged: _refreshSubmitButton,
            ),
          ],
          if (!_isRegistering)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isLoading ? null : _sendPasswordReset,
                child: const Text('¿Olvidaste tu contraseña?'),
              ),
            ),
          if (_isRegistering) ...[
            const SizedBox(height: 8),
            _securityNotice(),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _errorMessage!.startsWith('Verifica tu cuenta') ||
                        _errorMessage!.startsWith('Valida tu cuenta') ||
                        _errorMessage!.startsWith('Enviamos') ||
                        _errorMessage!
                            .startsWith('Tu correo ya está verificado') ||
                        _errorMessage!.startsWith('Coffee Wolves te envió') ||
                        _errorMessage!.startsWith('Tu correo aún no') ||
                        _errorMessage!.startsWith('Sesión cerrada')
                    ? const Color(0xFFB8C89A)
                    : const Color(0xFFFF8A80),
              ),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('auth-submit'),
            onPressed: !_canSubmit ? null : _submit,
            icon: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF171411),
                    ),
                  )
                : Icon(
                    _isRegistering ? Icons.person_add_alt_1 : Icons.login,
                  ),
            label: Text(
              _isRegistering ? 'Crear Cuenta' : 'Iniciar Sesión',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _canSubmit && _isPasswordLongEnoughForHighlight
                  ? _gold
                  : _gold.withValues(alpha: 0.38),
              elevation:
                  _isPasswordLongEnoughForHighlight && _canSubmit ? 6 : 0,
              shadowColor: _gold.withValues(alpha: 0.75),
              foregroundColor: const Color(0xFF171411),
              padding: const EdgeInsets.symmetric(vertical: 15),
              textStyle: const TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          if (_currentUser == null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () => _changeMode(
                        _isRegistering
                            ? ProfileAuthMode.signIn
                            : ProfileAuthMode.register,
                      ),
              child: Text(
                _isRegistering
                    ? '¿Ya tienes cuenta? Inicia sesión'
                    : '¿Nuevo en la manada? Crea una cuenta',
                textAlign: TextAlign.center,
              ),
            ),
          ],
          if (!_isRegistering) ...[
            const SizedBox(height: 4),
            OutlinedButton.icon(
              key: const ValueKey('sign-out-change-account'),
              onPressed: _isLoading ? null : _signOutAndClearAccount,
              icon: const Icon(Icons.logout, size: 17),
              label: const Text('CERRAR SESIÓN / CAMBIAR CUENTA'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold,
                side: BorderSide(color: _gold.withValues(alpha: 0.45)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _securityNotice() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF241D19),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _gold.withValues(alpha: 0.25)),
      ),
      child: const Text(
        '⚠️ Seguridad Wolves: No compartas datos personales, financieros o contraseñas con otros usuarios. Coffee Wolves no se hace responsable por interacciones fuera de nuestros locales oficiales. ¡Cuida a tu manada!',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _muted,
          fontSize: 11,
          height: 1.4,
        ),
      ),
    );
  }
}
