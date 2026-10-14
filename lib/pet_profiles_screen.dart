import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image_codec;
import 'package:image_picker/image_picker.dart';

import 'garra_icon.dart';

Uint8List _compressPetPhoto(Uint8List sourceBytes) {
  final decoded = image_codec.decodeImage(sourceBytes);
  if (decoded == null) {
    throw const FormatException('El archivo seleccionado no es una imagen.');
  }
  final scale = min(1.0, min(1400 / decoded.width, 1400 / decoded.height));
  final resized = image_codec.copyResize(
    decoded,
    width: max(1, (decoded.width * scale).round()),
    height: max(1, (decoded.height * scale).round()),
  );
  for (final quality in [82, 70, 58, 46, 34, 24]) {
    final bytes = image_codec.encodeJpg(resized, quality: quality);
    if (bytes.length <= 200000) return Uint8List.fromList(bytes);
  }
  throw ArgumentError('La foto supera el límite de tamaño permitido.');
}

class PetProfilesScreen extends StatefulWidget {
  const PetProfilesScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<PetProfilesScreen> createState() => _PetProfilesScreenState();
}

class _PetProfilesScreenState extends State<PetProfilesScreen> {
  static const _card = Color(0xFF111619);
  static const _cream = Color(0xFFC6A574);
  static const _muted = Color(0xFFADB3B8);
  static const _gold = Color(0xFFC6A574);

  final _imagePicker = ImagePicker();
  final _storage = FirebaseStorage.instance;
  final _firestore = FirebaseFirestore.instance;
  bool _isEditing = false;

  CollectionReference<Map<String, dynamic>> _petCollection(String uid) =>
      _firestore.collection('userPets').doc(uid).collection('pets');

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _deletePet(
    String uid,
    String petId,
    Map<String, dynamic> data,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _card,
        title: const Text('Eliminar perfil', style: TextStyle(color: _cream)),
        content: Text(
          '¿Quieres eliminar el perfil de ${data['name'] ?? 'tu mascota'}?',
          style: const TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _petCollection(uid).doc(petId).delete();
      final paths = (data['photoPaths'] as List<dynamic>? ?? const [])
          .whereType<String>();
      for (final path in paths) {
        try {
          await _storage.ref(path).delete();
        } on FirebaseException catch (error, stackTrace) {
          debugPrint('No se pudo borrar una foto de mascota (${error.code}).');
          debugPrintStack(stackTrace: stackTrace);
        }
      }
      _showMessage('Se eliminó el perfil de la mascota.');
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('No se pudo eliminar la mascota (${error.code}).');
      debugPrintStack(stackTrace: stackTrace);
      _showMessage('No se pudo eliminar el perfil (${error.code}).');
    }
  }

  Future<void> _editPet({
    required String uid,
    String? petId,
    Map<String, dynamic>? existing,
  }) async {
    if (_isEditing) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != uid || !user.emailVerified) {
      _showMessage('Verifica el correo de tu cuenta para guardar perfiles.');
      return;
    }
    setState(() => _isEditing = true);
    final nameController =
        TextEditingController(text: existing?['name'] as String? ?? '');
    final breedController =
        TextEditingController(text: existing?['breed'] as String? ?? '');
    final descriptionController = TextEditingController(
      text: existing?['description'] as String? ?? '',
    );
    final photoPaths = List<String>.from(
      existing?['photoPaths'] as List<dynamic>? ?? const [],
    );
    final photoUrls = List<String>.from(
      existing?['photoUrls'] as List<dynamic>? ?? const [],
    );
    final newPhotos = <Uint8List>[];
    final removedPaths = <String>{};
    DateTime? birthDate = (existing?['birthDate'] as Timestamp?)?.toDate();
    String? errorMessage;
    var isSaving = false;
    final formKey = GlobalKey<FormState>();

    Future<void> selectPhotos(
      BuildContext dialogContext,
      StateSetter setDialogState,
    ) async {
      try {
        final remaining =
            6 - photoPaths.length + removedPaths.length - newPhotos.length;
        if (remaining <= 0) {
          setDialogState(() => errorMessage = 'Puedes agregar hasta 6 fotos.');
          return;
        }
        final selected = await _imagePicker.pickMultiImage(
          imageQuality: 88,
          maxWidth: 1800,
          maxHeight: 1800,
        );
        if (selected.isEmpty || !dialogContext.mounted) return;
        final photos = <Uint8List>[];
        for (final file in selected.take(remaining)) {
          photos
              .add(await compute(_compressPetPhoto, await file.readAsBytes()));
        }
        if (!dialogContext.mounted) return;
        setDialogState(() {
          newPhotos.addAll(photos);
          errorMessage = null;
        });
      } catch (error, stackTrace) {
        debugPrint('No se pudieron preparar las fotos de la mascota: $error');
        debugPrintStack(stackTrace: stackTrace);
        if (dialogContext.mounted) {
          setDialogState(() {
            errorMessage =
                'No se pudieron preparar las fotos. Prueba con otras imágenes.';
          });
        }
      }
    }

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            backgroundColor: _card,
            title: Text(
              petId == null ? 'Perfil de tu mascota' : 'Editar perfil',
              style: const TextStyle(color: _cream),
            ),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: nameController,
                      maxLength: 60,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Escribe el nombre de tu mascota.'
                              : null,
                    ),
                    TextFormField(
                      controller: breedController,
                      maxLength: 80,
                      decoration: const InputDecoration(labelText: 'Raza'),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Escribe la raza de tu mascota.'
                              : null,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: isSaving
                          ? null
                          : () async {
                              final now = DateTime.now();
                              final selected = await showDatePicker(
                                context: dialogContext,
                                initialDate: birthDate ??
                                    DateTime(now.year - 1, now.month, now.day),
                                firstDate: DateTime(1900),
                                lastDate: now,
                                helpText: 'FECHA DE NACIMIENTO',
                              );
                              if (selected != null && dialogContext.mounted) {
                                setDialogState(() {
                                  birthDate = selected;
                                  errorMessage = null;
                                });
                              }
                            },
                      icon: const Icon(Icons.cake_outlined),
                      label: Text(
                        birthDate == null
                            ? 'Elegir fecha de nacimiento'
                            : 'Nacimiento: ${_formatDate(birthDate!)}',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: descriptionController,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Descripción',
                        hintText: 'Cuéntanos cómo es y qué le gusta.',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? 'Escribe una descripción.'
                              : null,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'FOTOS (HASTA 6)',
                      style: TextStyle(
                        color: _gold,
                        fontSize: 11,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var index = 0; index < photoPaths.length; index++)
                          if (!removedPaths.contains(photoPaths[index]))
                            _photoTile(
                              photoUrls[index],
                              onRemove: isSaving
                                  ? null
                                  : () => setDialogState(
                                        () =>
                                            removedPaths.add(photoPaths[index]),
                                      ),
                            ),
                        for (var index = 0; index < newPhotos.length; index++)
                          _photoTile(
                            null,
                            bytes: newPhotos[index],
                            onRemove: isSaving
                                ? null
                                : () => setDialogState(
                                      () => newPhotos.removeAt(index),
                                    ),
                          ),
                        if (photoPaths.length -
                                removedPaths.length +
                                newPhotos.length <
                            6)
                          OutlinedButton.icon(
                            onPressed: isSaving
                                ? null
                                : () => selectPhotos(
                                      dialogContext,
                                      setDialogState,
                                    ),
                            icon:
                                const Icon(Icons.add_photo_alternate_outlined),
                            label: const Text('Agregar fotos'),
                          ),
                      ],
                    ),
                    if (errorMessage != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        errorMessage!,
                        style: const TextStyle(color: Color(0xFFFF8A80)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('CANCELAR'),
              ),
              FilledButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false)) {
                          return;
                        }
                        if (birthDate == null) {
                          setDialogState(() {
                            errorMessage = 'Selecciona la fecha de nacimiento.';
                          });
                          return;
                        }
                        setDialogState(() {
                          isSaving = true;
                          errorMessage = null;
                        });
                        final reference = petId == null
                            ? _petCollection(uid).doc()
                            : _petCollection(uid).doc(petId);
                        final uploadedPaths = <String>[];
                        try {
                          final remainingPaths = <String>[];
                          final remainingUrls = <String>[];
                          for (var index = 0;
                              index < photoPaths.length;
                              index++) {
                            if (removedPaths.contains(photoPaths[index])) {
                              continue;
                            }
                            remainingPaths.add(photoPaths[index]);
                            remainingUrls.add(photoUrls[index]);
                          }
                          for (var index = 0;
                              index < newPhotos.length;
                              index++) {
                            final path =
                                'pet-profiles/$uid/${reference.id}/${DateTime.now().microsecondsSinceEpoch}_$index.jpg';
                            final photoReference = _storage.ref(path);
                            await photoReference
                                .putData(
                                  newPhotos[index],
                                  SettableMetadata(contentType: 'image/jpeg'),
                                )
                                .timeout(const Duration(seconds: 45));
                            uploadedPaths.add(path);
                            remainingPaths.add(path);
                            remainingUrls.add(
                              await photoReference
                                  .getDownloadURL()
                                  .timeout(const Duration(seconds: 15)),
                            );
                          }
                          final storedDate = DateTime(
                            birthDate!.year,
                            birthDate!.month,
                            birthDate!.day,
                          );
                          await reference.set({
                            'name': nameController.text.trim(),
                            'breed': breedController.text.trim(),
                            'birthDate': Timestamp.fromDate(storedDate),
                            'description': descriptionController.text.trim(),
                            'photoPaths': remainingPaths,
                            'photoUrls': remainingUrls,
                            if (existing == null)
                              'createdAt': FieldValue.serverTimestamp(),
                            'updatedAt': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: existing != null));
                          for (final removedPath in removedPaths) {
                            try {
                              await _storage.ref(removedPath).delete();
                            } on FirebaseException catch (error, stackTrace) {
                              debugPrint(
                                'No se pudo borrar una foto retirada (${error.code}).',
                              );
                              debugPrintStack(stackTrace: stackTrace);
                            }
                          }
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          _showMessage('Perfil de mascota guardado.');
                        } on FirebaseException catch (error, stackTrace) {
                          debugPrint(
                            'No se pudo guardar el perfil de mascota (${error.code}).',
                          );
                          debugPrintStack(stackTrace: stackTrace);
                          for (final path in uploadedPaths) {
                            try {
                              await _storage.ref(path).delete();
                            } on FirebaseException catch (cleanupError) {
                              debugPrint(
                                'No se pudo limpiar la foto subida (${cleanupError.code}).',
                              );
                            }
                          }
                          if (dialogContext.mounted) {
                            setDialogState(() {
                              isSaving = false;
                              errorMessage =
                                  'No se pudo guardar (${error.code}). Revisa la conexión e inténtalo otra vez.';
                            });
                          }
                        } catch (error, stackTrace) {
                          debugPrint(
                            'Error al guardar el perfil de mascota: $error',
                          );
                          debugPrintStack(stackTrace: stackTrace);
                          for (final path in uploadedPaths) {
                            try {
                              await _storage.ref(path).delete();
                            } on FirebaseException catch (cleanupError) {
                              debugPrint(
                                'No se pudo limpiar la foto subida (${cleanupError.code}).',
                              );
                            }
                          }
                          if (dialogContext.mounted) {
                            setDialogState(() {
                              isSaving = false;
                              errorMessage = 'No se pudo guardar el perfil.';
                            });
                          }
                        }
                      },
                child: isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('GUARDAR PERFIL'),
              ),
            ],
          ),
        ),
      );
    } finally {
      nameController.dispose();
      breedController.dispose();
      descriptionController.dispose();
      if (mounted) setState(() => _isEditing = false);
    }
  }

  Widget _photoTile(
    String? url, {
    Uint8List? bytes,
    required VoidCallback? onRemove,
  }) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: bytes != null
              ? Image.memory(bytes, width: 72, height: 72, fit: BoxFit.cover)
              : Image.network(
                  url ?? '',
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: 72,
                    height: 72,
                    child: const WolvesIcon(
                      icon: BrandIcons.garra,
                      color: _cream,
                    ),
                  ),
                ),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: IconButton(
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.cancel, color: Color(0xFFC6A574), size: 18),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Volver atrás',
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                color: _cream,
              ),
              const Expanded(
                child: Text(
                  'MIS MASCOTAS',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _cream,
                    letterSpacing: 2,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 10),
          if (user == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Inicia sesión para ver y crear perfiles de tus mascotas.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted),
              ),
            )
          else ...[
            OutlinedButton.icon(
              onPressed: _isEditing ? null : () => _editPet(uid: user.uid),
              icon: const Icon(Icons.add),
              label: const Text('AGREGAR MASCOTA'),
            ),
            const SizedBox(height: 14),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _petCollection(user.uid).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'No se pudieron cargar tus mascotas (${snapshot.error}).',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFFF8A80)),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: CircularProgressIndicator(color: _gold),
                    ),
                  );
                }
                final pets = snapshot.data!.docs.toList()
                  ..sort((first, second) =>
                      (first.data()['name'] as String? ?? '')
                          .compareTo(second.data()['name'] as String? ?? ''));
                if (pets.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 30, horizontal: 18),
                    child: Column(
                      children: [
                        const WolvesIcon(
                          icon: BrandIcons.garra,
                          size: 40,
                          color: _gold,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'AÚN NO HAY PERFILES DE MASCOTAS',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _cream, letterSpacing: 1),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Agrega un perfil para guardar su raza, cumpleaños, descripción y fotos.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _muted, height: 1.4),
                        ),
                      ],
                    ),
                  );
                }
                return Column(
                  children: pets
                      .map((document) => _petCard(
                            uid: user.uid,
                            petId: document.id,
                            data: document.data(),
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _petCard({
    required String uid,
    required String petId,
    required Map<String, dynamic> data,
  }) {
    final birthDate = (data['birthDate'] as Timestamp?)?.toDate();
    final photoUrls = (data['photoUrls'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList();
    return Card(
      color: _card,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: const Color(0xFF4A392F),
                  backgroundImage:
                      photoUrls.isEmpty ? null : NetworkImage(photoUrls.first),
                  child: photoUrls.isEmpty
                      ? const WolvesIcon(
                          icon: BrandIcons.garra,
                          color: _cream,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['name'] as String? ?? 'Mascota',
                        style: const TextStyle(
                          color: _cream,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${data['breed'] as String? ?? 'Raza no indicada'}'
                        '${birthDate == null ? '' : ' · ${_formatDate(birthDate)}'}',
                        style: const TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'edit') {
                      _editPet(uid: uid, petId: petId, existing: data);
                    } else {
                      _deletePet(uid, petId, data);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Editar perfil')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Eliminar perfil'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              data['description'] as String? ?? '',
              style: const TextStyle(color: _cream, height: 1.4),
            ),
            if (photoUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: photoUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      photoUrls[index],
                      width: 130,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        width: 130,
                        child: Icon(Icons.broken_image_outlined, color: _muted),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime date) => '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}/'
    '${date.year.toString().padLeft(4, '0')}';
