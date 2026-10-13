import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:image_picker/image_picker.dart';

import 'interstitial_ads_service.dart';
import 'mischief_wall_service.dart';
import 'profile_creation_form.dart' show compressProfileImageBytes;

class MischiefWallScreen extends StatefulWidget {
  const MischiefWallScreen({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  State<MischiefWallScreen> createState() => _MischiefWallScreenState();
}

class _MischiefWallScreenState extends State<MischiefWallScreen> {
  static const _background = Color(0xFF15120F);
  static const _panel = Color(0xFF211D19);
  static const _gold = Color(0xFFC6A06A);
  static const _cream = Color(0xFFE9DCCB);
  static const _muted = Color(0xFFB7AA9D);

  final _service = MischiefWallService();
  final _picker = ImagePicker();
  late Stream<QuerySnapshot<Map<String, dynamic>>> _postsStream;
  bool _publishing = false;
  String _publishingStage = 'SUBIENDO FOTO…';
  bool _voting = false;
  bool _leaving = false;
  String _feedSort = 'recent';
  String? _error;
  final Map<String, String> _myVotes = {};

  @override
  void initState() {
    super.initState();
    _postsStream = _service.watchPosts();
  }

  void _refreshPosts() {
    setState(() {
      _error = null;
      _postsStream = _service.watchPosts();
    });
  }

  Future<void> _leaveWall() async {
    if (_leaving) return;
    _leaving = true;
    await InterstitialAdsService.showBeforeLeaving();
    if (!mounted) return;
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else {
      await Navigator.of(context).maybePop();
    }
  }

  Future<void> _createPost() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous || !user.emailVerified) {
      setState(() {
        _error = 'Inicia sesión y verifica tu correo para publicar.';
      });
      return;
    }
    XFile? image;
    try {
      image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 100,
      );
    } catch (error) {
      if (mounted)
        setState(() => _error = 'No se pudo abrir la galería: $error');
      return;
    }
    if (image == null || !mounted) return;
    Uint8List imageBytes;
    try {
      imageBytes = compressProfileImageBytes(await image.readAsBytes());
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    if (!mounted) return;

    final dogNameController = TextEditingController();
    final descriptionController = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _panel,
        title: const Text(
          'El chisme de la travesura 🐾',
          style: TextStyle(color: _cream),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: dogNameController,
              maxLength: 40,
              style: const TextStyle(color: _cream),
              decoration: const InputDecoration(
                labelText: 'Nombre del perrito',
                labelStyle: TextStyle(color: _muted),
              ),
            ),
            TextField(
              controller: descriptionController,
              maxLength: 300,
              maxLines: 3,
              style: const TextStyle(color: _cream),
              decoration: const InputDecoration(
                labelText: '¿Qué travesura hizo?',
                labelStyle: TextStyle(color: _muted),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCELAR'),
          ),
          FilledButton(
            onPressed: () {
              if (dogNameController.text.trim().isEmpty ||
                  descriptionController.text.trim().isEmpty) {
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            style: FilledButton.styleFrom(backgroundColor: _gold),
            child: const Text('PUBLICAR'),
          ),
        ],
      ),
    );
    if (submitted != true || !mounted) {
      dogNameController.dispose();
      descriptionController.dispose();
      return;
    }

    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      await _service.createPost(
        imageBytes: imageBytes,
        dogName: dogNameController.text,
        description: descriptionController.text,
        onProgress: (stage) {
          if (mounted) setState(() => _publishingStage = stage);
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡La travesura ya está en el muro!')),
      );
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _error = _publishingStage == 'GUARDANDO PUBLICACIÓN…'
            ? 'La confirmación tardó demasiado. Actualiza el muro antes de '
                'intentar publicar otra vez.'
            : 'La carga tardó demasiado. Revisa tu conexión e inténtalo '
                'de nuevo.';
      });
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('Firebase rechazó la publicación: ${error.code}');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _error =
            'No se pudo publicar (${error.code}). Revisa tu conexión y vuelve '
            'a intentarlo.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo publicar: $error');
    } finally {
      dogNameController.dispose();
      descriptionController.dispose();
      if (mounted) {
        setState(() {
          _publishing = false;
          _publishingStage = 'SUBIENDO FOTO…';
        });
      }
    }
  }

  Future<void> _vote(String postId, String choice) async {
    if (_voting) return;
    setState(() {
      _voting = true;
      _error = null;
    });
    try {
      await _service.vote(postId: postId, choice: choice);
      if (mounted) setState(() => _myVotes[postId] = choice);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo guardar tu voto: $error');
    } finally {
      if (mounted) setState(() => _voting = false);
    }
  }

  Future<void> _report(String postId) async {
    try {
      await _service.reportPost(postId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gracias. Revisaremos la publicación.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'No se pudo reportar la publicación: $error');
    }
  }

  Widget _nativeAdSlot() {
    if (kIsWeb ||
        !{
          TargetPlatform.android,
          TargetPlatform.iOS,
        }.contains(defaultTargetPlatform)) {
      return const SizedBox.shrink();
    }
    return const _MischiefNativeAd();
  }

  Widget _feedSortChip(String value, String label, IconData icon) {
    final selected = _feedSort == value;
    return ChoiceChip(
      selected: selected,
      avatar: Icon(icon, size: 16),
      label: Text(label),
      labelStyle: TextStyle(
        color: selected ? _background : _cream,
        fontSize: 11,
      ),
      selectedColor: _gold,
      backgroundColor: _panel,
      side: BorderSide(color: _gold.withValues(alpha: selected ? 0.8 : 0.3)),
      onSelected: (_) => setState(() => _feedSort = value),
    );
  }

  Widget _emptyFeed() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.pets, color: _gold, size: 54),
            const SizedBox(height: 14),
            const Text(
              '¡El muro está listo para la primera travesura!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _cream,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Comparte una foto de tu perrito y deja que la manada decida: '
              '¿inocente o culpable?',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, height: 1.4),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _publishing ? null : _createPost,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('PUBLICAR LA PRIMERA TRAVESURA'),
              style: FilledButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: _background,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _postCard(QueryDocumentSnapshot<Map<String, dynamic>> document) {
    final post = document.data();
    final vote = _myVotes[document.id];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _gold.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 13, 8, 12),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFF3B3128),
                  child: Icon(Icons.pets, color: _gold),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post['dogName'] as String? ?? 'Perrito travieso',
                        style: const TextStyle(
                          color: _cream,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Publicado por ${post['ownerName'] ?? 'la manada'}',
                        style: const TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: _muted),
                  onSelected: (value) {
                    if (value == 'report') _report(document.id);
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'report', child: Text('Reportar')),
                  ],
                ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Image.network(
              post['photoUrl'] as String? ?? '',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const ColoredBox(
                color: Color(0xFF302820),
                child: Center(
                  child: Icon(Icons.broken_image_outlined, color: _muted),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 8),
            child: Text(
              post['description'] as String? ?? '',
              style: const TextStyle(color: _cream, height: 1.4),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _voting ? null : () => _vote(document.id, 'innocent'),
                    icon: Icon(
                      vote == 'innocent'
                          ? Icons.favorite
                          : Icons.favorite_border,
                      size: 18,
                    ),
                    label: Text(
                      'Inocente 🥺 · ${post['innocentVotes'] ?? 0}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: vote == 'innocent' ? _gold : _cream,
                      side: BorderSide(
                        color: vote == 'innocent' ? _gold : _muted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed:
                        _voting ? null : () => _vote(document.id, 'guilty'),
                    icon: Icon(
                      vote == 'guilty' ? Icons.gavel : Icons.balance_outlined,
                      size: 18,
                    ),
                    label: Text(
                      'Culpable ⚖️ · ${post['guiltyVotes'] ?? 0}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: vote == 'guilty' ? _gold : _cream,
                      side: BorderSide(
                        color: vote == 'guilty' ? _gold : _muted,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leaveWall();
      },
      child: Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          backgroundColor: _background,
          foregroundColor: _cream,
          leading: IconButton(
            onPressed: _leaveWall,
            tooltip: 'Volver',
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text(
            'EL MURO DE LAS TRAVESURAS',
            style: TextStyle(fontSize: 14, letterSpacing: 1.1),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _publishing ? null : _createPost,
          backgroundColor: _gold,
          foregroundColor: _background,
          icon: _publishing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_a_photo_outlined),
          label: Text(_publishing ? _publishingStage : 'SUBIR TRAVESURA'),
        ),
        body: user == null
            ? const Center(
                child: Text(
                  'Inicia sesión para ver el muro.',
                  style: TextStyle(color: _cream),
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Mira las historias de la manada',
                            style: TextStyle(
                              color: _muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _leaveWall,
                          icon: const Icon(Icons.explore_outlined, size: 17),
                          label: const Text('SEGUIR EXPLORANDO'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _gold,
                            side: BorderSide(
                              color: _gold.withValues(alpha: 0.5),
                            ),
                            textStyle: const TextStyle(fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 42,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      scrollDirection: Axis.horizontal,
                      children: [
                        _feedSortChip(
                          'recent',
                          'Recientes',
                          Icons.schedule,
                        ),
                        const SizedBox(width: 8),
                        _feedSortChip(
                          'innocent',
                          'Más inocentes',
                          Icons.favorite_outline,
                        ),
                        const SizedBox(width: 8),
                        _feedSortChip(
                          'guilty',
                          'Más culpables',
                          Icons.gavel_outlined,
                        ),
                      ],
                    ),
                  ),
                  if (_error != null)
                    MaterialBanner(
                      content: Text(_error!),
                      backgroundColor: _panel,
                      actions: [
                        TextButton(
                          onPressed: () => setState(() => _error = null),
                          child: const Text('CERRAR'),
                        ),
                      ],
                    ),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _postsStream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.cloud_off_outlined,
                                    color: _gold,
                                    size: 42,
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No pudimos cargar las travesuras.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: _cream),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Revisa tu conexión y las reglas de '
                                    'Firestore. ${snapshot.error}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: _refreshPosts,
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('VOLVER A INTENTAR'),
                                  ),
                                  TextButton.icon(
                                    onPressed: _leaveWall,
                                    icon: const Icon(Icons.explore_outlined),
                                    label: const Text('SEGUIR EXPLORANDO'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(color: _gold),
                          );
                        }
                        final posts = [...snapshot.data!.docs];
                        if (_feedSort == 'innocent') {
                          posts.sort(
                            (a, b) => (b.data()['innocentVotes'] as num? ?? 0)
                                .compareTo(
                              a.data()['innocentVotes'] as num? ?? 0,
                            ),
                          );
                        } else if (_feedSort == 'guilty') {
                          posts.sort(
                            (a, b) => (b.data()['guiltyVotes'] as num? ?? 0)
                                .compareTo(
                              a.data()['guiltyVotes'] as num? ?? 0,
                            ),
                          );
                        }
                        if (posts.isEmpty) {
                          return _emptyFeed();
                        }
                        return ListView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 96),
                          itemCount: posts.length + (posts.length ~/ 5),
                          itemBuilder: (context, index) {
                            if ((index + 1) % 6 == 0) return _nativeAdSlot();
                            final postIndex = index - (index ~/ 6);
                            return _postCard(posts[postIndex]);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _MischiefNativeAd extends StatefulWidget {
  const _MischiefNativeAd();

  @override
  State<_MischiefNativeAd> createState() => _MischiefNativeAdState();
}

class _MischiefNativeAdState extends State<_MischiefNativeAd> {
  static const _androidTestAdUnitId = 'ca-app-pub-3940256099942544/2247696110';
  static const _iosTestAdUnitId = 'ca-app-pub-3940256099942544/3986624511';
  NativeAd? _ad;
  bool _loaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    final adUnitId = switch (defaultTargetPlatform) {
      TargetPlatform.android => const String.fromEnvironment(
          'ADMOB_NATIVE_AD_UNIT_ID_ANDROID',
          defaultValue: _androidTestAdUnitId,
        ),
      TargetPlatform.iOS => const String.fromEnvironment(
          'ADMOB_NATIVE_AD_UNIT_ID_IOS',
          defaultValue: _iosTestAdUnitId,
        ),
      _ => null,
    };
    if (adUnitId == null) {
      _failed = true;
      return;
    }
    _ad = NativeAd(
      adUnitId: adUnitId,
      request: const AdRequest(),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
        mainBackgroundColor: const Color(0xFF211D19),
        cornerRadius: 16,
        callToActionTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFF15120F),
          backgroundColor: const Color(0xFFC6A06A),
          style: NativeTemplateFontStyle.bold,
          size: 14,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFFE9DCCB),
          style: NativeTemplateFontStyle.bold,
          size: 16,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(
          textColor: const Color(0xFFB7AA9D),
          size: 12,
        ),
      ),
      listener: NativeAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _failed = true);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    return Container(
      height: 300,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF211D19),
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: _loaded && _ad != null
          ? AdWidget(ad: _ad!)
          : const Center(
              child: CircularProgressIndicator(color: Color(0xFFC6A06A)),
            ),
    );
  }
}
