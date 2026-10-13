import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'garra_icon.dart';

class PackLegacyScreen extends StatefulWidget {
  const PackLegacyScreen({
    super.key,
    this.canManage = false,
    this.onBack,
    this.showBackButton = true,
  });

  final bool canManage;
  final VoidCallback? onBack;
  final bool showBackButton;

  @override
  State<PackLegacyScreen> createState() => _PackLegacyScreenState();
}

class _PackLegacyScreenState extends State<PackLegacyScreen> {
  static const _card = Color(0xFF111619);
  static const _gold = Color(0xFFC6A574);
  static const _cream = Color(0xFFF2E8D8);
  static const _muted = Color(0xFFADB3B8);

  CollectionReference<Map<String, dynamic>> get _profiles =>
      FirebaseFirestore.instance.collection('packLegacyProfiles');

  Future<void> _editProfile({
    String? documentId,
    Map<String, dynamic>? existing,
  }) async {
    final draft = await showDialog<_PackLegacyDraft>(
      context: context,
      builder: (_) => _PackLegacyProfileDialog(existing: existing),
    );
    if (draft == null || !mounted) {
      return;
    }

    try {
      final reference =
          documentId == null ? _profiles.doc() : _profiles.doc(documentId);
      await reference.set({
        ...draft.toMap(),
        if (existing == null) 'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: existing != null));
      if (mounted) _showMessage('El perfil del Legado se guardó.');
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('No se pudo guardar el Legado (${error.code}).');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        _showMessage('No se pudo guardar el perfil (${error.code}).');
      }
    } catch (error, stackTrace) {
      debugPrint('Error al guardar el Legado: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) _showMessage('No se pudo guardar el perfil.');
    }
  }

  Future<void> _deleteProfile(String documentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _card,
        title: const Text(
          'Retirar este perfil',
          style: TextStyle(color: _cream),
        ),
        content: const Text(
          'Esta historia dejará de aparecer en el Legado de la Manada.',
          style: TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('RETIRAR'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }

    try {
      await _profiles.doc(documentId).delete();
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('No se pudo retirar el perfil del Legado (${error.code}).');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        _showMessage('No se pudo retirar el perfil (${error.code}).');
      }
    } catch (error, stackTrace) {
      debugPrint('Error al retirar el perfil del Legado: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) _showMessage('No se pudo retirar el perfil.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  DateTime _sortDate(Map<String, dynamic> data) {
    final value = data['updatedAt'] ?? data['createdAt'];
    return value is Timestamp
        ? value.toDate()
        : DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.canManage
        ? _profiles.limit(50)
        : _profiles.where('published', isEqualTo: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: Row(
            children: [
              if (widget.showBackButton)
                IconButton(
                  tooltip: 'Volver atrás',
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                  color: _cream,
                ),
              const Expanded(
                child: Text(
                  'LEGADO DE LA MANADA',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _cream,
                    fontSize: 15,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (widget.canManage)
                IconButton(
                  tooltip: 'Agregar perfil legendario',
                  onPressed: _editProfile,
                  icon: const Icon(Icons.add_circle_outline),
                  color: _gold,
                )
              else
                const SizedBox(width: 48),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
          child: Column(
            children: [
              const Icon(Icons.auto_awesome, color: _gold, size: 40),
              const SizedBox(height: 10),
              const Text(
                'HISTORIAS QUE DEJAN HUELLA',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _gold,
                  fontSize: 12,
                  letterSpacing: 1.7,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                widget.canManage
                    ? 'Vitrina de miembros y mascotas destacados, seleccionados por Gerencia.'
                    : 'La puerta al universo de los miembros más destacados de Coffee Wolves.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: query.snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(22),
                child: Text(
                  'No se pudo cargar el Legado (${snapshot.error}).',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFFF8A80)),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(30),
                child: Center(
                  child: CircularProgressIndicator(color: _gold),
                ),
              );
            }
            final documents = snapshot.data!.docs.toList()
              ..sort(
                (first, second) =>
                    _sortDate(second.data()).compareTo(_sortDate(first.data())),
              );
            if (documents.isEmpty) {
              return _emptyState();
            }
            return Column(
              children: documents
                  .map((document) => _legacyCard(document.id, document.data()))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _emptyState() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 30),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF494139)),
          ),
          child: Column(
            children: [
              const Icon(Icons.auto_stories_outlined, color: _gold, size: 36),
              const SizedBox(height: 12),
              Text(
                widget.canManage
                    ? 'AÚN NO HAY PERFILES EN EL LEGADO'
                    : 'PRONTO, NUEVAS HISTORIAS DE LA MANADA',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _cream,
                  fontSize: 12,
                  letterSpacing: 0.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.canManage
                    ? 'Agrega una historia para inaugurar esta vitrina curada por Gerencia.'
                    : 'Gerencia está preparando los primeros perfiles y sus historias.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, height: 1.45),
              ),
              if (widget.canManage) ...[
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _editProfile,
                  icon: const Icon(Icons.add),
                  label: const Text('AGREGAR PERFIL'),
                ),
              ],
            ],
          ),
        ),
      );

  Widget _legacyCard(String documentId, Map<String, dynamic> data) {
    final achievements = (data['achievements'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .where((item) => item.trim().isNotEmpty);
    final photoUrl = data['photoUrl'] as String? ?? '';
    final published = data['published'] == true;
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _gold.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (photoUrl.isNotEmpty)
            Image.network(
              photoUrl,
              height: 210,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _photoPlaceholder(),
            )
          else
            _photoPlaceholder(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.workspace_premium, color: _gold, size: 19),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        data['memberName'] as String? ?? 'Miembro legendario',
                        style: const TextStyle(
                          color: _cream,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (widget.canManage)
                      PopupMenuButton<String>(
                        tooltip: 'Administrar perfil',
                        color: _card,
                        onSelected: (action) {
                          if (action == 'edit') {
                            _editProfile(
                                documentId: documentId, existing: data);
                          } else {
                            _deleteProfile(documentId);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child:
                                Text('Editar', style: TextStyle(color: _cream)),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              'Retirar',
                              style: TextStyle(color: Color(0xFFFF8A80)),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${data['petName'] ?? 'Su mascota'} · ${data['petBreed'] ?? 'Manada'}',
                  style: const TextStyle(color: _gold, fontSize: 12),
                ),
                if (widget.canManage) ...[
                  const SizedBox(height: 5),
                  Text(
                    published
                        ? 'PUBLICADO'
                        : 'BORRADOR · NO VISIBLE AL PÚBLICO',
                    style: TextStyle(
                      color: published ? const Color(0xFF8DC89B) : _muted,
                      fontSize: 9,
                      letterSpacing: 0.7,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  data['story'] as String? ?? '',
                  style: const TextStyle(
                    color: _cream,
                    height: 1.55,
                    fontSize: 12,
                  ),
                ),
                if (achievements.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text(
                    'INSIGNIAS Y LOGROS',
                    style: TextStyle(
                      color: _gold,
                      fontSize: 10,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: achievements
                        .map(
                          (achievement) => Chip(
                            avatar: const Icon(
                              Icons.stars_outlined,
                              color: _gold,
                              size: 15,
                            ),
                            label: Text(achievement),
                            backgroundColor: const Color(0xFF292D31),
                            labelStyle: const TextStyle(
                              color: _cream,
                              fontSize: 10,
                            ),
                            side: BorderSide.none,
                          ),
                        )
                        .toList(),
                  ),
                ],
                if ((data['experienceTitle'] as String? ?? '').isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF29231A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _gold.withValues(alpha: 0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'EXPERIENCIA ESPECIAL',
                          style: TextStyle(
                            color: _gold,
                            fontSize: 9,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          data['experienceTitle'] as String,
                          style: const TextStyle(
                            color: _cream,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if ((data['experienceDescription'] as String? ?? '')
                            .isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            data['experienceDescription'] as String,
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoPlaceholder() => Container(
        height: 150,
        color: const Color(0xFF292D31),
        child: const Center(
          child: const WolvesIcon(
            icon: BrandIcons.garra,
            color: _gold,
            size: 54,
          ),
        ),
      );
}

class _PackLegacyDraft {
  const _PackLegacyDraft({
    required this.memberName,
    required this.petName,
    required this.petBreed,
    required this.story,
    required this.achievements,
    required this.experienceTitle,
    required this.experienceDescription,
    required this.photoUrl,
    required this.published,
  });

  final String memberName;
  final String petName;
  final String petBreed;
  final String story;
  final List<String> achievements;
  final String experienceTitle;
  final String experienceDescription;
  final String photoUrl;
  final bool published;

  Map<String, dynamic> toMap() => {
        'memberName': memberName,
        'petName': petName,
        'petBreed': petBreed,
        'story': story,
        'achievements': achievements,
        'experienceTitle': experienceTitle,
        'experienceDescription': experienceDescription,
        'photoUrl': photoUrl,
        'published': published,
      };
}

class _PackLegacyProfileDialog extends StatefulWidget {
  const _PackLegacyProfileDialog({this.existing});

  final Map<String, dynamic>? existing;

  @override
  State<_PackLegacyProfileDialog> createState() =>
      _PackLegacyProfileDialogState();
}

class _PackLegacyProfileDialogState extends State<_PackLegacyProfileDialog> {
  static const _cream = Color(0xFFF2E8D8);
  static const _muted = Color(0xFFADB3B8);

  late final TextEditingController _memberName;
  late final TextEditingController _petName;
  late final TextEditingController _petBreed;
  late final TextEditingController _story;
  late final TextEditingController _achievements;
  late final TextEditingController _experienceTitle;
  late final TextEditingController _experienceDescription;
  late final TextEditingController _photoUrl;
  late bool _published;

  @override
  void initState() {
    super.initState();
    final data = widget.existing ?? const <String, dynamic>{};
    _memberName = TextEditingController(text: data['memberName'] as String?);
    _petName = TextEditingController(text: data['petName'] as String?);
    _petBreed = TextEditingController(text: data['petBreed'] as String?);
    _story = TextEditingController(text: data['story'] as String?);
    _achievements = TextEditingController(
      text: (data['achievements'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .join('\n'),
    );
    _experienceTitle =
        TextEditingController(text: data['experienceTitle'] as String?);
    _experienceDescription =
        TextEditingController(text: data['experienceDescription'] as String?);
    _photoUrl = TextEditingController(text: data['photoUrl'] as String?);
    _published = data['published'] == true;
  }

  @override
  void dispose() {
    _memberName.dispose();
    _petName.dispose();
    _petBreed.dispose();
    _story.dispose();
    _achievements.dispose();
    _experienceTitle.dispose();
    _experienceDescription.dispose();
    _photoUrl.dispose();
    super.dispose();
  }

  void _submit() {
    final memberName = _memberName.text.trim();
    final petName = _petName.text.trim();
    final petBreed = _petBreed.text.trim();
    final story = _story.text.trim();
    final achievementList = _achievements.text
        .split('\n')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
    final experienceTitle = _experienceTitle.text.trim();
    final experienceDescription = _experienceDescription.text.trim();
    final photoUrl = _photoUrl.text.trim();

    if (memberName.isEmpty ||
        petName.isEmpty ||
        petBreed.isEmpty ||
        story.isEmpty) {
      _showError(
          'Completa el nombre del miembro, su mascota, raza e historia.');
      return;
    }
    if (achievementList.length > 12 ||
        achievementList.any((item) => item.length > 80)) {
      _showError(
          'Agrega hasta 12 logros, con un máximo de 80 caracteres cada uno.');
      return;
    }
    final url = Uri.tryParse(photoUrl);
    if (photoUrl.isNotEmpty &&
        (url?.scheme != 'https' || url?.host.isEmpty != false)) {
      _showError('La foto debe tener una dirección HTTPS válida.');
      return;
    }

    Navigator.pop(
      context,
      _PackLegacyDraft(
        memberName: memberName,
        petName: petName,
        petBreed: petBreed,
        story: story,
        achievements: achievementList,
        experienceTitle: experienceTitle,
        experienceDescription: experienceDescription,
        photoUrl: photoUrl,
        published: _published,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111619),
      title: Text(
        widget.existing == null ? 'Agregar al Legado' : 'Editar perfil',
        style: const TextStyle(color: _cream),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field(_memberName, 'Nombre del miembro'),
              _field(_petName, 'Nombre de su mascota'),
              _field(_petBreed, 'Raza de la mascota'),
              _field(_story, 'Historia', maxLines: 5),
              _field(
                _achievements,
                'Insignias y logros (uno por línea)',
                maxLines: 3,
              ),
              _field(_experienceTitle, 'Experiencia especial'),
              _field(
                _experienceDescription,
                'Descripción de la experiencia',
                maxLines: 3,
              ),
              _field(_photoUrl, 'Foto pública (URL HTTPS, opcional)'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _published,
                title: const Text(
                  'Publicar en el Legado',
                  style: TextStyle(color: _cream),
                ),
                subtitle: const Text(
                  'Los borradores solo los ve Gerencia.',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
                onChanged: (value) => setState(() => _published = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCELAR'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('GUARDAR'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(color: _cream),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _muted),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF494139)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFFC6A574)),
          ),
        ),
      ),
    );
  }
}
