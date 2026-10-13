import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'lost_pet_service.dart';
import 'profile_creation_form.dart' show compressProfileImageBytes;

class LostPetScreen extends StatefulWidget {
  const LostPetScreen({
    super.key,
    required this.onBack,
    this.initialMissionId,
    this.onSharedMissionConsumed,
  });

  final VoidCallback onBack;
  final String? initialMissionId;
  final VoidCallback? onSharedMissionConsumed;

  @override
  State<LostPetScreen> createState() => _LostPetScreenState();
}

class _LostPetScreenState extends State<LostPetScreen> {
  static const _background = Color(0xFF15120F);
  static const _panel = Color(0xFF211D19);
  static const _gold = Color(0xFFC6A06A);
  static const _cream = Color(0xFFE9DCCB);
  static const _muted = Color(0xFFB7AA9D);

  final _service = LostPetService();
  final _draftPhotoPicker = ImagePicker();
  final _searchController = TextEditingController();
  final _cityController = TextEditingController();
  final _areaController = TextEditingController();
  final List<Uint8List> _draftMissionPhotos = [];
  String _section = 'home';
  String _speciesFilter = 'all';
  String _statusFilter = 'all';
  String _dateFilter = 'all';
  String? _error;
  bool _pickingDraftPhotos = false;
  bool _deepLinkHandled = false;

  @override
  void dispose() {
    _searchController.dispose();
    _cityController.dispose();
    _areaController.dispose();
    super.dispose();
  }

  Future<void> _openMissionForm({
    LostPetMission? mission,
    List<Uint8List> draftPhotos = const [],
  }) async {
    var initialPhotos = mission == null ? draftPhotos : const <Uint8List>[];
    var initialIdentification = '';
    try {
      if (mission != null) {
        initialPhotos = await _service.getMissionPhotos(
          mission.id,
          count: mission.photoCount,
        );
        initialIdentification =
            await _service.getPrivateIdentification(mission.id);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudieron cargar las fotos: $error')),
        );
      }
      return;
    }
    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _MissionEditorScreen(
          service: _service,
          mission: mission,
          initialPhotos: initialPhotos,
          initialIdentification: initialIdentification,
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        _error = null;
        _section = 'missions';
        if (mission == null) _draftMissionPhotos.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mission == null
                ? 'La misión de reencuentro ya está publicada.'
                : 'La misión se actualizó.',
          ),
        ),
      );
    }
  }

  Future<void> _pickDraftMissionPhotos() async {
    if (_pickingDraftPhotos || _draftMissionPhotos.length >= 3) return;
    setState(() => _pickingDraftPhotos = true);
    try {
      final selected = await _draftPhotoPicker.pickMultiImage(
        imageQuality: 100,
        maxWidth: 1800,
        maxHeight: 1800,
      );
      final remaining = 3 - _draftMissionPhotos.length;
      final added = <Uint8List>[];
      for (final image in selected.take(remaining)) {
        added.add(
          await compute(compressProfileImageBytes, await image.readAsBytes()),
        );
      }
      if (mounted && added.isNotEmpty) {
        setState(() => _draftMissionPhotos.addAll(added));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudieron cargar las fotos: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingDraftPhotos = false);
    }
  }

  Future<void> _openSightingForm(
    List<LostPetMission> missions, {
    LostPetMission? initialMission,
  }) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _SightingEditorScreen(
          service: _service,
          missions: missions
              .where((item) =>
                  item.status == 'active' ||
                  item.status == 'sightings' ||
                  item.status == 'verifying')
              .toList(),
          initialMission: initialMission,
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        _error = null;
        _section = 'sightings';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gracias por aportar este avistamiento.')),
      );
    }
  }

  Future<void> _openSharedMission({
    required String userUid,
    required List<LostPetMission> missions,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> sightings,
    required Set<String> favoriteIds,
  }) async {
    final missionId = widget.initialMissionId;
    if (missionId == null) return;
    widget.onSharedMissionConsumed?.call();
    try {
      LostPetMission? mission;
      for (final item in missions) {
        if (item.id == missionId) {
          mission = item;
          break;
        }
      }
      mission ??= await _service.getMission(missionId);
      if (!mounted) return;
      if (mission == null) {
        setState(() => _error = 'No encontramos esa misión compartida.');
        return;
      }
      await _openMissionDetails(
        mission,
        missions: missions,
        sightings: sightings,
        favoriteIds: favoriteIds,
        userUid: userUid,
      );
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = 'No se pudo abrir la misión compartida: $error');
      }
    }
  }

  List<LostPetMission> _filteredMissions(
    List<LostPetMission> missions,
    String uid,
  ) {
    final now = DateTime.now();
    final query = _searchController.text.trim().toLowerCase();
    return missions.where((mission) {
      final isMyMission = mission.ownerUid == uid;
      if (_section == 'myMissions' && !isMyMission) return false;
      if (_section == 'missions' &&
          (mission.status == 'reunited' || mission.status == 'closed')) {
        return false;
      }
      if (_section == 'home' &&
          (mission.status == 'reunited' || mission.status == 'closed')) {
        return false;
      }
      if (_section == 'reunited' && mission.status != 'reunited') return false;
      if (_section == 'reunited' && !mission.shareReunion) return false;
      if (_section == 'missions' &&
          _statusFilter != 'all' &&
          mission.status != _statusFilter) {
        return false;
      }
      if (_speciesFilter != 'all' && mission.species != _speciesFilter) {
        return false;
      }
      if (_dateFilter == '7' && now.difference(mission.missingAt).inDays > 7) {
        return false;
      }
      if (_dateFilter == '30' &&
          now.difference(mission.missingAt).inDays > 30) {
        return false;
      }
      if (_cityController.text.trim().isNotEmpty &&
          !mission.city
              .toLowerCase()
              .contains(_cityController.text.trim().toLowerCase())) {
        return false;
      }
      if (_areaController.text.trim().isNotEmpty &&
          !mission.area
              .toLowerCase()
              .contains(_areaController.text.trim().toLowerCase())) {
        return false;
      }
      if (query.isNotEmpty &&
          ![
            mission.petName,
            mission.breed,
            mission.description,
            mission.color,
            mission.markings,
            mission.city,
            mission.area,
            mission.lastSeenArea,
          ].any((value) => value.toLowerCase().contains(query))) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous || !user.emailVerified) {
      return _scaffold(
        body: const _EmptyState(
          icon: Icons.lock_outline,
          title: 'Un espacio para la Manada',
          message:
              'Inicia sesión y verifica tu correo para consultar o publicar misiones.',
        ),
      );
    }
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _service.watchMissions(),
      builder: (context, missionSnapshot) {
        if (missionSnapshot.hasError) {
          return _scaffold(
            body: _loadError(missionSnapshot.error!),
          );
        }
        if (!missionSnapshot.hasData) {
          return _scaffold(
            body: const Center(
              child: CircularProgressIndicator(color: _gold),
            ),
          );
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _service.watchMyMissions(user.uid),
          builder: (context, myMissionSnapshot) {
            if (myMissionSnapshot.hasError) {
              return _scaffold(body: _loadError(myMissionSnapshot.error!));
            }
            if (!myMissionSnapshot.hasData) {
              return _scaffold(
                body: const Center(
                  child: CircularProgressIndicator(color: _gold),
                ),
              );
            }
            final missionDocuments =
                <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
            for (final document in missionSnapshot.data!.docs) {
              missionDocuments[document.id] = document;
            }
            for (final document in myMissionSnapshot.data!.docs) {
              missionDocuments[document.id] = document;
            }
            final missions = <LostPetMission>[];
            for (final document in missionDocuments.values) {
              try {
                missions.add(
                  LostPetMission.fromMap(document.id, document.data()),
                );
              } on FormatException catch (error) {
                _error = error.message;
              }
            }
            missions.sort(
              (first, second) => second.updatedAt.compareTo(first.updatedAt),
            );
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _service.watchSightings(),
              builder: (context, sightingSnapshot) {
                if (sightingSnapshot.hasError) {
                  return _scaffold(body: _loadError(sightingSnapshot.error!));
                }
                if (!sightingSnapshot.hasData) {
                  return _scaffold(
                    body: const Center(
                      child: CircularProgressIndicator(color: _gold),
                    ),
                  );
                }
                final sightings = sightingSnapshot.data!.docs;
                final visibleMissions = _filteredMissions(missions, user.uid);
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _service.watchFavorites(user.uid),
                  builder: (context, favoriteSnapshot) {
                    final favoriteIds = favoriteSnapshot.data?.docs
                            .map((document) => document.data()['missionId'])
                            .whereType<String>()
                            .toSet() ??
                        <String>{};
                    if (!_deepLinkHandled &&
                        widget.initialMissionId != null &&
                        favoriteSnapshot.hasData) {
                      _deepLinkHandled = true;
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => _openSharedMission(
                          userUid: user.uid,
                          missions: missions,
                          sightings: sightings,
                          favoriteIds: favoriteIds,
                        ),
                      );
                    }
                    final favoriteError = favoriteSnapshot.error;
                    return _scaffold(
                      body: Column(
                        children: [
                          if (favoriteSnapshot.hasError)
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                'No se pudieron cargar tus favoritos (${favoriteError is FirebaseException ? favoriteError.code : 'error'}).',
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          Expanded(
                            child: _mainBody(
                              userUid: user.uid,
                              missions: missions,
                              visibleMissions: visibleMissions,
                              sightings: sightings,
                              favoriteIds: favoriteIds,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _scaffold({required Widget body}) => Container(
        color: _background,
        child: SafeArea(
          child: Column(
            children: [
              _header(),
              if (_error != null) _errorBanner(),
              Expanded(child: body),
            ],
          ),
        ),
      );

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Volver',
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back, color: _cream),
            ),
            const Expanded(
              child: Text(
                'HOY NOS FALTA UNO',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _cream,
                  fontSize: 13,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Ver la guía El rastro de regreso',
              onPressed: () => setState(() => _section = 'guide'),
              icon: const Icon(Icons.menu_book_outlined, color: _gold),
            ),
          ],
        ),
      );

  Widget _errorBanner() => MaterialBanner(
        backgroundColor: const Color(0xFF3A2922),
        content: Text(
          'No pudimos cargar todo el contenido. ${_error ?? ''}',
          style: const TextStyle(color: _cream),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() => _error = null),
            child: const Text('CERRAR'),
          ),
        ],
      );

  Widget _loadError(Object error) {
    final text = error is FirebaseException
        ? 'No se pudo consultar el servicio (${error.code}).'
        : 'No se pudo cargar el contenido.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, color: _gold, size: 36),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => setState(() {}),
              child: const Text('INTENTAR DE NUEVO'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mainBody({
    required String userUid,
    required List<LostPetMission> missions,
    required List<LostPetMission> visibleMissions,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> sightings,
    required Set<String> favoriteIds,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
            children: [
              if (_section == 'home') ...[
                _hero(missions, sightings),
                const SizedBox(height: 14),
                _photoUploadCard(),
                const SizedBox(height: 20),
                _sectionTitle('MISIONES DE REENCUENTRO'),
                const SizedBox(height: 10),
                _filterPanel(),
                const SizedBox(height: 12),
                _missionCards(
                  visibleMissions,
                  missions: missions,
                  sightings: sightings,
                  favoriteIds: favoriteIds,
                  userUid: userUid,
                ),
              ] else if (_section == 'missions' ||
                  _section == 'myMissions' ||
                  _section == 'reunited') ...[
                _sectionTitle(
                  _section == 'reunited'
                      ? 'VOLVIÓ A CASA'
                      : _section == 'myMissions'
                          ? 'MIS MISIONES'
                          : 'MISIONES DE REENCUENTRO',
                ),
                const SizedBox(height: 12),
                if (_section != 'reunited') _filterPanel(),
                const SizedBox(height: 12),
                _missionCards(
                  visibleMissions,
                  missions: missions,
                  sightings: sightings,
                  favoriteIds: favoriteIds,
                  userUid: userUid,
                ),
              ] else if (_section == 'sightings') ...[
                _sectionTitle('AVISTAMIENTOS RECIENTES'),
                const SizedBox(height: 8),
                const Text(
                  'Cada reporte es una pista por verificar, no una coincidencia confirmada.',
                  style: TextStyle(color: _muted, height: 1.45),
                ),
                const SizedBox(height: 14),
                if (sightings.isEmpty)
                  const _EmptyState(
                    icon: Icons.visibility_outlined,
                    title: 'Aún no hay avistamientos',
                    message:
                        'Si viste una mascota que podría estar perdida, comparte una descripción y una zona aproximada.',
                  )
                else
                  ...sightings.map(
                    (document) => _sightingCard(
                      document.data(),
                      missions,
                      onMissionTap: (mission) => _openMissionDetails(
                        mission,
                        missions: missions,
                        sightings: sightings,
                        favoriteIds: favoriteIds,
                        userUid: userUid,
                      ),
                    ),
                  ),
              ] else if (_section == 'guide') ...[
                _guide(),
              ] else ...[
                _myContactRequests(userUid),
              ],
              const SizedBox(height: 24),
              _footerNotice(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero(
    List<LostPetMission> missions,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> sightings,
  ) =>
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _gold.withValues(alpha: 0.32)),
          gradient: const LinearGradient(
            colors: [Color(0xFF2B2119), Color(0xFF1B1815)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.pets_outlined, color: _gold, size: 34),
            const SizedBox(height: 12),
            const Text(
              'Ningún miembro de la Manada debería buscar solo.',
              style: TextStyle(
                color: _cream,
                fontSize: 23,
                height: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Una comunidad atenta puede ayudar a compartir información y acercar pistas. No garantizamos reencuentros.',
              style: TextStyle(color: _muted, height: 1.5),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _openSightingForm(missions),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('VI UNA MASCOTA'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _cream,
                    side: BorderSide(color: _gold.withValues(alpha: 0.55)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _quickLink(
                  'AVISTAMIENTOS (${sightings.length})',
                  Icons.visibility_outlined,
                  () => setState(() => _section = 'sightings'),
                ),
                _quickLink(
                  'EL RASTRO DE REGRESO',
                  Icons.menu_book_outlined,
                  () => setState(() => _section = 'guide'),
                ),
                _quickLink(
                  'VOLVIÓ A CASA',
                  Icons.home_outlined,
                  () => setState(() => _section = 'reunited'),
                ),
                _quickLink(
                  'MIS MISIONES',
                  Icons.manage_search_outlined,
                  () => setState(() => _section = 'myMissions'),
                ),
                _quickLink(
                  'MENSAJES',
                  Icons.mail_outline,
                  () => setState(() => _section = 'myMessages'),
                ),
              ],
            ),
            if (missions
                .where((item) =>
                    item.status != 'reunited' && item.status != 'closed')
                .isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  '${missions.where((item) => item.status != 'reunited' && item.status != 'closed').length} misiones activas en la comunidad',
                  style: const TextStyle(color: _gold, fontSize: 12),
                ),
              ),
          ],
        ),
      );

  Widget _quickLink(String label, IconData icon, VoidCallback onPressed) =>
      ActionChip(
        avatar: Icon(icon, color: _gold, size: 17),
        label: Text(label, style: const TextStyle(color: _cream, fontSize: 10)),
        backgroundColor: _background,
        side: BorderSide(color: _gold.withValues(alpha: 0.2)),
        onPressed: onPressed,
      );

  Widget _sectionTitle(String title) => Text(
        title,
        style: const TextStyle(
          color: _gold,
          letterSpacing: 1.4,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      );

  Widget _filterPanel() => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: _gold.withValues(alpha: 0.14)),
        ),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: _cream),
              decoration: _inputDecoration(
                label: 'Buscar mascota, raza o descripción',
                icon: Icons.search,
              ),
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 570;
                final fields = [
                  TextField(
                    controller: _cityController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: _cream),
                    decoration: _inputDecoration(
                      label: 'Ciudad',
                      icon: Icons.location_city_outlined,
                    ),
                  ),
                  TextField(
                    controller: _areaController,
                    onChanged: (_) => setState(() {}),
                    style: const TextStyle(color: _cream),
                    decoration: _inputDecoration(
                      label: 'Zona aproximada',
                      icon: Icons.place_outlined,
                    ),
                  ),
                  _dropdownFilter(
                    value: _speciesFilter,
                    label: 'Especie',
                    values: const {
                      'all': 'Todas',
                      'dog': 'Perro',
                      'cat': 'Gato',
                      'other': 'Otra',
                    },
                    onChanged: (value) =>
                        setState(() => _speciesFilter = value),
                  ),
                  _dropdownFilter(
                    value: _dateFilter,
                    label: 'Fecha',
                    values: const {
                      'all': 'Cualquiera',
                      '7': 'Últimos 7 días',
                      '30': 'Últimos 30 días',
                    },
                    onChanged: (value) => setState(() => _dateFilter = value),
                  ),
                ];
                if (narrow) {
                  return Column(
                    children: [
                      for (var index = 0; index < fields.length; index++) ...[
                        if (index > 0) const SizedBox(height: 8),
                        fields[index],
                      ],
                    ],
                  );
                }
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final field in fields)
                      SizedBox(
                          width: (constraints.maxWidth - 8) / 2, child: field),
                  ],
                );
              },
            ),
            if (_section == 'missions' || _section == 'myMissions') ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  children: [
                    for (final entry in const {
                      'all': 'Todos los estados',
                      'active': 'Activas',
                      'sightings': 'Con avistamientos',
                      'verifying': 'En verificación',
                    }.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: _statusFilter == entry.key,
                        onSelected: (_) =>
                            setState(() => _statusFilter = entry.key),
                        selectedColor: _gold,
                        backgroundColor: _background,
                        labelStyle: TextStyle(
                          color:
                              _statusFilter == entry.key ? _background : _cream,
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  Widget _dropdownFilter({
    required String value,
    required String label,
    required Map<String, String> values,
    required ValueChanged<String> onChanged,
  }) =>
      DropdownButtonFormField<String>(
        value: value,
        dropdownColor: _panel,
        style: const TextStyle(color: _cream, fontSize: 13),
        decoration: _inputDecoration(label: label, icon: Icons.filter_list),
        items: values.entries
            .map((entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value),
                ))
            .toList(),
        onChanged: (next) {
          if (next != null) onChanged(next);
        },
      );

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) =>
      InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: _muted, fontSize: 12),
        prefixIcon: Icon(icon, color: _gold, size: 18),
        filled: true,
        fillColor: _background,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: _gold.withValues(alpha: 0.16)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide(color: _gold.withValues(alpha: 0.16)),
        ),
      );

  Widget _missionCards(
    List<LostPetMission> items, {
    required List<LostPetMission> missions,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> sightings,
    required Set<String> favoriteIds,
    required String userUid,
  }) {
    if (items.isEmpty) {
      final hasActiveMissions = missions.any(
        (mission) =>
            const {'active', 'sightings', 'verifying'}.contains(mission.status),
      );
      final noResultsAfterFiltering =
          hasActiveMissions && (_section == 'home' || _section == 'missions');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _EmptyState(
            icon: _section == 'reunited'
                ? Icons.favorite_border
                : Icons.pets_outlined,
            title: _section == 'reunited'
                ? 'Aún no hay historias para celebrar'
                : noResultsAfterFiltering
                    ? 'No encontramos misiones con esos filtros'
                    : _section == 'myMissions'
                        ? 'Aún no has publicado una misión'
                        : 'Todavía no hay misiones activas',
            message: _section == 'reunited'
                ? 'Cuando una familia autorice compartir su reencuentro, aparecerá aquí.'
                : noResultsAfterFiltering
                    ? 'Amplía los filtros para ver otras búsquedas de la comunidad.'
                    : 'Puedes iniciar una misión de reencuentro o ayudar reportando un avistamiento.',
            actionLabel: noResultsAfterFiltering ? 'LIMPIAR FILTROS' : null,
            onAction: noResultsAfterFiltering
                ? () => setState(() {
                      _searchController.clear();
                      _cityController.clear();
                      _areaController.clear();
                      _speciesFilter = 'all';
                      _statusFilter = 'all';
                      _dateFilter = 'all';
                    })
                : null,
          ),
          if (_section != 'reunited') ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const ValueKey('lost-pet-empty-create-mission'),
              onPressed: () => _openMissionForm(),
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('PUBLICAR UNA MISIÓN DE REENCUENTRO'),
              style: FilledButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: _background,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              key: const ValueKey('lost-pet-empty-report-sighting'),
              onPressed: () => _openSightingForm(missions),
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('REPORTAR UN AVISTAMIENTO'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _cream,
                side: BorderSide(color: _gold.withValues(alpha: 0.55)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        ],
      );
    }
    return Column(
      children: items
          .map(
            (mission) => _missionCard(
              mission,
              missions: missions,
              sightings: sightings,
              favoriteIds: favoriteIds,
              userUid: userUid,
            ),
          )
          .toList(),
    );
  }

  Widget _missionCard(
    LostPetMission mission, {
    required List<LostPetMission> missions,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> sightings,
    required Set<String> favoriteIds,
    required String userUid,
  }) {
    final status =
        lostPetStatusLabels[mission.status] ?? 'Estado sin verificar';
    return Card(
      color: _panel,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(color: _gold.withValues(alpha: 0.16)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openMissionDetails(
          mission,
          missions: missions,
          sightings: sightings,
          favoriteIds: favoriteIds,
          userUid: userUid,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mission.photoCount > 0)
              FutureBuilder<Uint8List?>(
                future: _service.getMissionPhoto(mission.id),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return _imagePlaceholder();
                  final image = snapshot.data;
                  return image == null
                      ? _imagePlaceholder()
                      : Image.memory(
                          image,
                          width: double.infinity,
                          height: 190,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _imagePlaceholder(),
                        );
                },
              )
            else
              _imagePlaceholder(),
            Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    children: [
                      _statusBadge(status, mission.status),
                      if (mission.ownerUid == userUid)
                        _statusBadge('TU MISIÓN', 'owner'),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Text(
                    mission.petName.isEmpty
                        ? 'Nombre no conocido'
                        : mission.petName,
                    style: const TextStyle(
                      color: _cream,
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const SizedBox(height: 9),
                  const Text(
                    'DATOS DE LA MASCOTA',
                    style: TextStyle(
                      color: _gold,
                      fontSize: 10,
                      letterSpacing: 0.9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _detailChip(_speciesLabel(mission.species)),
                      if (mission.breed.isNotEmpty) _detailChip(mission.breed),
                      if (mission.size != 'unknown' && mission.size.isNotEmpty)
                        _detailChip(_sizeLabel(mission.size)),
                      if (mission.color.isNotEmpty) _detailChip(mission.color),
                      if (mission.sex != 'unknown' && mission.sex.isNotEmpty)
                        _detailChip(_sexLabel(mission.sex)),
                      if (mission.markings.isNotEmpty)
                        _detailChip('Señas: ${mission.markings}'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'DESCRIPCIÓN DE LA PÉRDIDA',
                    style: TextStyle(
                      color: _gold,
                      fontSize: 10,
                      letterSpacing: 0.9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mission.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _cream, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    children: [
                      _metadata(Icons.location_on_outlined,
                          '${mission.area}, ${mission.city}'),
                      _metadata(Icons.schedule,
                          'Perdida ${_dateLabel(mission.missingAt)}'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailChip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: _gold.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _gold.withValues(alpha: 0.18)),
        ),
        child: Text(
          label,
          style: const TextStyle(color: _cream, fontSize: 10),
        ),
      );

  String _sizeLabel(String size) => switch (size) {
        'small' => 'Pequeño',
        'medium' => 'Mediano',
        'large' => 'Grande',
        _ => 'Tamaño no conocido',
      };

  String _sexLabel(String sex) => switch (sex) {
        'female' => 'Hembra',
        'male' => 'Macho',
        _ => 'Sexo no conocido',
      };

  Widget _imagePlaceholder() => Container(
        height: 180,
        width: double.infinity,
        color: const Color(0xFF302820),
        child: const Icon(Icons.pets_outlined, color: _gold, size: 54),
      );

  Uint8List? _decodePhoto(String source) {
    try {
      return base64Decode(source);
    } on FormatException {
      return null;
    }
  }

  Widget _statusBadge(String label, String status) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: status == 'reunited'
              ? const Color(0xFF254136)
              : _gold.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: status == 'reunited' ? const Color(0xFF9DD4B0) : _gold,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _metadata(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _gold, size: 15),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
          ),
        ],
      );

  Widget _photoUploadCard() {
    final hasPhotos = _draftMissionPhotos.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _gold.withValues(alpha: 0.34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'SUBE LA FOTO DE TU AMIGO PERDIDO',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _cream,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Una imagen clara puede ayudar a reconocerlo y compartir su búsqueda.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 14),
          Material(
            color: _background.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              onTap: _pickingDraftPhotos ? null : _pickDraftMissionPhotos,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                constraints: const BoxConstraints(minHeight: 196),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _gold.withValues(alpha: 0.65),
                    width: 1.2,
                  ),
                ),
                child: hasPhotos
                    ? SizedBox(
                        height: 190,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _draftMissionPhotos.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (context, index) => Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(
                                  _draftMissionPhotos[index],
                                  width: 220,
                                  height: 190,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: IconButton(
                                  tooltip: 'Quitar foto',
                                  onPressed: () => setState(
                                    () => _draftMissionPhotos.removeAt(index),
                                  ),
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                  ),
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black54,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _pickingDraftPhotos
                                  ? Icons.hourglass_top
                                  : Icons.add_a_photo_outlined,
                              color: _gold,
                              size: 48,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _pickingDraftPhotos
                                  ? 'CARGANDO FOTO…'
                                  : 'TOCA PARA SUBIR LA FOTO DE TU MASCOTA',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: _cream,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 5),
                            const Text(
                              'Puedes agregar hasta 3 fotos',
                              style: TextStyle(color: _muted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
          if (hasPhotos) ...[
            const SizedBox(height: 9),
            Text(
              '${_draftMissionPhotos.length} foto${_draftMissionPhotos.length == 1 ? '' : 's'} lista${_draftMissionPhotos.length == 1 ? '' : 's'} para el aviso',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _gold, fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _pickingDraftPhotos
                ? null
                : hasPhotos
                    ? () => _openMissionForm(
                          draftPhotos: List.unmodifiable(_draftMissionPhotos),
                        )
                    : _pickDraftMissionPhotos,
            icon: Icon(
              hasPhotos ? Icons.edit_note : Icons.add_a_photo_outlined,
            ),
            label: Text(
              hasPhotos ? 'COMPLETAR DATOS DE LA PÉRDIDA' : 'ELEGIR FOTOGRAFÍA',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: _background,
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'La publicación se comparte cuando completes y confirmes la misión.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _sightingCard(
    Map<String, dynamic> data,
    List<LostPetMission> missions, {
    required ValueChanged<LostPetMission> onMissionTap,
  }) {
    final image = data['photoBase64'] is String &&
            (data['photoBase64'] as String).isNotEmpty
        ? _decodePhoto(data['photoBase64'] as String)
        : null;
    final missionId =
        data['missionId'] is String ? data['missionId'] as String : '';
    LostPetMission? mission;
    for (final candidate in missions) {
      if (candidate.id == missionId) {
        mission = candidate;
        break;
      }
    }
    final sightedAt = (data['sightedAt'] as Timestamp?)?.toDate();
    return Card(
      color: _panel,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (image != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  image,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            Row(
              children: [
                const Icon(Icons.visibility_outlined, color: _gold, size: 19),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${_speciesLabel((data['species'] as String?) ?? 'other')} · ${(data['area'] as String?) ?? 'Zona no indicada'}, ${(data['city'] as String?) ?? ''}',
                    style: const TextStyle(
                        color: _cream, fontWeight: FontWeight.w600),
                  ),
                ),
                _statusBadge('POR VERIFICAR', 'verifying'),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              (data['description'] as String?) ?? '',
              style: const TextStyle(color: _muted, height: 1.4),
            ),
            if ((data['direction'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 5),
              Text(
                'Dirección: ${data['direction']}',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
            if (sightedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: Text(
                  'Visto ${_dateLabel(sightedAt)}',
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ),
            if (mission != null)
              TextButton.icon(
                onPressed: () => onMissionTap(mission!),
                icon: const Icon(Icons.link, size: 16),
                label: Text(
                    'Posible relación con ${mission.petName.isEmpty ? 'una misión' : mission.petName}'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMissionDetails(
    LostPetMission mission, {
    required List<LostPetMission> missions,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> sightings,
    required Set<String> favoriteIds,
    required String userUid,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _panel,
      builder: (sheetContext) => _MissionDetailsSheet(
        service: _service,
        mission: mission,
        isOwner: mission.ownerUid == userUid,
        isFavorite: favoriteIds.contains(mission.id),
        onEdit: () {
          Navigator.pop(sheetContext);
          _openMissionForm(mission: mission);
        },
        onReportSighting: () {
          Navigator.pop(sheetContext);
          _openSightingForm(missions, initialMission: mission);
        },
        onChanged: () => setState(() {}),
      ),
    );
  }

  Widget _guide() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('EL RASTRO DE REGRESO'),
          const SizedBox(height: 8),
          const Text(
            'Orientación general: adapta cada paso a la especie, el temperamento y la situación. Si hay riesgo o lesiones, busca asistencia local.',
            style: TextStyle(color: _muted, height: 1.5),
          ),
          const SizedBox(height: 12),
          for (final article in _guideArticles)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: _panel,
                borderRadius: BorderRadius.circular(13),
              ),
              child: ExpansionTile(
                iconColor: _gold,
                collapsedIconColor: _gold,
                title: Text(
                  article.$1,
                  style: const TextStyle(
                    color: _cream,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      article.$2,
                      style: const TextStyle(color: _muted, height: 1.55),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );

  Widget _myContactRequests(String userUid) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('MIS MENSAJES'),
          const SizedBox(height: 8),
          const Text(
            'Las solicitudes y respuestas de contacto se muestran solo a las personas involucradas.',
            style: TextStyle(color: _muted, height: 1.4),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _service.watchMyContactRequests(userUid),
            builder: (context, snapshot) {
              if (snapshot.hasError) return _loadError(snapshot.error!);
              if (!snapshot.hasData) {
                return const Center(
                    child: CircularProgressIndicator(color: _gold));
              }
              if (snapshot.data!.docs.isEmpty) {
                return const _EmptyState(
                  icon: Icons.mail_outline,
                  title: 'No tienes mensajes todavía',
                  message:
                      'Si envías una solicitud para contactar a una familia, podrás seguir la conversación aquí.',
                );
              }
              final requests = snapshot.data!.docs.toList()
                ..sort((first, second) {
                  final firstDate =
                      (first.data()['createdAt'] as Timestamp?)?.toDate();
                  final secondDate =
                      (second.data()['createdAt'] as Timestamp?)?.toDate();
                  return (secondDate ?? DateTime(2000))
                      .compareTo(firstDate ?? DateTime(2000));
                });
              return Column(
                children: requests.map((document) {
                  final data = document.data();
                  final mission = data['missionId'] as String? ?? '';
                  return Card(
                    color: _panel,
                    child: ListTile(
                      leading: const Icon(Icons.pets_outlined, color: _gold),
                      title: Text(
                        'Misión ${_shortId(mission)}',
                        style: const TextStyle(color: _cream),
                      ),
                      subtitle: Text(
                        [
                          data['message'] as String? ?? '',
                          if ((data['ownerReply'] as String?)?.isNotEmpty ==
                              true)
                            'Respuesta: ${data['ownerReply']}',
                        ].join('\n\n'),
                        style: const TextStyle(color: _muted, height: 1.4),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      );

  Widget _footerNotice() => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: _gold.withValues(alpha: 0.12)),
        ),
        child: const Text(
          'Coffee Wolves facilita compartir información comunitaria; no es un servicio de rescate ni garantiza encontrar a una mascota. No publiques teléfonos, domicilios ni ubicaciones exactas en tiempo real.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _muted, fontSize: 11, height: 1.5),
        ),
      );

  String _speciesLabel(String species) => switch (species) {
        'dog' => 'Perro',
        'cat' => 'Gato',
        'other' => 'Otra especie',
        _ => 'Especie no conocida',
      };

  String _dateLabel(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  String _shortId(String id) =>
      id.length > 9 ? id.substring(0, 9).toUpperCase() : id.toUpperCase();
}

class _MissionDetailsSheet extends StatefulWidget {
  const _MissionDetailsSheet({
    required this.service,
    required this.mission,
    required this.isOwner,
    required this.isFavorite,
    required this.onEdit,
    required this.onReportSighting,
    required this.onChanged,
  });

  final LostPetService service;
  final LostPetMission mission;
  final bool isOwner;
  final bool isFavorite;
  final VoidCallback onEdit;
  final VoidCallback onReportSighting;
  final VoidCallback onChanged;

  @override
  State<_MissionDetailsSheet> createState() => _MissionDetailsSheetState();
}

class _MissionDetailsSheetState extends State<_MissionDetailsSheet> {
  static const _gold = Color(0xFFC6A06A);
  static const _cream = Color(0xFFE9DCCB);
  static const _muted = Color(0xFFB7AA9D);
  bool _busy = false;
  String? _error;

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _contactOwner() async {
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Contactar de forma privada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tu mensaje solo lo verá quien publicó esta misión. No incluyas teléfonos, domicilios ni datos financieros.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLength: 500,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Escribe tu mensaje',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(dialogContext, text);
            },
            child: const Text('ENVIAR'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (message == null || !mounted) return;
    await _run(() => widget.service.createContactRequest(
          missionId: widget.mission.id,
          message: message,
        ));
  }

  Future<void> _share() async {
    final mission = widget.mission;
    final url =
        'https://coffeewolves.github.io/coffeewolves/?module=lost-pet&mission=${mission.id}';
    final text = [
      'MISIÓN DE REENCUENTRO · Coffee Wolves',
      'Mascota: ${mission.petName.isEmpty ? 'nombre no conocido' : mission.petName}',
      'Especie: ${_speciesLabel(mission.species)} · ${mission.area}, ${mission.city}',
      'Última vez vista: ${_date(mission.missingAt)}',
      'Misión ${mission.id}',
      url,
      'Si tienes información, abre HOY NOS FALTA UNO en Coffee Wolves. No persigas al animal ni compartas ubicaciones exactas públicamente.',
    ].join('\n');
    final uri = Uri.https('wa.me', '/', {'text': text});
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        setState(
            () => _error = 'No se pudo abrir WhatsApp en este dispositivo.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'No se pudo compartir la misión: $error');
      }
    }
  }

  Future<void> _reportMission() async {
    String reason = 'sospechoso';
    final detailsController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Reportar misión'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: reason,
                items: const [
                  DropdownMenuItem(
                      value: 'sospechoso', child: Text('Posible fraude')),
                  DropdownMenuItem(
                      value: 'falso',
                      child: Text('Información posiblemente falsa')),
                  DropdownMenuItem(
                      value: 'abuso', child: Text('Contenido abusivo')),
                  DropdownMenuItem(
                      value: 'privacidad',
                      child: Text('Expone datos privados')),
                ],
                onChanged: (value) {
                  if (value != null) setDialogState(() => reason = value);
                },
              ),
              TextField(
                controller: detailsController,
                maxLength: 300,
                maxLines: 3,
                decoration:
                    const InputDecoration(labelText: 'Detalle opcional'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('CANCELAR'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('ENVIAR'),
            ),
          ],
        ),
      ),
    );
    final details = detailsController.text;
    detailsController.dispose();
    if (confirmed != true || !mounted) return;
    await _run(() => widget.service.reportMission(
          missionId: widget.mission.id,
          reason: reason,
          details: details,
        ));
  }

  Future<void> _resolveMission() async {
    final storyController = TextEditingController();
    var share = false;
    final result = await showDialog<({String story, bool share})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('¿Volvió a casa?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Al confirmar, la búsqueda dejará de aparecer entre las misiones activas. La historia solo se mostrará si autorizas compartirla.',
              ),
              TextField(
                controller: storyController,
                maxLength: 400,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Historia o agradecimiento (opcional)',
                ),
              ),
              CheckboxListTile(
                value: share,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                    'Autorizo publicar esta historia en VOLVIÓ A CASA'),
                onChanged: (value) =>
                    setDialogState(() => share = value ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('CANCELAR'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                (story: storyController.text, share: share),
              ),
              child: const Text('CONFIRMAR REENCUENTRO'),
            ),
          ],
        ),
      ),
    );
    final story = storyController.text;
    storyController.dispose();
    if (result == null || !mounted) return;
    await _run(() => widget.service.updateStatus(
          widget.mission.id,
          status: 'reunited',
          reunionStory: story,
          shareReunion: result.share,
        ));
  }

  Future<void> _updateStatus(String status) async {
    await _run(
      () => widget.service.updateStatus(widget.mission.id, status: status),
    );
  }

  Future<void> _replyToRequest(
    String requestId,
    String previousReply,
  ) async {
    final controller = TextEditingController(text: previousReply);
    final reply = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Responder de forma privada'),
        content: TextField(
          controller: controller,
          maxLength: 500,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'Tu respuesta'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: const Text('ENVIAR'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reply == null || !mounted) return;
    await _run(() => widget.service.replyToContactRequest(
          requestId: requestId,
          reply: reply,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final mission = widget.mission;
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.92,
        minChildSize: 0.55,
        maxChildSize: 0.96,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: _muted,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (mission.photoCount > 0)
              FutureBuilder<List<Uint8List>>(
                future: widget.service.getMissionPhotos(
                  mission.id,
                  count: mission.photoCount,
                ),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'No se pudieron cargar las fotos de esta misión.',
                        style: TextStyle(color: _muted),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const SizedBox(
                      height: 100,
                      child: Center(
                        child: CircularProgressIndicator(color: _gold),
                      ),
                    );
                  }
                  return SizedBox(
                    height: 230,
                    child: PageView(
                      children: snapshot.data!
                          .map(
                            (bytes) => ClipRRect(
                              borderRadius: BorderRadius.circular(15),
                              child: Image.memory(bytes, fit: BoxFit.cover),
                            ),
                          )
                          .toList(),
                    ),
                  );
                },
              ),
            const SizedBox(height: 12),
            Text(
              mission.petName.isEmpty ? 'Nombre no conocido' : mission.petName,
              style: const TextStyle(
                color: _cream,
                fontSize: 24,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${_speciesLabel(mission.species)} · ${mission.breed.isEmpty ? 'raza no conocida' : mission.breed}',
              style: const TextStyle(color: _muted),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: [
                _detailChip(mission.size),
                _detailChip(mission.color),
                if (mission.sex != 'unknown') _detailChip(mission.sex),
                _detailChip(lostPetStatusLabels[mission.status] ?? 'Estado'),
              ],
            ),
            const SizedBox(height: 12),
            _detailLine('Señas particulares', mission.markings),
            _detailLine('Desaparición aproximada', _date(mission.missingAt)),
            _detailLine('Ciudad y zona', '${mission.area}, ${mission.city}'),
            _detailLine('Última zona vista', mission.lastSeenArea),
            _detailLine('Descripción', mission.description),
            if (widget.isOwner)
              FutureBuilder<String>(
                future: widget.service.getPrivateIdentification(mission.id),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text(
                      'No se pudieron cargar los detalles privados.',
                      style: TextStyle(color: _muted, fontSize: 11),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return _detailLine(
                    'Collar o identificación (solo tú)',
                    snapshot.data!,
                  );
                },
              ),
            const SizedBox(height: 6),
            const Text(
              'La ubicación publicada es aproximada. Evita compartir puntos exactos en tiempo real.',
              style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
            ),
            if (mission.status == 'reunited' &&
                mission.shareReunion &&
                mission.reunionStory.isNotEmpty) ...[
              const SizedBox(height: 14),
              _detailLine('VOLVIÓ A CASA', mission.reunionStory),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _share,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('COMPARTIR POR WHATSAPP'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(() => widget.service.toggleFavorite(
                            missionId: mission.id,
                            isFavorite: widget.isFavorite,
                          )),
                  icon: Icon(widget.isFavorite
                      ? Icons.favorite
                      : Icons.favorite_border),
                  label: Text(widget.isFavorite ? 'GUARDADA' : 'GUARDAR'),
                ),
                if (!widget.isOwner && mission.status != 'reunited')
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _contactOwner,
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('CONTACTO PRIVADO'),
                  ),
                if (mission.status != 'reunited' && mission.status != 'closed')
                  OutlinedButton.icon(
                    onPressed: _busy ? null : widget.onReportSighting,
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('REPORTAR AVISTAMIENTO'),
                  ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _reportMission,
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('REPORTAR AVISO'),
                ),
                if (widget.isOwner) ...[
                  OutlinedButton.icon(
                    onPressed: _busy ? null : widget.onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('EDITAR MISIÓN'),
                  ),
                  if (mission.status != 'reunited' &&
                      mission.status != 'closed')
                    FilledButton.icon(
                      onPressed: _busy ? null : _resolveMission,
                      icon: const Icon(Icons.home_outlined),
                      label: const Text('VOLVIÓ A CASA'),
                    ),
                  if (mission.status != 'reunited' &&
                      mission.status != 'closed')
                    TextButton(
                      onPressed: _busy ? null : () => _updateStatus('closed'),
                      child: const Text('CERRAR MISIÓN'),
                    ),
                  for (final nextStatus in const [
                    'active',
                    'sightings',
                    'verifying'
                  ])
                    if (nextStatus != mission.status)
                      TextButton(
                        onPressed:
                            _busy ? null : () => _updateStatus(nextStatus),
                        child: Text(
                          switch (nextStatus) {
                            'active' => 'BÚSQUEDA ACTIVA',
                            'sightings' => 'HAY AVISTAMIENTOS',
                            _ => 'EN VERIFICACIÓN',
                          },
                        ),
                      ),
                ],
              ],
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                  child: CircularProgressIndicator(color: _gold),
                ),
              ),
            const SizedBox(height: 18),
            if (widget.isOwner) ...[
              const Text(
                'SOLICITUDES PRIVADAS DE CONTACTO',
                style: TextStyle(
                  color: _gold,
                  fontSize: 11,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: widget.service.watchContactRequests(mission.id),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text(
                      'No se pudieron cargar las solicitudes.',
                      style: TextStyle(color: _muted),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const LinearProgressIndicator(color: _gold);
                  }
                  if (snapshot.data!.docs.isEmpty) {
                    return const Text(
                      'Aún no hay solicitudes de contacto.',
                      style: TextStyle(color: _muted),
                    );
                  }
                  return Column(
                    children: snapshot.data!.docs.map((document) {
                      final data = document.data();
                      return Card(
                        color: const Color(0xFF302820),
                        child: ListTile(
                          title: Text(
                            data['senderName'] as String? ??
                                'Miembro de la Manada',
                            style: const TextStyle(color: _cream),
                          ),
                          subtitle: Text(
                            [
                              data['message'] as String? ?? '',
                              if ((data['ownerReply'] as String?)?.isNotEmpty ==
                                  true)
                                'Tu respuesta: ${data['ownerReply']}',
                            ].join('\n\n'),
                            style: const TextStyle(color: _muted),
                          ),
                          trailing: IconButton(
                            tooltip: 'Responder de forma privada',
                            onPressed: _busy
                                ? null
                                : () => _replyToRequest(
                                      document.id,
                                      data['ownerReply'] as String? ?? '',
                                    ),
                            icon: const Icon(Icons.reply, color: _gold),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
            const SizedBox(height: 18),
            const Text(
              'AVISTAMIENTOS VINCULADOS',
              style: TextStyle(
                color: _gold,
                fontSize: 11,
                letterSpacing: 1,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: widget.service.watchMissionSightings(mission.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text(
                    'No se pudieron cargar los avistamientos vinculados.',
                    style: TextStyle(color: _muted),
                  );
                }
                if (!snapshot.hasData) {
                  return const LinearProgressIndicator(color: _gold);
                }
                if (snapshot.data!.docs.isEmpty) {
                  return const Text(
                    'Todavía no hay pistas relacionadas con esta misión.',
                    style: TextStyle(color: _muted),
                  );
                }
                return Column(
                  children: snapshot.data!.docs.map((document) {
                    final data = document.data();
                    final sightedAt =
                        (data['sightedAt'] as Timestamp?)?.toDate();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.visibility_outlined,
                        color: _gold,
                      ),
                      title: Text(
                        '${data['area'] as String? ?? 'Zona no indicada'}, ${data['city'] as String? ?? ''}',
                        style: const TextStyle(color: _cream, fontSize: 13),
                      ),
                      subtitle: Text(
                        [
                          data['description'] as String? ?? '',
                          if (sightedAt != null)
                            'Avistamiento ${_date(sightedAt)}',
                          'Pista sin verificar',
                        ].join(' · '),
                        style: const TextStyle(color: _muted, height: 1.4),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: _muted, height: 1.45),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: _cream,
                fontWeight: FontWeight.w600,
              ),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _detailChip(String text) => Chip(
        label: Text(text.isEmpty ? 'No informado' : text),
        backgroundColor: const Color(0xFF302820),
        labelStyle: const TextStyle(color: _cream, fontSize: 10),
        side: BorderSide(color: _gold.withValues(alpha: 0.16)),
      );

  String _date(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';

  String _speciesLabel(String species) => switch (species) {
        'dog' => 'Perro',
        'cat' => 'Gato',
        'other' => 'Otra especie',
        _ => 'Especie desconocida',
      };
}

class _MissionEditorScreen extends StatefulWidget {
  const _MissionEditorScreen({
    required this.service,
    this.mission,
    this.initialPhotos = const [],
    this.initialIdentification = '',
  });

  final LostPetService service;
  final LostPetMission? mission;
  final List<Uint8List> initialPhotos;
  final String initialIdentification;

  @override
  State<_MissionEditorScreen> createState() => _MissionEditorScreenState();
}

class _MissionEditorScreenState extends State<_MissionEditorScreen> {
  static const _background = Color(0xFF15120F);
  static const _panel = Color(0xFF211D19);
  static const _gold = Color(0xFFC6A06A);
  static const _cream = Color(0xFFE9DCCB);
  static const _muted = Color(0xFFB7AA9D);
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final _petName = TextEditingController();
  final _breed = TextEditingController();
  final _color = TextEditingController();
  final _markings = TextEditingController();
  final _city = TextEditingController();
  final _area = TextEditingController();
  final _lastSeen = TextEditingController();
  final _description = TextEditingController();
  final _identification = TextEditingController();
  final List<Uint8List> _photos = [];
  String _species = 'dog';
  String _size = 'unknown';
  String _sex = 'unknown';
  DateTime _missingAt = DateTime.now();
  bool _authorized = false;
  bool _accurate = false;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.mission != null;

  @override
  void initState() {
    super.initState();
    final mission = widget.mission;
    if (mission == null) return;
    _petName.text = mission.petName;
    _breed.text = mission.breed;
    _color.text = mission.color;
    _markings.text = mission.markings;
    _city.text = mission.city;
    _area.text = mission.area;
    _lastSeen.text = mission.lastSeenArea;
    _description.text = mission.description;
    _identification.text = widget.initialIdentification;
    _species = mission.species;
    _size = mission.size;
    _sex = mission.sex;
    _missingAt = mission.missingAt;
    _authorized = true;
    _accurate = true;
    _photos.addAll(widget.initialPhotos);
  }

  @override
  void dispose() {
    for (final controller in [
      _petName,
      _breed,
      _color,
      _markings,
      _city,
      _area,
      _lastSeen,
      _description,
      _identification,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    try {
      final selected = await _picker.pickMultiImage(
        imageQuality: 100,
        maxWidth: 1800,
        maxHeight: 1800,
      );
      if (selected.isEmpty) return;
      final added = <Uint8List>[];
      for (final image in selected.take(3 - _photos.length)) {
        added.add(
          await compute(compressProfileImageBytes, await image.readAsBytes()),
        );
      }
      if (mounted) {
        setState(() {
          _photos.addAll(added);
          _error = null;
        });
      }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on ArgumentError catch (error) {
      if (mounted) setState(() => _error = error.message?.toString());
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'No se pudieron agregar las fotos: $error');
      }
    }
  }

  Future<void> _selectMissingDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate:
          _missingAt.isAfter(DateTime.now()) ? DateTime.now() : _missingAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      helpText: 'Fecha aproximada de desaparición',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_missingAt),
      helpText: 'Hora aproximada (puedes usar una estimación)',
    );
    if (time == null) {
      setState(() => _missingAt = DateTime(date.year, date.month, date.day));
    } else {
      setState(() => _missingAt = DateTime(
            date.year,
            date.month,
            date.day,
            time.hour,
            time.minute,
          ));
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_photos.isEmpty) {
      setState(() => _error = 'Agrega al menos una foto clara de la mascota.');
      return;
    }
    if (!_authorized || !_accurate) {
      setState(
          () => _error = 'Confirma la autorización y veracidad del aviso.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final fields = {
        'petName': _petName.text,
        'species': _species,
        'breed': _breed.text,
        'size': _size,
        'color': _color.text,
        'sex': _sex,
        'markings': _markings.text,
        'missingAt': _missingAt,
        'city': _city.text,
        'area': _area.text,
        'lastSeenArea': _lastSeen.text,
        'description': _description.text,
        'identification': _identification.text,
        'publicationAuthorized': _authorized,
        'informationIsAccurate': _accurate,
      };
      if (_isEditing) {
        await widget.service.updateMission(
          missionId: widget.mission!.id,
          fields: fields,
          photos: _photos,
        );
      } else {
        await widget.service.createMission(fields: fields, photos: _photos);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'No se pudo guardar la misión: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          backgroundColor: _background,
          foregroundColor: _cream,
          title: Text(_isEditing ? 'EDITAR MISIÓN' : 'MISIÓN DE REENCUENTRO'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                children: [
                  const Text(
                    'Comparte solo los datos necesarios para ayudar. No publiques una dirección exacta, teléfono ni información sensible.',
                    style: TextStyle(color: _muted, height: 1.5),
                  ),
                  const SizedBox(height: 14),
                  _photoPicker(),
                  const SizedBox(height: 12),
                  _field(
                    _petName,
                    'Nombre (si se conoce)',
                    required: false,
                    maxLength: 60,
                  ),
                  _dropdown(
                    'Especie',
                    _species,
                    const {'dog': 'Perro', 'cat': 'Gato', 'other': 'Otra'},
                    (value) => setState(() => _species = value),
                  ),
                  _field(
                    _breed,
                    'Raza (opcional)',
                    required: false,
                    maxLength: 80,
                  ),
                  _dropdown(
                    'Tamaño',
                    _size,
                    const {
                      'unknown': 'No conocido',
                      'small': 'Pequeño',
                      'medium': 'Mediano',
                      'large': 'Grande',
                    },
                    (value) => setState(() => _size = value),
                  ),
                  _field(
                    _color,
                    'Color principal',
                    maxLength: 80,
                  ),
                  _dropdown(
                    'Sexo',
                    _sex,
                    const {
                      'unknown': 'No conocido',
                      'female': 'Hembra',
                      'male': 'Macho',
                    },
                    (value) => setState(() => _sex = value),
                  ),
                  _field(
                    _markings,
                    'Señas particulares (opcional)',
                    required: false,
                    maxLength: 400,
                    maxLines: 3,
                  ),
                  Card(
                    color: _panel,
                    child: ListTile(
                      leading: const Icon(Icons.event_outlined, color: _gold),
                      title: const Text(
                        'Fecha y hora aproximadas',
                        style: TextStyle(color: _cream),
                      ),
                      subtitle: Text(
                        '${_date(_missingAt)} · ${TimeOfDay.fromDateTime(_missingAt).format(context)}',
                        style: const TextStyle(color: _muted),
                      ),
                      trailing: const Icon(Icons.edit_calendar, color: _gold),
                      onTap: _selectMissingDate,
                    ),
                  ),
                  _field(_city, 'Ciudad', maxLength: 80),
                  _field(
                    _area,
                    'Zona o barrio aproximado',
                    maxLength: 100,
                    hint: 'Ej.: zona norte, barrio o sector amplio',
                  ),
                  _field(
                    _lastSeen,
                    'Último lugar donde fue vista (sin dirección exacta)',
                    maxLength: 150,
                    hint: 'Ej.: cerca de un parque o avenida principal',
                  ),
                  _field(
                    _description,
                    '¿Qué sucedió?',
                    maxLength: 800,
                    maxLines: 4,
                  ),
                  _field(
                    _identification,
                    'Collar, placa u otros elementos (opcional)',
                    required: false,
                    maxLength: 250,
                    maxLines: 2,
                  ),
                  const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.lock_outline, color: _gold),
                    title: Text(
                      'Contacto seguro dentro de la app',
                      style: TextStyle(color: _cream),
                    ),
                    subtitle: Text(
                      'No se mostrará tu correo ni tu teléfono. Los miembros podrán enviarte mensajes privados sobre esta misión.',
                      style: TextStyle(color: _muted, height: 1.4),
                    ),
                  ),
                  CheckboxListTile(
                    value: _authorized,
                    contentPadding: EdgeInsets.zero,
                    activeColor: _gold,
                    title: const Text(
                      'Autorizo publicar este aviso y las fotos seleccionadas.',
                      style: TextStyle(color: _cream, fontSize: 13),
                    ),
                    onChanged: (value) =>
                        setState(() => _authorized = value ?? false),
                  ),
                  CheckboxListTile(
                    value: _accurate,
                    contentPadding: EdgeInsets.zero,
                    activeColor: _gold,
                    title: const Text(
                      'Confirmo que la información es veraz según mi conocimiento.',
                      style: TextStyle(color: _cream, fontSize: 13),
                    ),
                    onChanged: (value) =>
                        setState(() => _accurate = value ?? false),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.campaign_outlined),
                    label: Text(
                        _isEditing ? 'GUARDAR CAMBIOS' : 'PUBLICAR MISIÓN'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: _background,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _photoPicker() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'FOTOGRAFÍAS RECIENTES (HASTA 3)',
                    style: TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _photos.length >= 3 ? null : _pickPhotos,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('AGREGAR'),
                ),
              ],
            ),
            const Text(
              'Las imágenes se optimizan y se guardan en Firestore. Máximo 200 KB por foto.',
              style: TextStyle(color: _muted, fontSize: 11),
            ),
            if (_photos.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _photos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.memory(
                          _photos[index],
                          width: 100,
                          height: 90,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton(
                          onPressed: () =>
                              setState(() => _photos.removeAt(index)),
                          icon: const Icon(Icons.close, color: Colors.white),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                            minimumSize: const Size(28, 28),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      );

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = true,
    int maxLength = 200,
    int maxLines = 1,
    String? hint,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: TextFormField(
          controller: controller,
          maxLength: maxLength,
          maxLines: maxLines,
          style: const TextStyle(color: _cream),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            counterStyle: const TextStyle(color: _muted, fontSize: 9),
            labelStyle: const TextStyle(color: _muted),
            filled: true,
            fillColor: _panel,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)),
          ),
          validator: (value) {
            final text = value?.trim() ?? '';
            if (required && text.isEmpty) return 'Completa este campo.';
            if (text.length > maxLength) return 'Reduce el texto.';
            return null;
          },
        ),
      );

  Widget _dropdown(
    String label,
    String value,
    Map<String, String> choices,
    ValueChanged<String> onChanged,
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: DropdownButtonFormField<String>(
          value: value,
          dropdownColor: _panel,
          style: const TextStyle(color: _cream),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: _muted),
            filled: true,
            fillColor: _panel,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)),
          ),
          items: choices.entries
              .map((entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ))
              .toList(),
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      );

  String _date(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _SightingEditorScreen extends StatefulWidget {
  const _SightingEditorScreen({
    required this.service,
    required this.missions,
    this.initialMission,
  });

  final LostPetService service;
  final List<LostPetMission> missions;
  final LostPetMission? initialMission;

  @override
  State<_SightingEditorScreen> createState() => _SightingEditorScreenState();
}

class _SightingEditorScreenState extends State<_SightingEditorScreen> {
  static const _background = Color(0xFF15120F);
  static const _panel = Color(0xFF211D19);
  static const _gold = Color(0xFFC6A06A);
  static const _cream = Color(0xFFE9DCCB);
  static const _muted = Color(0xFFB7AA9D);
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();
  final _description = TextEditingController();
  final _color = TextEditingController();
  final _city = TextEditingController();
  final _area = TextEditingController();
  final _direction = TextEditingController();
  final _additional = TextEditingController();
  String _species = 'dog';
  String _size = 'unknown';
  String? _missionId;
  DateTime _sightedAt = DateTime.now();
  Uint8List? _photo;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _missionId = widget.initialMission?.id;
  }

  @override
  void dispose() {
    for (final controller in [
      _description,
      _color,
      _city,
      _area,
      _direction,
      _additional,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
      if (file == null) return;
      final photo =
          await compute(compressProfileImageBytes, await file.readAsBytes());
      if (mounted) setState(() => _photo = photo);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on ArgumentError catch (error) {
      if (mounted) setState(() => _error = error.message?.toString());
    } catch (error) {
      if (mounted) setState(() => _error = 'No se pudo cargar la foto: $error');
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate:
          _sightedAt.isAfter(DateTime.now()) ? DateTime.now() : _sightedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_sightedAt),
    );
    setState(() {
      _sightedAt = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 12,
        time?.minute ?? 0,
      );
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final fields = {
        'description': _description.text,
        'species': _species,
        'color': _color.text,
        'size': _size,
        'sightedAt': _sightedAt,
        'city': _city.text,
        'area': _area.text,
        'direction': _direction.text,
        'additionalInfo': _additional.text,
      };
      await widget.service.createSighting(
        missionId: _missionId,
        fields: fields,
        photo: _photo,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'No se pudo enviar el avistamiento: $error');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _suggestionLabel(LostPetMission mission) {
    final score = lostPetMatchScore(
      missionSpecies: mission.species,
      sightingSpecies: _species,
      missionColor: mission.color,
      sightingColor: _color.text,
      missionSize: mission.size,
      sightingSize: _size,
      missionCity: mission.city,
      sightingCity: _city.text,
      missingAt: mission.missingAt,
      sightedAt: _sightedAt,
    );
    return '${score >= 6 ? 'Posible relación · ' : ''}'
        '${mission.petName.isEmpty ? 'Mascota sin nombre' : mission.petName}'
        ' · ${mission.area}, ${mission.city}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          backgroundColor: _background,
          foregroundColor: _cream,
          title: const Text('REPORTAR AVISTAMIENTO'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                children: [
                  const Text(
                    'Describe lo que viste sin acercarte ni perseguir al animal. Usa una zona aproximada; no publiques direcciones exactas.',
                    style: TextStyle(color: _muted, height: 1.5),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    color: _panel,
                    child: ListTile(
                      leading:
                          const Icon(Icons.photo_camera_outlined, color: _gold),
                      title: Text(
                        _photo == null
                            ? 'Agregar foto (opcional)'
                            : 'Foto lista',
                        style: const TextStyle(color: _cream),
                      ),
                      subtitle: const Text(
                        'Se optimiza antes de guardarla.',
                        style: TextStyle(color: _muted),
                      ),
                      trailing: const Icon(Icons.add, color: _gold),
                      onTap: _pickPhoto,
                    ),
                  ),
                  if (_photo != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child:
                          Image.memory(_photo!, height: 140, fit: BoxFit.cover),
                    ),
                  _dropdown(
                    'Especie observada',
                    _species,
                    const {'dog': 'Perro', 'cat': 'Gato', 'other': 'Otra'},
                    (value) => setState(() => _species = value),
                  ),
                  _dropdown(
                    'Tamaño',
                    _size,
                    const {
                      'unknown': 'No conocido',
                      'small': 'Pequeño',
                      'medium': 'Mediano',
                      'large': 'Grande',
                    },
                    (value) => setState(() => _size = value),
                  ),
                  _field(_color, 'Color y características visibles',
                      maxLength: 300),
                  _field(_description, 'Descripción observada',
                      maxLength: 600, lines: 4),
                  Card(
                    color: _panel,
                    child: ListTile(
                      leading: const Icon(Icons.schedule, color: _gold),
                      title: const Text(
                        'Fecha y hora del avistamiento',
                        style: TextStyle(color: _cream),
                      ),
                      subtitle: Text(
                        '${_date(_sightedAt)} · ${TimeOfDay.fromDateTime(_sightedAt).format(context)}',
                        style: const TextStyle(color: _muted),
                      ),
                      onTap: _pickDateTime,
                    ),
                  ),
                  _field(_city, 'Ciudad', maxLength: 80),
                  _field(
                    _area,
                    'Zona aproximada',
                    maxLength: 100,
                    hint: 'Barrio o sector amplio',
                  ),
                  _field(
                    _direction,
                    'Dirección en que se desplazaba (opcional)',
                    required: false,
                    maxLength: 200,
                  ),
                  _field(
                    _additional,
                    'Información adicional (opcional)',
                    required: false,
                    maxLength: 400,
                    lines: 3,
                  ),
                  if (widget.missions.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    const Text(
                      '¿Podría relacionarse con una misión activa?',
                      style: TextStyle(color: _cream),
                    ),
                    const SizedBox(height: 5),
                    DropdownButtonFormField<String>(
                      value: _missionId ?? '',
                      dropdownColor: _panel,
                      style: const TextStyle(color: _cream),
                      decoration: InputDecoration(
                        labelText: 'Posible relación, no confirmada',
                        labelStyle: const TextStyle(color: _muted),
                        filled: true,
                        fillColor: _panel,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Sin misión relacionada'),
                        ),
                        ...widget.missions.map(
                          (mission) => DropdownMenuItem(
                            value: mission.id,
                            child: Text(
                              _suggestionLabel(mission),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _missionId = value ?? ''),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Una sugerencia no confirma que sea la misma mascota. La familia deberá verificar cada pista.',
                        style: TextStyle(color: _muted, fontSize: 11),
                      ),
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.orangeAccent),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            height: 17,
                            width: 17,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_outlined),
                    label: const Text('ENVIAR AVISTAMIENTO'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: _background,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = true,
    int maxLength = 200,
    int lines = 1,
    String? hint,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: TextFormField(
          controller: controller,
          maxLength: maxLength,
          maxLines: lines,
          style: const TextStyle(color: _cream),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            labelStyle: const TextStyle(color: _muted),
            counterStyle: const TextStyle(color: _muted, fontSize: 9),
            filled: true,
            fillColor: _panel,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)),
          ),
          validator: (value) => required && (value?.trim().isEmpty ?? true)
              ? 'Completa este campo.'
              : null,
        ),
      );

  Widget _dropdown(
    String label,
    String value,
    Map<String, String> choices,
    ValueChanged<String> onChanged,
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: DropdownButtonFormField<String>(
          value: value,
          dropdownColor: _panel,
          style: const TextStyle(color: _cream),
          decoration: InputDecoration(
            labelText: label,
            labelStyle: const TextStyle(color: _muted),
            filled: true,
            fillColor: _panel,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)),
          ),
          items: choices.entries
              .map((entry) => DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ))
              .toList(),
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      );

  String _date(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: const Color(0xFFC6A06A), size: 42),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFE9DCCB),
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFB7AA9D),
                height: 1.45,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      );
}

const Map<String, String> lostPetStatusLabels = {
  'active': 'BÚSQUEDA ACTIVA',
  'sightings': 'CON AVISTAMIENTOS',
  'verifying': 'EN VERIFICACIÓN',
  'reunited': 'VOLVIÓ A CASA',
  'closed': 'CERRADA',
};

const _guideArticles = <(String, String)>[
  (
    '1. Qué hacer durante los primeros minutos',
    'Respira y anota la hora y el último lugar conocido. Revisa con cuidado el entorno inmediato y pide apoyo a personas de confianza. Mantén disponibles una foto reciente y una descripción. Si el animal está en peligro o herido, contacta servicios veterinarios o de rescate locales.'
  ),
  (
    '2. Cómo organizar una búsqueda',
    'Divide zonas amplias entre personas de confianza, acuerda una hora de actualización y registra cada lugar revisado. Evita que varias personas cubran lo mismo. Adapta el plan a la especie, el temperamento y las condiciones del área; no te pongas en riesgo.'
  ),
  (
    '3. Cómo preparar un aviso de mascota perdida',
    'Usa una foto reciente, especie, tamaño, color, señas visibles, fecha y zona aproximadas. Deja fuera algunos rasgos identificativos para poder verificar a quien reclame conocer al animal. No publiques teléfono, domicilio ni una ubicación exacta en tiempo real.'
  ),
  (
    '4. Cómo buscar y difundir información localmente',
    'Comparte el aviso en canales comunitarios de confianza y consulta veterinarias, refugios y servicios locales. Pide permiso antes de pegar avisos en espacios privados. Actualiza la información si aparecen nuevas pistas y retira o cierra el aviso cuando corresponda.'
  ),
  (
    '5. Qué hacer ante un posible avistamiento',
    'Registra hora, zona aproximada, características y dirección de desplazamiento. Envía la pista a la misión relacionada si la conoces. Un avistamiento es una pista que debe verificarse, no una identificación confirmada.'
  ),
  (
    '6. Cómo acercarse a un animal asustado',
    'No lo persigas, acorrales ni intentes sujetarlo si puede asustarse o reaccionar. Mantén distancia, evita movimientos bruscos y procura no bloquear su salida. Si está herido, agresivo o en una vía peligrosa, busca apoyo profesional local.'
  ),
  (
    '7. Cómo contactar veterinarias, refugios y rescate',
    'Llama a clínicas, refugios y organizaciones de tu zona y proporciona una descripción y foto. Confirma sus datos por canales oficiales. Las prácticas y servicios disponibles varían según la ciudad.'
  ),
  (
    '8. Cómo reconocer estafas',
    'Desconfía de quien exige dinero por adelantado a cambio de una supuesta ubicación, pide códigos o datos bancarios, o evita aportar detalles verificables. No envíes dinero ni compartas información financiera. Conserva mensajes sospechosos y repórtalos.'
  ),
  (
    '9. Qué hacer cuando vuelve a casa',
    'Confirma que está a salvo y considera una revisión veterinaria, especialmente si estuvo fuera mucho tiempo o presenta lesiones. Avisa a las personas y servicios que ayudaron, actualiza el estado de la misión y comparte una historia solo si lo deseas.'
  ),
  (
    '10. Cómo prevenir futuras desapariciones',
    'Mantén identificación actualizada, revisa cierres y correas, usa transportadoras apropiadas y conversa con tu veterinario sobre medidas adecuadas. Las necesidades dependen del animal; ninguna medida elimina todo riesgo.'
  ),
];
