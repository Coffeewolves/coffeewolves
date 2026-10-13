import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'coffee_pup_game_screen.dart';
import 'coffee_pup_game_service.dart';
import 'garra_icon.dart';
import 'mischief_wall_screen.dart';
import 'wolves_match_service.dart';

class WolvesMatchScreen extends StatefulWidget {
  const WolvesMatchScreen({
    super.key,
    required this.onClose,
    this.onCompleteProfile,
  });

  final VoidCallback onClose;
  final VoidCallback? onCompleteProfile;

  @override
  State<WolvesMatchScreen> createState() => _WolvesMatchScreenState();
}

class _WolvesMatchScreenState extends State<WolvesMatchScreen>
    with SingleTickerProviderStateMixin {
  static const _background = Color(0xFF080A0B);
  static const _card = Color(0xFF111619);
  static const _gold = Color(0xFFC6A574);
  static const _cream = Color(0xFFF2E8D8);
  static const _muted = Color(0xFFADB3B8);
  static const _interestOptions = [
    'Café de especialidad',
    'Eventos',
    'Música',
    'Lectura',
    'Naturaleza',
    'Mascotas',
    'Arte',
    'Viajes',
    'Conversaciones',
    'Deportes',
  ];

  final WolvesMatchService _service = WolvesMatchService();
  final CoffeePupGameService _coffeePupGameService = CoffeePupGameService();
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  Map<String, dynamic>? _state;
  bool _loading = true;
  bool _saving = false;
  bool _leaving = false;
  bool _openingWall = false;
  bool _openingIcebreaker = false;
  String? _startingCoffeePupGame;
  bool _editing = false;
  bool _consent = false;
  bool _radarRunning = true;
  late final AnimationController _radarController;
  String? _error;
  String _intention = 'friendship';
  final Set<String> _interests = {};

  @override
  void initState() {
    super.initState();
    _radarController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
    _loadState();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    _radarController.dispose();
    super.dispose();
  }

  Future<void> _loadState() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final state = await _service.getState();
      if (!mounted) return;
      setState(() {
        _state = state;
        _loading = false;
        _displayNameController.text =
            (state['displayName'] as String?)?.trim().isNotEmpty == true
                ? state['displayName'] as String
                : FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
        _bioController.text = state['bio'] as String? ?? '';
        _intention = state['intention'] as String? ?? 'friendship';
        _interests
          ..clear()
          ..addAll(
            (state['interests'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .where(_interestOptions.contains),
          );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _messageFor(error);
      });
    }
  }

  Future<void> _toggleRadar() async {
    final shouldStart = !_radarRunning;
    setState(() => _radarRunning = shouldStart);
    if (!shouldStart) {
      _radarController.stop();
      _showMessage('Radar pausado. No se comparte ni consulta tu ubicación.');
      return;
    }
    _radarController.repeat();
    try {
      final state = await _service.getState();
      if (!mounted) return;
      setState(() => _state = state);
      _showMessage('Radar actualizado con perfiles compatibles.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _radarRunning = false);
      _radarController.stop();
      setState(() => _error = _messageFor(error));
    }
  }

  String _messageFor(Object error) {
    final message = error.toString();
    if (message.startsWith('Bad state: ')) {
      return message.substring('Bad state: '.length);
    }
    if (message.startsWith('Invalid argument(s): ')) {
      return message.substring('Invalid argument(s): '.length);
    }
    return 'No se pudo completar la acción de WOLVES MATCH. '
        'Revisa tu conexión y las reglas de Firestore e inténtalo de nuevo. '
        '$message';
  }

  String get _status => _state?['status'] as String? ?? 'inactive';

  List<Map<String, dynamic>> _profiles(String key) {
    final value = _state?[key];
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((profile) => Map<String, dynamic>.from(profile))
        .toList();
  }

  void _beginSetup() {
    setState(() {
      _editing = true;
      _consent = false;
      _error = null;
    });
  }

  Future<void> _saveProfile({required String status}) async {
    if (status == 'active' && !_consent) {
      setState(() =>
          _error = 'Confirma tu consentimiento para activar tu participación.');
      return;
    }
    if (_displayNameController.text.trim().length < 2) {
      setState(() => _error = 'Escribe el nombre que quieres mostrar.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _service.saveProfile(
        status: status,
        displayName: _displayNameController.text.trim(),
        bio: _bioController.text.trim(),
        intention: _intention,
        interests: _interests.toList(),
        consent: _consent,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _editing = false;
      });
      _showMessage(
        status == 'active'
            ? 'Tu aullido está activo. Puedes pausar o salir cuando quieras.'
            : 'Tu perfil quedó guardado como borrador; aún no es visible.',
      );
      await _loadState();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _messageFor(error);
      });
    }
  }

  Future<void> _setParticipation(String status) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (status == 'active') {
        _consent = true;
      }
      await _service.saveProfile(
        status: status,
        displayName: _displayNameController.text.trim(),
        bio: _bioController.text.trim(),
        intention: _intention,
        interests: _interests.toList(),
        consent: status == 'active',
      );
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage(
        status == 'paused'
            ? 'Tu participación está pausada y ya no aparecerás en recomendaciones.'
            : status == 'left'
                ? 'Saliste de WOLVES MATCH. Tu perfil de WOLVES CLUB permanece intacto.'
                : 'Volviste a la manada.',
      );
      await _loadState();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _messageFor(error);
      });
    }
  }

  Future<void> _confirmParticipationChange(String status) async {
    final leaving = status == 'left';
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: _card,
            title: Text(
              leaving ? 'Abandonar WOLVES MATCH' : 'Pausar tu aullido',
              style: const TextStyle(color: _cream),
            ),
            content: Text(
              leaving
                  ? 'Tu perfil general de WOLVES CLUB seguirá intacto. '
                      '¿Quieres salir de Match?'
                  : 'Dejarás de aparecer en recomendaciones mientras esté pausado. '
                      '¿Continuar?',
              style: const TextStyle(color: _muted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('CANCELAR'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(
                  leaving ? 'SALIR' : 'PAUSAR',
                  style: const TextStyle(color: _gold),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) await _setParticipation(status);
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage(successMessage);
      await _loadState();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _messageFor(error);
      });
    }
  }

  Future<void> _reportProfile(Map<String, dynamic> profile) async {
    var reason = 'inappropriate';
    final detailsController = TextEditingController();
    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: _card,
            title: const Text(
              'Reportar perfil',
              style: TextStyle(color: _cream),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: reason,
                  dropdownColor: _card,
                  decoration: const InputDecoration(labelText: 'Motivo'),
                  items: const [
                    DropdownMenuItem(
                      value: 'inappropriate',
                      child: Text('Contenido inapropiado'),
                    ),
                    DropdownMenuItem(
                      value: 'fake',
                      child: Text('Perfil falso'),
                    ),
                    DropdownMenuItem(
                      value: 'harassment',
                      child: Text('Acoso o conducta'),
                    ),
                    DropdownMenuItem(value: 'other', child: Text('Otro')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => reason = value);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: detailsController,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Detalles (opcional)',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('CANCELAR'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('ENVIAR REPORTE'),
              ),
            ],
          ),
        ),
      );
      if (result != true || !mounted) return;
      await _runAction(
        () => _service.reportProfile(
          profileId: profile['id'] as String,
          reason: reason,
          details: detailsController.text.trim(),
        ),
        successMessage: 'Reporte enviado de forma privada.',
      );
    } finally {
      detailsController.dispose();
    }
  }

  void _closeMatch() {
    if (_leaving) return;
    _leaving = true;
    widget.onClose();
  }

  Future<void> _openMischiefWall() async {
    if (_openingWall) return;
    _openingWall = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MischiefWallScreen(
            onClose: () => Navigator.of(context).pop(),
          ),
        ),
      );
    } finally {
      if (mounted) _openingWall = false;
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _openingWall ? null : _openMischiefWall,
            icon: const WolvesIcon(icon: BrandIcons.garra, size: 18),
            label: const Text('EL MURO DE LAS TRAVESURAS'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _gold,
              side: const BorderSide(color: _gold),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading || _saving)
            const Padding(
              padding: EdgeInsets.all(22),
              child: Center(child: CircularProgressIndicator(color: _gold)),
            )
          else if (_editing)
            _setupForm()
          else if (_error != null)
            _errorCard()
          else
            _matchHub(),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        IconButton(
          key: const ValueKey('wolves-match-back'),
          onPressed: _leaving ? null : _closeMatch,
          tooltip: 'Volver',
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          color: _gold,
        ),
        const Expanded(
          child: Column(
            children: [
              Text(
                'WOLVES MATCH',
                style: TextStyle(
                  color: _cream,
                  fontSize: 15,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'UN AULLIDO, UNA CONEXIÓN',
                style: TextStyle(
                  color: _gold,
                  fontSize: 9,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: _loading || _saving ? null : _loadState,
          tooltip: 'Actualizar',
          icon: const Icon(Icons.refresh, size: 19),
          color: _muted,
        ),
      ],
    );
  }

  Widget _errorCard() {
    final needsProfile = _error?.contains('Completa tu perfil') == true;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF5A4934)),
      ),
      child: Column(
        children: [
          const Icon(Icons.nightlight_outlined, color: _gold, size: 30),
          const SizedBox(height: 10),
          const Text(
            'NO SE PUDO ABRIR WOLVES MATCH',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _gold,
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _cream, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (needsProfile && widget.onCompleteProfile != null)
            FilledButton(
              onPressed: () => widget.onCompleteProfile?.call(),
              child: const Text('COMPLETAR PERFIL'),
            ),
          OutlinedButton(
            onPressed: _loading ? null : _loadState,
            child: const Text('INTENTAR DE NUEVO'),
          ),
        ],
      ),
    );
  }

  Widget _matchHub() {
    switch (_status) {
      case 'active':
        return _activeHub();
      case 'paused':
        return _pausedHub();
      default:
        return _inactiveHub();
    }
  }

  Widget _inactiveHub() {
    final configuring = _status == 'configuring';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _moonCard(
          icon: Icons.nightlight_round,
          title: 'La manada te espera',
          body: configuring
              ? 'Tu perfil sigue siendo privado. Completa la configuración y '
                  'activa tu participación solo cuando estés listo/a.'
              : 'Conoce miembros que comparten tus intereses. Tu perfil público '
                  'de Coffee Wolves no te inscribe automáticamente.',
        ),
        const SizedBox(height: 16),
        _stateButton(
          configuring ? 'PREPARA TU AULLIDO' : 'LANZA TU AULLIDO',
          configuring ? Icons.auto_awesome_outlined : BrandIcons.garra,
          _beginSetup,
        ),
        const SizedBox(height: 8),
        const Text(
          'Quiero conocer a otros miembros',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(height: 18),
        _privacyNote(),
      ],
    );
  }

  Widget _pausedHub() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _moonCard(
          icon: Icons.pause_circle_outline,
          title: 'Tu aullido está en pausa',
          body: 'No apareces en nuevas recomendaciones. Tu perfil de WOLVES '
              'CLUB y tus datos de Match se conservan.',
        ),
        const SizedBox(height: 16),
        _stateButton(
          'VOLVER A LA MANADA',
          BrandIcons.garra,
          () => _setParticipation('active'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _saving ? null : _beginSetup,
          child: const Text('EDITAR MI PERFIL DE MATCH'),
        ),
        TextButton(
          onPressed: _saving ? null : () => _confirmParticipationChange('left'),
          child: const Text(
            'Abandonar WOLVES MATCH',
            style: TextStyle(color: _muted),
          ),
        ),
        _privacyNote(),
      ],
    );
  }

  Widget _activeHub() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stateButton(
          'MI AULLIDO ESTÁ ACTIVO',
          Icons.graphic_eq,
          _beginSetup,
        ),
        const SizedBox(height: 6),
        Text(
          'Intención: ${_intentionLabel(_state?['intention'] as String?)}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(height: 14),
        _radarPanel(),
        const SizedBox(height: 12),
        _sectionTitle('NUEVAS SEÑALES', Icons.auto_awesome_outlined),
        if (_profiles('recommendations').isEmpty)
          _emptyState('Aún no hay perfiles compatibles. Vuelve más tarde.')
        else
          ..._profiles('recommendations').map(_recommendationCard),
        if (_profiles('incoming').isNotEmpty) ...[
          _sectionTitle('AULLIDOS RECIBIDOS', Icons.mark_chat_unread_outlined),
          ..._profiles('incoming').map(_incomingCard),
        ],
        if (_profiles('outgoing').isNotEmpty) ...[
          _sectionTitle('INTERÉS ENVIADO', Icons.schedule_outlined),
          ..._profiles('outgoing').map(_outgoingCard),
        ],
        _dynamicsSection(),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed:
              _saving ? null : () => _confirmParticipationChange('paused'),
          icon: const Icon(Icons.pause_circle_outline, size: 18),
          label: const Text('PAUSAR MI PARTICIPACIÓN'),
        ),
        TextButton(
          onPressed: _saving ? null : () => _confirmParticipationChange('left'),
          child: const Text(
            'Abandonar WOLVES MATCH',
            style: TextStyle(color: _muted),
          ),
        ),
        _privacyNote(),
      ],
    );
  }

  Widget _radarPanel() {
    final recommendations = _profiles('recommendations');
    final currentUser = FirebaseAuth.instance.currentUser;
    final photoUrl = currentUser?.photoURL;
    final displayName = _state?['displayName'] as String? ?? 'Lobo';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF5A4934)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _radarRunning ? Icons.radar : Icons.pause_circle_outline,
                color: _gold,
                size: 18,
              ),
              const SizedBox(width: 7),
              Text(
                _radarRunning
                    ? 'BUSCANDO PERFILES COMPATIBLES'
                    : 'RADAR EN PAUSA',
                style: const TextStyle(
                  color: _gold,
                  fontSize: 10,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 280,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size =
                    constraints.maxWidth < 280 ? constraints.maxWidth : 280.0;
                final nodeLocations = <Offset>[
                  Offset(size * 0.19, size * 0.35),
                  Offset(size * 0.78, size * 0.27),
                  Offset(size * 0.22, size * 0.73),
                  Offset(size * 0.79, size * 0.68),
                  Offset(size * 0.51, size * 0.12),
                ];
                return Center(
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: AnimatedBuilder(
                      animation: _radarController,
                      builder: (context, _) {
                        final progress =
                            _radarRunning ? _radarController.value : 0.0;
                        return Stack(
                          alignment: Alignment.center,
                          children: [
                            for (var index = 0; index < 3; index++)
                              if (_radarRunning)
                                _pulseRing(progress, index, size),
                            Container(
                              width: size * 0.77,
                              height: size * 0.77,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _gold.withValues(alpha: 0.12),
                                ),
                              ),
                            ),
                            Container(
                              width: size * 0.51,
                              height: size * 0.51,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _gold.withValues(alpha: 0.18),
                                ),
                              ),
                            ),
                            for (var index = 0;
                                index < recommendations.length &&
                                    index < nodeLocations.length;
                                index++)
                              Positioned(
                                left: nodeLocations[index].dx - 20,
                                top: nodeLocations[index].dy - 20,
                                child: _radarMember(
                                  recommendations[index],
                                  progress,
                                  index,
                                ),
                              ),
                            Container(
                              width: 78,
                              height: 78,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _background,
                                border: Border.all(color: _gold, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: _gold.withValues(
                                      alpha: _radarRunning ? 0.27 : 0.08,
                                    ),
                                    blurRadius: _radarRunning ? 22 : 8,
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: photoUrl != null && photoUrl.isNotEmpty
                                    ? Image.network(
                                        photoUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stack) =>
                                            _currentUserPlaceholder(
                                                displayName),
                                      )
                                    : _currentUserPlaceholder(displayName),
                              ),
                            ),
                            if (recommendations.isEmpty)
                              Positioned(
                                bottom: size * 0.08,
                                child: Text(
                                  _radarRunning
                                      ? 'Esperando miembros activos compatibles'
                                      : 'Activa el radar cuando quieras',
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                            Positioned(
                              top: size * 0.04,
                              left: size * 0.43,
                              child: const Icon(
                                Icons.star_outline,
                                color: _gold,
                                size: 12,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Descubrimiento por intención e intereses. No usa ni muestra ubicación.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 10),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _saving ? null : _toggleRadar,
              icon: Icon(
                _radarRunning ? Icons.pause : Icons.play_arrow,
                size: 18,
              ),
              label: Text(_radarRunning ? 'DETENER RADAR' : 'INICIAR RADAR'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold,
                side: const BorderSide(color: _gold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pulseRing(double progress, int index, double size) {
    final phase = (progress + index / 3) % 1;
    final diameter = size * (0.22 + phase * 0.76);
    return IgnorePointer(
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _gold.withValues(alpha: (1 - phase) * 0.52),
            width: 1.2,
          ),
        ),
      ),
    );
  }

  Widget _radarMember(
    Map<String, dynamic> profile,
    double progress,
    int index,
  ) {
    final name = profile['displayName'] as String? ?? '';
    final initial = name.trim().isEmpty ? '•' : name.trim()[0].toUpperCase();
    final phase = (progress + index / 5) % 1;
    final drift = _radarRunning ? math.sin(phase * math.pi * 2) * 3 : 0.0;
    final opacity =
        _radarRunning ? 0.2 + math.sin(phase * math.pi).abs() * 0.8 : 0.42;
    return Transform.translate(
      offset: Offset(0, drift),
      child: AnimatedOpacity(
        opacity: opacity,
        duration: const Duration(milliseconds: 250),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF242019),
            shape: BoxShape.circle,
            border: Border.all(color: _gold.withValues(alpha: 0.8)),
            boxShadow: [
              BoxShadow(
                color: _gold.withValues(alpha: 0.16),
                blurRadius: 8,
              ),
            ],
          ),
          child: Text(
            initial,
            style: const TextStyle(
              color: _cream,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _currentUserPlaceholder(String name) {
    final initial = name.trim().isEmpty ? '🐺' : name.trim()[0].toUpperCase();
    return ColoredBox(
      color: const Color(0xFF241F18),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: _gold,
            fontSize: 26,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _setupForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _moonCard(
          icon: BrandIcons.garra,
          title: 'Prepara tu aullido',
          body: 'Elige cómo te gustaría conectar. Nada se mostrará en Match '
              'hasta que marques tu consentimiento y actives el perfil.',
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _displayNameController,
          maxLength: 40,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nombre visible en Match',
            prefixIcon: Icon(Icons.person_outline),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _bioController,
          maxLength: 180,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Presentación (sin contacto ni ubicación exacta)',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '¿QUÉ TIPO DE CONEXIÓN BUSCAS?',
          style: TextStyle(color: _gold, fontSize: 10, letterSpacing: 1.4),
        ),
        const SizedBox(height: 8),
        _intentionOption(
          'friendship',
          'Amistad',
          'Quiero ampliar mi círculo social.',
          Icons.groups_outlined,
        ),
        _intentionOption(
          'romantic',
          'Conexión romántica',
          'Estoy abierto/a a conocer a alguien especial.',
          Icons.nightlight_outlined,
        ),
        _intentionOption(
          'both',
          'Ambas',
          'Quiero conocer personas sin limitar el tipo de conexión.',
          Icons.auto_awesome_outlined,
        ),
        const SizedBox(height: 10),
        const Text(
          'INTERESES · HASTA CINCO',
          style: TextStyle(color: _gold, fontSize: 10, letterSpacing: 1.4),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 5,
          children: [
            for (final interest in _interestOptions)
              FilterChip(
                label: Text(interest),
                selected: _interests.contains(interest),
                onSelected: (selected) {
                  setState(() {
                    if (selected && _interests.length < 5) {
                      _interests.add(interest);
                    } else {
                      _interests.remove(interest);
                    }
                  });
                },
                selectedColor: _gold.withValues(alpha: 0.22),
                checkmarkColor: _gold,
                labelStyle: TextStyle(
                  color: _interests.contains(interest) ? _cream : _muted,
                  fontSize: 11,
                ),
                side: BorderSide(
                  color: _interests.contains(interest)
                      ? _gold
                      : const Color(0xFF39342F),
                ),
                backgroundColor: _card,
              ),
          ],
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _consent,
          onChanged: (value) => setState(() => _consent = value ?? false),
          activeColor: _gold,
          checkColor: _background,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'Acepto aparecer en recomendaciones de WOLVES MATCH y entiendo '
            'que solo se mostrará la información de este perfil.',
            style: TextStyle(color: _cream, fontSize: 12, height: 1.35),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Color(0xFFFF8A80))),
        ],
        const SizedBox(height: 8),
        _stateButton(
          'ACTIVAR MI AULLIDO',
          Icons.graphic_eq,
          () => _saveProfile(status: 'active'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _saving ? null : () => _saveProfile(status: 'configuring'),
          child: const Text('GUARDAR COMO BORRADOR'),
        ),
        TextButton(
          onPressed: _saving
              ? null
              : () => setState(() {
                    _editing = false;
                    _error = null;
                  }),
          child: const Text('CANCELAR'),
        ),
        _privacyNote(),
      ],
    );
  }

  Widget _intentionOption(
    String value,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final selected = _intention == value;
    return Card(
      color: selected ? const Color(0xFF201C17) : _card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? _gold : const Color(0xFF39342F)),
      ),
      child: RadioListTile<String>(
        value: value,
        groupValue: _intention,
        onChanged: (next) {
          if (next != null) setState(() => _intention = next);
        },
        activeColor: _gold,
        title: Row(
          children: [
            WolvesIcon(icon: icon, color: _gold, size: 18),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: _cream, fontSize: 13),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(left: 27),
          child: Text(
            subtitle,
            style: const TextStyle(color: _muted, fontSize: 11),
          ),
        ),
      ),
    );
  }

  Widget _recommendationCard(Map<String, dynamic> profile) {
    final id = profile['id'] as String? ?? '';
    return _profileCard(
      profile,
      statusLabel: _intentionLabel(profile['intention'] as String?),
      actions: Row(
        children: [
          IconButton(
            tooltip: 'Pasar sin notificar',
            onPressed: _saving
                ? null
                : () => _runAction(
                      () => _service.dismissProfile(id),
                      successMessage: 'Perfil descartado de forma privada.',
                    ),
            icon: const Icon(Icons.close),
            color: _muted,
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _saving
                ? null
                : () => _runAction(
                      () async {
                        await _service.sendInterest(id);
                      },
                      successMessage:
                          'Interés procesado en privado. Revisa tus conexiones '
                          'para ver si el aullido fue mutuo.',
                    ),
            style: FilledButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: _background,
            ),
            icon: const Icon(Icons.graphic_eq, size: 17),
            label: const Text('MOSTRAR INTERÉS'),
          ),
        ],
      ),
    );
  }

  Widget _incomingCard(Map<String, dynamic> profile) {
    final id = profile['id'] as String? ?? '';
    return _profileCard(
      profile,
      statusLabel: 'Interés recibido',
      actions: Row(
        children: [
          TextButton(
            onPressed: _saving
                ? null
                : () => _runAction(
                      () => _service.respondToInterest(
                        profileId: id,
                        accept: false,
                      ),
                      successMessage: 'Interés descartado en privado.',
                    ),
            child: const Text('PASAR EN SILENCIO'),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _saving
                ? null
                : () => _runAction(
                      () => _service.respondToInterest(
                        profileId: id,
                        accept: true,
                      ),
                      successMessage: '¡Conexión mutua confirmada!',
                    ),
            style: FilledButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: _background,
            ),
            icon: const Icon(Icons.brightness_3_outlined, size: 17),
            label: const Text('CONECTAR'),
          ),
        ],
      ),
    );
  }

  Widget _outgoingCard(Map<String, dynamic> profile) => _profileCard(
        profile,
        statusLabel: 'Interés enviado · esperando respuesta',
      );

  Widget _dynamicsSection() {
    final connections = _profiles('connections');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('ROMPEHIELOS Y JUEGOS', Icons.sports_esports_outlined),
        if (connections.isEmpty) ...[
          const SizedBox(height: 8),
          _emptyState(
            'Las dinámicas en pareja se habilitan cuando tú y otro miembro '
            'aceptan el interés. Mientras tanto, puedes explorar los '
            'rompehielos.',
          ),
          _lockedDynamicsCard(
            icon: Icons.coffee_outlined,
            title: 'TRIVIA · CAFÉ Y PERRITOS',
            description:
                'Rondas por turnos con preguntas para poner a prueba sus gustos.',
          ),
          _lockedDynamicsCard(
            icon: Icons.favorite_outline,
            title: '¿QUÉ PREFIEREN?',
            description:
                'Cinco dilemas para comparar preferencias con tu conexión.',
          ),
          _icebreakerPreviewCard(),
        ] else ...[
          ...connections.map(_connectionCard),
        ],
      ],
    );
  }

  Widget _lockedDynamicsCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFF5A4934)),
      ),
      child: Row(
        children: [
          WolvesIcon(icon: icon, color: _gold),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _cream,
                    fontSize: 11,
                    letterSpacing: 0.7,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Se desbloquea con una conexión mutua',
                  style: TextStyle(color: _gold, fontSize: 10),
                ),
              ],
            ),
          ),
          const Icon(Icons.lock_outline, color: _muted, size: 17),
        ],
      ),
    );
  }

  Widget _icebreakerPreviewCard() {
    return Container(
      margin: const EdgeInsets.only(top: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFF5A4934)),
      ),
      child: Row(
        children: [
          const Icon(Icons.quiz_outlined, color: _gold),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PREGUNTAS ROMPEHIELOS',
                  style: TextStyle(
                    color: _cream,
                    fontSize: 11,
                    letterSpacing: 0.7,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Explora las preguntas y comparte una para iniciar una charla.',
                  style: TextStyle(color: _muted, fontSize: 11, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: const ValueKey('match-preview-icebreakers'),
            onPressed: _previewIcebreakers,
            child: const Text('VER'),
          ),
        ],
      ),
    );
  }

  Future<void> _previewIcebreakers() async {
    var questionIndex = 0;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final question =
              WolvesMatchService.icebreakerQuestions[questionIndex];
          return AlertDialog(
            backgroundColor: _card,
            title: const Text(
              'PREGUNTA ROMPEHIELOS',
              textAlign: TextAlign.center,
              style: TextStyle(color: _gold, letterSpacing: 1),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'PREGUNTA ${questionIndex + 1} DE '
                  '${WolvesMatchService.icebreakerQuestions.length}',
                  style: const TextStyle(color: _muted, fontSize: 10),
                ),
                const SizedBox(height: 12),
                Text(
                  question.prompt,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _cream,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                for (final option in question.options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(
                      option,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _muted, fontSize: 12),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: questionIndex == 0
                    ? null
                    : () => setDialogState(() => questionIndex--),
                child: const Text('ANTERIOR'),
              ),
              TextButton(
                onPressed: questionIndex ==
                        WolvesMatchService.icebreakerQuestions.length - 1
                    ? null
                    : () => setDialogState(() => questionIndex++),
                child: const Text('SIGUIENTE'),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: question.prompt),
                  );
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('Pregunta copiada.')),
                    );
                  }
                },
                icon: const Icon(Icons.copy_outlined, size: 16),
                label: const Text('COPIAR'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('CERRAR'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _connectionCard(Map<String, dynamic> profile) => _profileCard(
        profile,
        statusLabel: 'Conexión mutua',
        actions: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: _startingCoffeePupGame != null
                  ? null
                  : () => _startCoffeePupGame(profile, 'trivia'),
              icon: const Icon(Icons.coffee_outlined, size: 18),
              label: Text(
                _startingCoffeePupGame == 'trivia'
                    ? 'INICIANDO TRIVIA…'
                    : 'JUGAR TRIVIA · CAFÉ Y PERRITOS',
              ),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _startingCoffeePupGame != null
                  ? null
                  : () => _startCoffeePupGame(profile, 'preferences'),
              icon: const Icon(Icons.favorite_outline, size: 18),
              label: Text(
                _startingCoffeePupGame == 'preferences'
                    ? 'INICIANDO JUEGO…'
                    : 'JUGAR ¿QUÉ PREFIEREN?',
              ),
            ),
            const SizedBox(height: 6),
            FilledButton.icon(
              onPressed: _saving || _openingIcebreaker
                  ? null
                  : () => _openIcebreaker(profile),
              icon: const Icon(Icons.quiz_outlined, size: 18),
              label: Text(
                _openingIcebreaker
                    ? 'ABRIENDO JUEGO…'
                    : 'ROMPEHIELO · RESPUESTAS SECRETAS',
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Trivia por turnos, cinco dilemas para comparar gustos y '
              'preguntas secretas para conocerse mejor.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ),
      );

  Future<void> _startCoffeePupGame(
    Map<String, dynamic> profile,
    String gameType,
  ) async {
    final peerPublicId = profile['id'] as String?;
    if (peerPublicId == null || peerPublicId.isEmpty) {
      _showMessage('No se pudo identificar esta conexión.');
      return;
    }
    setState(() => _startingCoffeePupGame = gameType);
    try {
      final sessionId = await _coffeePupGameService.startGame(
        profileId: peerPublicId,
        gameType: gameType,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => CoffeePupGameScreen(sessionId: sessionId),
        ),
      );
    } on FirebaseFunctionsException catch (error, stackTrace) {
      debugPrint('No se pudo iniciar el juego Coffee Pup (${error.code}).');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        _showMessage(
          error.message ?? 'No se pudo iniciar el juego. Inténtalo de nuevo.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('No se pudo iniciar el juego Coffee Pup: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) _showMessage('No se pudo iniciar el juego.');
    } finally {
      if (mounted) setState(() => _startingCoffeePupGame = null);
    }
  }

  Future<void> _openIcebreaker(Map<String, dynamic> profile) async {
    final peerPublicId = profile['id'] as String?;
    if (peerPublicId == null || peerPublicId.isEmpty) {
      _showMessage('No se pudo identificar esta conexión.');
      return;
    }
    setState(() => _openingIcebreaker = true);
    try {
      final gameContext = await _service.getIcebreakerContext(peerPublicId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => _MatchIcebreakerDialog(
          service: _service,
          gameContext: gameContext,
          peerName: profile['displayName'] as String? ?? 'Tu conexión',
        ),
      );
    } catch (error) {
      if (mounted) _showMessage(_messageFor(error));
    } finally {
      if (mounted) setState(() => _openingIcebreaker = false);
    }
  }

  Widget _profileCard(
    Map<String, dynamic> profile, {
    required String statusLabel,
    Widget? actions,
  }) {
    final name = profile['displayName'] as String? ?? 'Miembro de la manada';
    final bio = profile['bio'] as String? ?? '';
    final interests = (profile['interests'] as List<dynamic>? ?? const [])
        .whereType<String>();
    final coffeePupRank = profile['coffeePupRank'] as String?;
    final coffeePupAchievements =
        (profile['coffeePupAchievements'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF5A4934)),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _background,
                  border: Border.all(color: _gold.withValues(alpha: 0.7)),
                ),
                child: const WolvesIcon(
                  icon: BrandIcons.garra,
                  color: _gold,
                  size: 22,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: _cream,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      statusLabel,
                      style: const TextStyle(color: _gold, fontSize: 10),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Opciones de seguridad',
                color: _card,
                icon: const Icon(Icons.more_vert, color: _muted, size: 19),
                onSelected: (choice) {
                  if (choice == 'block') {
                    unawaited(
                      _runAction(
                        () => _service.blockProfile(profile['id'] as String),
                        successMessage:
                            'Perfil bloqueado; no volverá a aparecerte.',
                      ),
                    );
                  } else if (choice == 'report') {
                    unawaited(_reportProfile(profile));
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'block',
                    child: Text(
                      'Bloquear',
                      style: TextStyle(color: _cream),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'report',
                    child: Text(
                      'Reportar',
                      style: TextStyle(color: _cream),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 11),
            Text(
              bio,
              style: const TextStyle(
                color: _cream,
                height: 1.4,
                fontSize: 12,
              ),
            ),
          ],
          if (coffeePupRank != null) ...[
            const SizedBox(height: 11),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _gold.withValues(alpha: 0.6)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.workspace_premium, color: _gold, size: 19),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'Rango de barista · $coffeePupRank',
                      style: const TextStyle(
                        color: _cream,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final icon in _achievementIcons(coffeePupAchievements))
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: WolvesIcon(icon: icon, color: _gold, size: 17),
                    ),
                ],
              ),
            ),
          ],
          if (interests.isNotEmpty) ...[
            const SizedBox(height: 11),
            Wrap(
              spacing: 6,
              runSpacing: 5,
              children: interests.map(_interestTag).toList(),
            ),
          ],
          if (actions != null) ...[
            const SizedBox(height: 10),
            actions,
          ],
        ],
      ),
    );
  }

  List<IconData> _achievementIcons(List<String> achievementIds) {
    const icons = {
      'first_brew': Icons.coffee,
      'coffee_scholar': Icons.workspace_premium,
      'pup_expert': BrandIcons.garra,
      'five_streak': Icons.local_fire_department,
      'match_minds': Icons.favorite,
      'streak_saver': Icons.shield,
    };
    return achievementIds
        .map((achievementId) => icons[achievementId])
        .whereType<IconData>()
        .take(3)
        .toList();
  }

  Widget _interestTag(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: _background,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF39342F)),
        ),
        child: Text(label, style: const TextStyle(color: _muted, fontSize: 10)),
      );

  Widget _stateButton(String label, IconData icon, VoidCallback onPressed) {
    return SizedBox(
      height: 54,
      child: ElevatedButton.icon(
        onPressed: _saving ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _background,
          foregroundColor: _gold,
          side: const BorderSide(color: _gold, width: 1.2),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontSize: 12,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
          ),
        ),
        icon: WolvesIcon(icon: icon, size: 20),
        label: Text(label),
      ),
    );
  }

  Widget _moonCard({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF5A4934)),
        gradient: const LinearGradient(
          colors: [_card, Color(0xFF191710)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          WolvesIcon(icon: icon, color: _gold, size: 30),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _cream,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(top: 19, bottom: 3),
        child: Row(
          children: [
            WolvesIcon(icon: icon, size: 16, color: _gold),
            const SizedBox(width: 7),
            Text(
              title,
              style: const TextStyle(
                color: _gold,
                fontSize: 10,
                letterSpacing: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _emptyState(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
      );

  Widget _privacyNote() => Padding(
        padding: const EdgeInsets.only(top: 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.lock_outline, color: _gold, size: 16),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Nunca mostramos tu correo, teléfono ni ubicación exacta. '
                'Pasar, pausar y abandonar son acciones privadas.',
                style: TextStyle(color: _muted, fontSize: 10, height: 1.4),
              ),
            ),
          ],
        ),
      );

  String _intentionLabel(String? value) {
    switch (value) {
      case 'friendship':
        return 'Amistad';
      case 'romantic':
        return 'Conexión romántica';
      case 'both':
        return 'Amistad y conexión romántica';
      default:
        return 'Sin definir';
    }
  }
}

class _MatchIcebreakerDialog extends StatefulWidget {
  const _MatchIcebreakerDialog({
    required this.service,
    required this.gameContext,
    required this.peerName,
  });

  final WolvesMatchService service;
  final MatchIcebreakerContext gameContext;
  final String peerName;

  @override
  State<_MatchIcebreakerDialog> createState() => _MatchIcebreakerDialogState();
}

class _MatchIcebreakerDialogState extends State<_MatchIcebreakerDialog> {
  int _questionIndex = 0;
  bool _submitting = false;
  String? _error;

  MatchIcebreakerQuestion get _question =>
      WolvesMatchService.icebreakerQuestions[_questionIndex];

  Future<void> _submitAnswer(int answerIndex) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.service.submitIcebreakerAnswer(
        context: widget.gameContext,
        questionId: _question.id,
        answerIndex: answerIndex,
      );
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('No se pudo guardar la respuesta rompehielos: ${error.code}');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _error = error.code == 'permission-denied'
              ? 'La conexión ya no está disponible para jugar.'
              : 'No se pudo guardar tu respuesta. Inténtalo de nuevo.';
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Error al guardar la respuesta rompehielos: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() => _error = 'No se pudo guardar tu respuesta.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownAnswer = widget.service.watchIcebreakerAnswer(
      context: widget.gameContext,
      questionId: _question.id,
      publicId: widget.gameContext.ownPublicId,
    );
    return AlertDialog(
      backgroundColor: const Color(0xFF111619),
      title: const Text(
        'ROMPEHIELO',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFFC6A574), letterSpacing: 1.4),
      ),
      content: SizedBox(
        width: 420,
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          key: ValueKey('own-${_question.id}'),
          stream: ownAnswer,
          builder: (context, ownSnapshot) {
            if (ownSnapshot.hasError) {
              return const Text(
                'No se pudo cargar esta pregunta.',
                style: TextStyle(color: Color(0xFFFF8A80)),
              );
            }
            if (!ownSnapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFFC6A574)),
              );
            }
            final ownData = ownSnapshot.data!.data();
            final ownIndex = ownData?['answerIndex'] is int
                ? ownData!['answerIndex'] as int
                : null;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'PREGUNTA ${_questionIndex + 1} DE '
                  '${WolvesMatchService.icebreakerQuestions.length}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFC6A574),
                    fontSize: 10,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _question.prompt,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFF2E8D8),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                for (var index = 0; index < _question.options.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: OutlinedButton(
                      onPressed: ownIndex != null || _submitting
                          ? null
                          : () => _submitAnswer(index),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: ownIndex == index
                            ? const Color(0xFFC6A574)
                            : const Color(0xFFF2E8D8),
                        side: BorderSide(
                          color: ownIndex == index
                              ? const Color(0xFFC6A574)
                              : const Color(0xFF5A4934),
                        ),
                      ),
                      child: Text(_question.options[index]),
                    ),
                  ),
                if (ownIndex != null) ...[
                  const SizedBox(height: 5),
                  const Text(
                    'Tu respuesta quedó guardada.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFC6A574), fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    key: ValueKey('peer-${_question.id}'),
                    stream: widget.service.watchIcebreakerAnswer(
                      context: widget.gameContext,
                      questionId: _question.id,
                      publicId: widget.gameContext.peerPublicId,
                    ),
                    builder: (context, peerSnapshot) {
                      if (peerSnapshot.hasError) {
                        return const Text(
                          'No se pudo consultar la respuesta de tu conexión.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFFF8A80),
                            fontSize: 11,
                          ),
                        );
                      }
                      final peerData = peerSnapshot.data?.data();
                      final peerIndex = peerData?['answerIndex'] is int
                          ? peerData!['answerIndex'] as int
                          : null;
                      return Text(
                        peerIndex == null
                            ? 'Esperando la respuesta de ${widget.peerName}…'
                            : '${widget.peerName} eligió: '
                                '${_question.options[peerIndex]}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFF2E8D8),
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFF8A80),
                      fontSize: 11,
                    ),
                  ),
                ],
                if (_submitting)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFFC6A574),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _questionIndex == 0 || _submitting
              ? null
              : () => setState(() {
                    _questionIndex--;
                    _error = null;
                  }),
          child: const Text('ANTERIOR'),
        ),
        TextButton(
          onPressed: _questionIndex ==
                  WolvesMatchService.icebreakerQuestions.length - 1
              ? () => Navigator.of(context).pop()
              : () => setState(() {
                    _questionIndex++;
                    _error = null;
                  }),
          child: Text(
            _questionIndex == WolvesMatchService.icebreakerQuestions.length - 1
                ? 'CERRAR'
                : 'SIGUIENTE',
          ),
        ),
      ],
    );
  }
}
