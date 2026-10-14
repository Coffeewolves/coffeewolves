import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'coffee_pup_game_service.dart';
import 'garra_icon.dart';
import 'rewarded_ads_service.dart';

class CoffeePupGameScreen extends StatefulWidget {
  const CoffeePupGameScreen({super.key, required this.sessionId});

  final String sessionId;

  @override
  State<CoffeePupGameScreen> createState() => _CoffeePupGameScreenState();
}

class _CoffeePupGameScreenState extends State<CoffeePupGameScreen> {
  static const _coffee = Color(0xFF76533C);
  static const _cream = Color(0xFFC6A574);
  static const _pink = Color(0xFFF2D9D0);
  static const _sage = Color(0xFFDCE8D8);
  static const _ink = Color(0xFF33271F);
  static const _muted = Color(0xFF806F64);

  final CoffeePupGameService _service = CoffeePupGameService();
  bool _submitting = false;
  bool _showingAd = false;
  String? _feedback;
  String? _error;

  String _messageFor(Object error) {
    if (error is FirebaseFunctionsException) {
      return error.message ?? 'No se pudo completar esta acción.';
    }
    return 'No se pudo conectar con la partida. Inténtalo de nuevo.';
  }

  Future<void> _submitAnswer({
    required String questionId,
    required int answerIndex,
  }) async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _feedback = null;
      _error = null;
    });
    try {
      final result = await _service.submitAnswer(
        sessionId: widget.sessionId,
        questionId: questionId,
        answerIndex: answerIndex,
      );
      if (!mounted) return;
      final correct = result['correct'];
      final waitingForMatch = result['waitingForMatch'] == true;
      final revealed = result['revealed'] == true;
      setState(() {
        _feedback = waitingForMatch
            ? '¡Respuesta guardada! Esperando a tu match…'
            : revealed
                ? '¡Ya respondieron los dos! Mira qué eligió tu match.'
                : correct == true
                    ? '¡Correcto! ☕🐶'
                    : '¡Ups! Perdiste una vida, pero la ronda continúa.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _watchRewardedAd({
    required String uid,
    required String gameType,
    required int round,
  }) async {
    if (_showingAd) return;
    if (!RewardedAdsService.isSupported) {
      setState(() {
        _error =
            'Los anuncios recompensados solo están disponibles en Android e iOS.';
      });
      return;
    }

    setState(() {
      _showingAd = true;
      _error = null;
      _feedback = 'Cargando anuncio…';
    });
    try {
      final preferenceGame = gameType == 'preferences';
      final earned = await RewardedAdsService.showRewarded(
        uid: uid,
        customData:
            preferenceGame ? '${widget.sessionId}:$round' : widget.sessionId,
        purpose: preferenceGame
            ? RewardedAdPurpose.preferenceRound
            : RewardedAdPurpose.gameLives,
      );
      if (!mounted) return;
      setState(() {
        _feedback = earned
            ? preferenceGame
                ? 'AdMob está validando el desbloqueo de la siguiente ronda.'
                : 'AdMob está validando la recompensa. Tus vidas aparecerán al confirmarse.'
            : 'Completa el anuncio para solicitar la recompensa.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _showingAd = false);
    }
  }

  Map<String, dynamic> _stringMap(Object? value) {
    if (value is! Map) return const {};
    return Map<String, dynamic>.from(value);
  }

  Widget _playerSummary({
    required String name,
    required int lives,
    required int score,
    required int streak,
    required bool isTurn,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: isTurn ? _sage : _cream,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isTurn ? _coffee : _pink),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: List.generate(
                3,
                (index) => Icon(
                  Icons.favorite,
                  size: 16,
                  color: index < lives ? const Color(0xFFD46C73) : _pink,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '$lives vidas · $score puntos',
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
            Text(
              '🔥 $streak seguidas',
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
            if (isTurn)
              const Padding(
                padding: EdgeInsets.only(top: 5),
                child: Text(
                  'TU TURNO',
                  style: TextStyle(
                    color: _coffee,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _achievementsSection(Map<String, dynamic>? progress) {
    const medals = [
      (
        id: 'first_brew',
        title: 'Primer sorbo',
        subtitle: 'Responde bien por primera vez',
        icon: Icons.coffee,
      ),
      (
        id: 'coffee_scholar',
        title: 'Barista curioso',
        subtitle: '5 respuestas correctas',
        icon: Icons.workspace_premium,
      ),
      (
        id: 'pup_expert',
        title: 'Experto perruno',
        subtitle: '3 trivias de perritos',
        icon: BrandIcons.garra,
      ),
      (
        id: 'five_streak',
        title: 'Racha perfecta',
        subtitle: '5 respuestas seguidas',
        icon: Icons.local_fire_department,
      ),
      (
        id: 'match_minds',
        title: 'Mentes gemelas',
        subtitle: 'Coincide en 3 dilemas',
        icon: Icons.favorite,
      ),
      (
        id: 'streak_saver',
        title: 'Salvador de rachas',
        subtitle: 'Rescata una racha con AdMob',
        icon: Icons.shield,
      ),
    ];
    final earned = (progress?['achievements'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toSet();
    final rank = progress?['rank'] as String? ?? 'Aprendiz';
    final totalCorrect = progress?['totalCorrect'] is int
        ? progress!['totalCorrect'] as int
        : 0;

    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEBD7C2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium, color: _coffee),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'MIS LOGROS DE BARISTA',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              Text(
                '$totalCorrect aciertos',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Rango: $rank',
            style: const TextStyle(
              color: _coffee,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: medals.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.82,
            ),
            itemBuilder: (context, index) {
              final medal = medals[index];
              final unlocked = earned.contains(medal.id);
              return AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: unlocked
                      ? const Color(0xFFFFF1D1)
                      : const Color(0xFFF1EFEB),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: unlocked
                        ? const Color(0xFFE4BD72)
                        : const Color(0xFFE1DDD7),
                  ),
                  boxShadow: unlocked
                      ? const [
                          BoxShadow(
                            color: Color(0x40C6A06A),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ]
                      : const [],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ColorFiltered(
                      colorFilter: unlocked
                          ? const ColorFilter.mode(
                              Colors.transparent,
                              BlendMode.dst,
                            )
                          : const ColorFilter.matrix([
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0.2126, 0.7152, 0.0722, 0, 0,
                              0, 0, 0, 1, 0,
                            ]),
                      child: WolvesIcon(
                        icon: medal.icon,
                        size: 31,
                        color: unlocked
                            ? const Color(0xFFC28B36)
                            : const Color(0xFF85817B),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      medal.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: unlocked ? _ink : _muted,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      unlocked ? 'DESBLOQUEADA' : medal.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 8,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _lastReveal(Map<String, dynamic> reveal) {
    final answers = _stringMap(reveal['answers']);
    final options = (reveal['options'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList();
    final names = _stringMap(reveal['playerNames']);
    if (answers.length < 2 || options.isEmpty) return const SizedBox.shrink();

    return TweenAnimationBuilder<double>(
      key: ValueKey(reveal['questionId']),
      tween: Tween(begin: 0.92, end: 1),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      builder: (context, scale, child) => Transform.scale(
        scale: scale,
        child: Opacity(opacity: scale.clamp(0.0, 1.0), child: child),
      ),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: _pink.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reveal['matched'] is bool)
              Center(
                child: Text(
                  reveal['matched'] == true
                      ? '¡COINCIDIERON! ☕💞'
                      : 'PENSAMIENTOS DIFERENTES 🐾',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _coffee,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              )
            else
              const Text(
                'ASÍ RESPONDIERON LOS DOS 💬',
                style: TextStyle(
                  color: _coffee,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 7),
            Text(
              reveal['question'] as String? ?? '',
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final entry in answers.entries)
              if (entry.value is int &&
                  (entry.value as int) >= 0 &&
                  (entry.value as int) < options.length)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '${names[entry.key] ?? 'Tu match'} eligió: '
                    '${options[entry.value as int]}',
                    style: const TextStyle(color: _coffee, fontSize: 13),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Inicia sesión para jugar.')),
      );
    }

    return Scaffold(
      backgroundColor: _cream,
      appBar: AppBar(
        backgroundColor: _cream,
        foregroundColor: _ink,
        elevation: 0,
        title: const Text(
          'CAFÉ & PERRITOS',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _service.watchSession(widget.sessionId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No se pudo abrir la partida: ${snapshot.error}',
                    style: const TextStyle(color: _ink),
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: _coffee),
              );
            }
            final data = snapshot.data!.data();
            if (data == null) {
              return const Center(
                child: Text('La partida ya no está disponible.'),
              );
            }

            final names = _stringMap(data['playerNames']);
            final lives = _stringMap(data['lives']);
            final scores = _stringMap(data['scores']);
            final me = user.uid;
            final streaks = _stringMap(data['streaks']);
            final pendingStreaks = _stringMap(data['pendingStreaks']);
            final pendingStreak = pendingStreaks[me] is int
                ? pendingStreaks[me] as int
                : 0;
            final answeredUids =
                (data['answeredUids'] as List<dynamic>? ?? const [])
                    .whereType<String>()
                    .toSet();
            final options = (data['options'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .toList();
            final participants =
                (data['participants'] as List<dynamic>? ?? const [])
                    .whereType<String>()
                    .toList();
            if (participants.length != 2 || !participants.contains(me)) {
              return const Center(
                child: Text('No tienes acceso a esta partida.'),
              );
            }
            final otherUid = participants
                .firstWhere((participantUid) => participantUid != me);
            final gameType = data['gameType'] as String? ?? 'trivia';
            final isPreferenceGame = gameType == 'preferences';
            final isSharedChoice =
                const {'opinion', 'preference'}.contains(data['questionType']);
            final round = data['round'] is int ? data['round'] as int : 1;
            final questionsInRound = data['questionsInRound'] is int
                ? data['questionsInRound'] as int
                : 0;
            final roundLocked = data['roundLocked'] == true;
            final myLives = lives[me] is int ? lives[me] as int : 0;
            final canAnswer = !_submitting &&
                myLives > 0 &&
                !roundLocked &&
                (isSharedChoice
                    ? !answeredUids.contains(me)
                    : data['currentTurnUid'] == me);
            final reveal = _stringMap(data['lastReveal']);
            final turn = data['currentTurnUid'] == me;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEBD7C2),
                      borderRadius: BorderRadius.circular(22),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.local_cafe, color: _coffee, size: 30),
                        SizedBox(width: 10),
                        WolvesIcon(
                          icon: BrandIcons.garra,
                          color: _coffee,
                          size: 27,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            isPreferenceGame
                                ? 'Dos elecciones secretas. ¿Coincidirán?'
                                : 'Una trivia para conocerse entre sorbos y patitas.',
                            style: const TextStyle(
                              color: _ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _playerSummary(
                        name: names[me] as String? ?? 'Tú',
                        lives: myLives,
                        score: scores[me] is int ? scores[me] as int : 0,
                        streak:
                            streaks[me] is int ? streaks[me] as int : 0,
                        isTurn: !isSharedChoice && turn,
                      ),
                      const SizedBox(width: 10),
                      _playerSummary(
                        name: names[otherUid] as String? ?? 'Tu match',
                        lives:
                            lives[otherUid] is int ? lives[otherUid] as int : 0,
                        score: scores[otherUid] is int
                            ? scores[otherUid] as int
                            : 0,
                        streak: streaks[otherUid] is int
                            ? streaks[otherUid] as int
                            : 0,
                        isTurn: !isSharedChoice && !turn,
                      ),
                    ],
                  ),
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _service.watchProgress(me),
                    builder: (context, progressSnapshot) {
                      return _achievementsSection(
                        progressSnapshot.data?.data(),
                      );
                    },
                  ),
                  const SizedBox(height: 14),
                  _lastReveal(reveal),
                  if (isPreferenceGame)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'RONDA $round · $questionsInRound DE 5 PREGUNTAS',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _coffee,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x18000000),
                          blurRadius: 14,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isPreferenceGame
                              ? '¿QUÉ PREFIERES?'
                              : isSharedChoice
                                  ? 'PREGUNTA PARA CONOCERSE'
                                  : 'TU PREGUNTA',
                          style: const TextStyle(
                            color: _coffee,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          data['question'] as String? ??
                              'Pregunta no disponible',
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 19,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 15),
                        for (var index = 0; index < options.length; index++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: canAnswer
                                    ? () => _submitAnswer(
                                          questionId:
                                              data['questionId'] as String,
                                          answerIndex: index,
                                        )
                                    : null,
                                style: OutlinedButton.styleFrom(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 15,
                                    vertical: 13,
                                  ),
                                  foregroundColor: _ink,
                                  backgroundColor:
                                      _sage.withValues(alpha: 0.35),
                                  side: const BorderSide(color: _sage),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Text(
                                  '${String.fromCharCode(65 + index)}) ${options[index]}',
                                ),
                              ),
                            ),
                          ),
                        if (isSharedChoice && answeredUids.contains(me))
                          Text(
                            'Ya elegiste. Tu respuesta se revelará cuando '
                            'tu match también responda.',
                            style: TextStyle(color: _muted, fontSize: 12),
                          )
                        else if (!isSharedChoice && !turn)
                          const Text(
                            'Tu match está pensando su respuesta…',
                            style: TextStyle(color: _muted, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  if (_feedback != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _feedback!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _coffee,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFB74242)),
                    ),
                  ],
                  if (myLives == 0 || roundLocked || pendingStreak > 0) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _showingAd
                          ? null
                          : () => _watchRewardedAd(
                                uid: me,
                                gameType: gameType,
                                round: round,
                              ),
                      style: FilledButton.styleFrom(
                        backgroundColor: _coffee,
                        foregroundColor: _cream,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      icon: _showingAd
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _cream,
                              ),
                            )
                          : const Icon(Icons.play_circle_outline),
                      label: Text(
                        _showingAd
                            ? 'VALIDANDO RECOMPENSA…'
                            : isPreferenceGame && roundLocked
                                ? 'VER ANUNCIO · DESBLOQUEAR RONDA'
                                : pendingStreak > 0
                                    ? 'SALVAR RACHA · RECUPERAR VIDAS'
                                    : myLives == 0
                                ? 'VER ANUNCIO · RECUPERAR 3 VIDAS'
                                : 'VER ANUNCIO',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isPreferenceGame && roundLocked
                          ? 'Ambos podrán seguir cuando AdMob confirme el desbloqueo.'
                          : pendingStreak > 0
                              ? 'AdMob restaura tu racha y vidas para que sigas sumando hacia tus medallas.'
                              : 'La partida se reanudará cuando AdMob confirme la recompensa.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
