const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const {
  getFirestore,
  FieldValue,
  Timestamp,
} = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');
const { getStorage } = require('firebase-admin/storage');
const { randomUUID, createHash, createPublicKey, verify } = require('crypto');
const { HttpsError, logger } = require('firebase-functions');
const { defineSecret, defineString } = require('firebase-functions/params');
const { onCall, onRequest } = require('firebase-functions/v2/https');
const {
  onDocumentCreated,
  onDocumentUpdated,
} = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');

initializeApp();

const db = getFirestore();
const region = 'us-central1';
const orderTitle = 'Coffee Wolves · Nueva comanda';
const visionApiKey = defineSecret('GOOGLE_CLOUD_VISION_API_KEY');
const admobGameRewardedAdUnitIds = defineString(
  'ADMOB_GAME_REWARDED_AD_UNIT_IDS',
);
const admobPreferenceRewardedAdUnitIds = defineString(
  'ADMOB_PREFERENCE_REWARDED_AD_UNIT_IDS',
);
const startingGameLives = 3;
const rewardedGameLives = 3;
const coffeePupQuestions = [
  {
    id: 'coffee-01',
    type: 'trivia',
    question: '¿Qué método prepara café haciendo pasar agua por un filtro?',
    options: ['Prensa francesa', 'V60', 'Moka', 'Cold brew'],
    answerIndex: 1,
  },
  {
    id: 'dog-01',
    type: 'trivia',
    question: '¿Cuál de estas razas suele tener el hocico chato?',
    options: ['Galgo', 'Pug', 'Border collie', 'Dálmata'],
    answerIndex: 1,
  },
  {
    id: 'visual-01',
    type: 'trivia',
    question: '🫘 + 💧 + 🔥 = ¿qué se obtiene?',
    options: ['Un espresso', 'Un té helado', 'Leche espumada', 'Un croissant'],
    answerIndex: 0,
  },
  {
    id: 'coffee-02',
    type: 'trivia',
    question: '¿Qué ingrediente da su nombre al café con leche vaporizada?',
    options: ['Agua tónica', 'Leche', 'Chocolate', 'Canela'],
    answerIndex: 1,
  },
  {
    id: 'dog-02',
    type: 'trivia',
    question: '¿Qué raza es conocida por sus manchas negras o marrones?',
    options: ['Dálmata', 'Shiba inu', 'Caniche', 'Chihuahua'],
    answerIndex: 0,
  },
  {
    id: 'visual-02',
    type: 'trivia',
    question: '☕ + 🧊 + ☀️ = ¿qué bebida va mejor en un día caluroso?',
    options: ['Café turco', 'Café helado', 'Cappuccino caliente', 'Moka'],
    answerIndex: 1,
  },
  {
    id: 'coffee-opinion-01',
    type: 'opinion',
    question:
      'Si tu match fuera un tipo de café, ¿cuál sería según su personalidad?',
    options: [
      'Espresso (intenso y directo)',
      'Capuccino (dulce y equilibrado)',
      'Frappuccino (divertido y relajado)',
    ],
  },
  {
    id: 'dog-opinion-01',
    type: 'opinion',
    question:
      '¿Qué raza describe mejor cómo te comportas cuando estás enamorado?',
    options: [
      'Golden Retriever (fiel y cariñoso)',
      'Husky (rebelde y gritón)',
      'Chihuahua (celoso pero tierno)',
    ],
  },
  {
    id: 'preference-01',
    type: 'preference',
    gameType: 'preferences',
    question: '¿Qué prefieres para la primera cita?',
    options: [
      'Cafetería aesthetic, vinitos y música jazz',
      'Café al paso y paseo de perritos en el parque',
    ],
  },
  {
    id: 'preference-02',
    type: 'preference',
    gameType: 'preferences',
    question: '¿Qué plan cafetera elegirías para una tarde libre?',
    options: [
      'Probar un espresso nuevo en una barra tranquila',
      'Pedir un frappuccino y sentarse a mirar a los perritos',
    ],
  },
  {
    id: 'preference-03',
    type: 'preference',
    gameType: 'preferences',
    question: '¿Cómo sería el paseo perfecto con tu perrito?',
    options: [
      'Ruta larga por el parque con muchas paradas a oler',
      'Vuelta corta y luego siesta juntos en una cafetería pet-friendly',
    ],
  },
  {
    id: 'preference-04',
    type: 'preference',
    gameType: 'preferences',
    question: '¿Qué pedirías para compartir en una cita?',
    options: [
      'Dos capuccinos y algo dulce',
      'Un cold brew y un snack para el perrito',
    ],
  },
  {
    id: 'preference-05',
    type: 'preference',
    gameType: 'preferences',
    question: '¿Qué te conquista más de una cita?',
    options: [
      'Una conversación profunda con café caliente',
      'Una aventura espontánea con perritos y café para llevar',
    ],
  },
];
const coffeePupAchievements = [
  { id: 'first_brew', icon: 'coffee', title: 'Primer sorbo' },
  { id: 'coffee_scholar', icon: 'workspace_premium', title: 'Barista curioso' },
  { id: 'pup_expert', icon: 'pets', title: 'Experto perruno' },
  { id: 'five_streak', icon: 'local_fire_department', title: 'Racha perfecta' },
  { id: 'match_minds', icon: 'favorite', title: 'Mentes gemelas' },
  { id: 'streak_saver', icon: 'shield', title: 'Salvador de rachas' },
];

function coffeePupRank(totalCorrect) {
  if (totalCorrect >= 50) return 'Maestro del Café';
  if (totalCorrect >= 20) return 'Barista Jefe';
  if (totalCorrect >= 5) return 'Barista';
  return 'Aprendiz';
}

function buildCoffeePupProgress(snapshot, increments = {}) {
  const old = snapshot.exists ? snapshot.data() : {};
  const totalCorrect = (old.totalCorrect || 0) + (increments.totalCorrect || 0);
  const dogCorrect = (old.dogCorrect || 0) + (increments.dogCorrect || 0);
  const preferenceMatches =
    (old.preferenceMatches || 0) + (increments.preferenceMatches || 0);
  const currentStreak =
    increments.currentStreak ?? old.currentStreak ?? 0;
  const bestStreak = Math.max(
    old.bestStreak || 0,
    increments.bestStreak || 0,
    currentStreak,
  );
  const streakSaves = (old.streakSaves || 0) + (increments.streakSaves || 0);
  const achievements = new Set(old.achievements || []);
  if (totalCorrect >= 1) achievements.add('first_brew');
  if (totalCorrect >= 5) achievements.add('coffee_scholar');
  if (dogCorrect >= 3) achievements.add('pup_expert');
  if (bestStreak >= 5) achievements.add('five_streak');
  if (preferenceMatches >= 3) achievements.add('match_minds');
  if (streakSaves >= 1) achievements.add('streak_saver');

  return {
    totalCorrect,
    dogCorrect,
    preferenceMatches,
    currentStreak,
    bestStreak,
    streakSaves,
    achievements: [...achievements],
    rank: coffeePupRank(totalCorrect),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

let cachedAdMobKeys;
let cachedAdMobKeysExpiresAt = 0;

async function getAdMobVerificationKeys() {
  if (cachedAdMobKeys && Date.now() < cachedAdMobKeysExpiresAt) {
    return cachedAdMobKeys;
  }

  const response = await fetch(
    'https://www.gstatic.com/admob/reward/verifier-keys.json',
  );
  if (!response.ok) {
    throw new Error(`AdMob keys request failed with ${response.status}.`);
  }
  const { keys } = await response.json();
  if (!Array.isArray(keys) || keys.length === 0) {
    throw new Error('AdMob returned no SSV verification keys.');
  }

  cachedAdMobKeys = new Map(
    keys.map((key) => [
      String(key.keyId),
      createPublicKey({
        key: Buffer.from(key.base64, 'base64'),
        format: 'der',
        type: 'spki',
      }),
    ]),
  );
  cachedAdMobKeysExpiresAt = Date.now() + 23 * 60 * 60 * 1000;
  return cachedAdMobKeys;
}

async function verifyAdMobSsvCallback(req) {
  const query = String(req.originalUrl || req.url || '').split('?')[1] || '';
  const signatureMarker = '&signature=';
  const keyIdMarker = '&key_id=';
  const signatureIndex = query.lastIndexOf(signatureMarker);
  const keyIdIndex = query.indexOf(keyIdMarker, signatureIndex);
  if (
    signatureIndex < 0 ||
    keyIdIndex < signatureIndex ||
    query.indexOf('&', keyIdIndex + keyIdMarker.length) !== -1
  ) {
    return null;
  }

  const signedData = query.slice(0, signatureIndex);
  const params = new URLSearchParams(query);
  const key = (await getAdMobVerificationKeys()).get(params.get('key_id'));
  if (!key) return null;

  const signature = Buffer.from(
    params.get('signature').replace(/-/g, '+').replace(/_/g, '/'),
    'base64',
  );
  return verify('sha256', Buffer.from(signedData, 'utf8'), key, signature)
    ? params
    : null;
}

exports.adMobRewardedSsv = onRequest({ region }, async (req, res) => {
  if (req.method !== 'GET') {
    res.status(405).send('Method not allowed.');
    return;
  }

  try {
    const params = await verifyAdMobSsvCallback(req);
    if (!params) {
      res.status(400).send('Invalid AdMob signature.');
      return;
    }

    const uid = params.get('user_id');
    const customData = params.get('custom_data') || '';
    const transactionId = params.get('transaction_id');
    const adUnit = params.get('ad_unit');
    const gameAdUnitIds = admobGameRewardedAdUnitIds.value()
      .split(',')
      .map((id) => id.trim())
      .filter(Boolean);
    const preferenceAdUnitIds = admobPreferenceRewardedAdUnitIds.value()
      .split(',')
      .map((id) => id.trim())
      .filter(Boolean);
    const customDataParts = customData.split(':');
    const isGameReward =
      gameAdUnitIds.includes(adUnit) &&
      customDataParts.length === 1 &&
      /^[a-f0-9-]{36}$/i.test(customDataParts[0]);
    const isPreferenceReward =
      preferenceAdUnitIds.includes(adUnit) &&
      customDataParts.length === 2 &&
      /^[a-f0-9-]{36}$/i.test(customDataParts[0]) &&
      /^\d{1,6}$/.test(customDataParts[1]);
    const sessionId =
      isGameReward || isPreferenceReward ? customDataParts[0] : null;
    const roundString = isPreferenceReward ? customDataParts[1] : null;
    if (
      !uid ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(uid) ||
      !transactionId ||
      !/^[a-fA-F0-9]{32,128}$/.test(transactionId) ||
      !isGameReward && !isPreferenceReward ||
      isGameReward &&
        (params.get('reward_amount') !== String(rewardedGameLives) ||
          params.get('reward_item') !== 'game_lives') ||
      isPreferenceReward &&
        (params.get('reward_amount') !== '1' ||
          params.get('reward_item') !== 'preference_round')
    ) {
      res.status(400).send('Invalid AdMob reward details.');
      return;
    }

    const eventRef = db.collection('admobRewardEvents').doc(transactionId);
    await db.runTransaction(async (transaction) => {
      const event = await transaction.get(eventRef);
      if (event.exists) return;

      if (isGameReward) {
        const sessionRef = db.collection('game_sessions').doc(sessionId);
        const session = await transaction.get(sessionRef);
        if (
          !session.exists ||
          !session.data().participants.includes(uid) ||
          session.data().status !== 'active'
        ) {
          throw new Error('Rewarded game session is unavailable.');
        }
        const lives = session.data().lives;
        const currentLives = lives?.[uid];
        if (!Number.isSafeInteger(currentLives) || currentLives < 0) {
          throw new Error('Rewarded player lives are invalid.');
        }
        const progressRef = db.collection('coffeePupProfiles').doc(uid);
        const progressSnapshot = await transaction.get(progressRef);
        const pendingStreak = session.data().pendingStreaks?.[uid] || 0;
        const restoredStreak = Math.max(
          session.data().streaks?.[uid] || 0,
          pendingStreak,
        );
        const progress = buildCoffeePupProgress(progressSnapshot, {
          currentStreak: restoredStreak,
          bestStreak: restoredStreak,
          streakSaves: pendingStreak > 0 ? 1 : 0,
        });
        const pendingStreaks = {
          ...(session.data().pendingStreaks || {}),
        };
        delete pendingStreaks[uid];
        transaction.update(sessionRef, {
          [`lives.${uid}`]: Math.min(
            startingGameLives,
            currentLives + rewardedGameLives,
          ),
          [`streaks.${uid}`]: restoredStreak,
          pendingStreaks,
          updatedAt: FieldValue.serverTimestamp(),
        });
        transaction.set(progressRef, progress, { merge: true });
      } else {
        const sessionRef = db.collection('game_sessions').doc(sessionId);
        const session = await transaction.get(sessionRef);
        if (
          !session.exists ||
          !session.data().participants.includes(uid) ||
          session.data().gameType !== 'preferences'
        ) {
          throw new Error('Rewarded preference game is unavailable.');
        }
        const currentRound = Number(roundString);
        if (
          session.data().roundLocked !== true ||
          session.data().round !== currentRound
        ) {
          return;
        }
        const nextQuestion = publicCoffeePupQuestion(0, 'preferences');
        transaction.update(sessionRef, {
          round: currentRound + 1,
          questionsInRound: 0,
          roundLocked: false,
          questionIndex: 0,
          questionId: questionInstanceId(nextQuestion),
          questionType: nextQuestion.type,
          question: nextQuestion.question,
          options: nextQuestion.options,
          answeredUids: [],
          updatedAt: FieldValue.serverTimestamp(),
        });
      }

      transaction.create(eventRef, {
        uid,
        adUnit,
        rewardType,
        rewardAmount: Number(params.get('reward_amount')),
        sessionId: isGameReward || isPreferenceReward ? sessionId : null,
        round: isPreferenceReward ? Number(roundString) : null,
        createdAt: FieldValue.serverTimestamp(),
      });
    });

    res.status(200).send('OK');
  } catch (error) {
    logger.error('AdMob SSV callback failed.', error);
    res.status(500).send('Reward verification temporarily failed.');
  }
});

exports.voteMischiefPost = onCall({ region }, async (request) => {
  if (!request.auth || request.auth.token.firebase.sign_in_provider === 'anonymous') {
    throw new HttpsError('unauthenticated', 'Inicia sesión para votar.');
  }
  const postId = request.data?.postId;
  const choice = request.data?.choice;
  if (
    typeof postId !== 'string' ||
    !/^[A-Za-z0-9_-]{20,80}$/.test(postId) ||
    !['innocent', 'guilty'].includes(choice)
  ) {
    throw new HttpsError('invalid-argument', 'El voto no es válido.');
  }

  const postRef = db.collection('mischiefPosts').doc(postId);
  const voteRef = postRef.collection('votes').doc(request.auth.uid);
  await db.runTransaction(async (transaction) => {
    const [post, vote] = await Promise.all([
      transaction.get(postRef),
      transaction.get(voteRef),
    ]);
    if (!post.exists) {
      throw new HttpsError('not-found', 'La publicación ya no está disponible.');
    }
    const previousChoice = vote.data()?.choice;
    if (previousChoice === choice) return;
    const data = post.data();
    const innocentVotes = data.innocentVotes ?? 0;
    const guiltyVotes = data.guiltyVotes ?? 0;
    if (
      !Number.isSafeInteger(innocentVotes) ||
      innocentVotes < 0 ||
      !Number.isSafeInteger(guiltyVotes) ||
      guiltyVotes < 0
    ) {
      throw new HttpsError('internal', 'El conteo de votos no es válido.');
    }

    transaction.update(postRef, {
      innocentVotes:
        innocentVotes +
        (choice === 'innocent' ? 1 : 0) -
        (previousChoice === 'innocent' ? 1 : 0),
      guiltyVotes:
        guiltyVotes +
        (choice === 'guilty' ? 1 : 0) -
        (previousChoice === 'guilty' ? 1 : 0),
    });
    transaction.set(voteRef, {
      choice,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
  return { success: true };
});

const matchIntentions = {
  friendship: ['friendship'],
  romantic: ['romantic'],
  both: ['friendship', 'romantic'],
};

function matchPairId(uidA, uidB) {
  return createHash('sha256')
    .update([uidA, uidB].sort().join(':'))
    .digest('hex');
}

function intentionsAreCompatible(intentA, intentB) {
  const acceptedA = Object.hasOwn(matchIntentions, intentA)
    ? matchIntentions[intentA]
    : [];
  const acceptedB = Object.hasOwn(matchIntentions, intentB)
    ? matchIntentions[intentB]
    : [];
  return acceptedA.some((intent) => acceptedB.includes(intent));
}

function parseBirthday(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new HttpsError(
      'invalid-argument',
      'Selecciona una fecha de nacimiento válida.',
    );
  }
  const [year, month, day] = value.split('-').map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (
    date.getUTCFullYear() !== year ||
    date.getUTCMonth() !== month - 1 ||
    date.getUTCDate() !== day
  ) {
    throw new HttpsError(
      'invalid-argument',
      'Selecciona una fecha de nacimiento válida.',
    );
  }
  return { year, month, day, date };
}

function isAdultBirthday(year, month, day) {
  const now = new Date();
  const currentYear = now.getUTCFullYear();
  const currentMonth = now.getUTCMonth() + 1;
  const currentDay = now.getUTCDate();
  const age =
    currentYear -
    year -
    (currentMonth < month ||
    (currentMonth === month && currentDay < day)
      ? 1
      : 0);
  return age >= 18;
}

exports.saveBirthdayDetails = onCall({ region }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Inicia sesión para continuar.');
  }
  const { year, month, day } = parseBirthday(request.data?.birthDate);
  if (!isAdultBirthday(year, month, day)) {
    throw new HttpsError(
      'permission-denied',
      'Debes tener al menos 18 años para guardar esta fecha.',
    );
  }
  if (typeof request.data?.birthdayMarketingConsent !== 'boolean') {
    throw new HttpsError(
      'invalid-argument',
      'Indica si aceptas recibir una invitación de cumpleaños.',
    );
  }

  const profileRef = db.collection('users').doc(request.auth.uid);
  await db.runTransaction(async (transaction) => {
    const profileSnapshot = await transaction.get(profileRef);
    if (!profileSnapshot.exists) {
      throw new HttpsError(
        'failed-precondition',
        'No se encontró tu perfil de Coffee Wolves.',
      );
    }
    const existingValue =
      profileSnapshot.data().birthDate ||
      profileSnapshot.data().dateOfBirth;
    if (existingValue) {
      const existingDate =
        existingValue instanceof Date
          ? existingValue
          : typeof existingValue.toDate === 'function'
            ? existingValue.toDate()
            : new Date(existingValue);
      if (
        !Number.isFinite(existingDate.getTime()) ||
        existingDate.getUTCFullYear() !== year ||
        existingDate.getUTCMonth() + 1 !== month ||
        existingDate.getUTCDate() !== day
      ) {
        throw new HttpsError(
          'failed-precondition',
          'La fecha ya registrada no se puede cambiar desde la app. Contacta a Coffee Wolves para corregirla.',
        );
      }
    }
    transaction.set(
      profileRef,
      {
        birthDate: `${String(year).padStart(4, '0')}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`,
        birthMonth: month,
        birthDay: day,
        birthdayMarketingConsent: request.data.birthdayMarketingConsent,
        birthdayConsentUpdatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
  return { saved: true };
});

async function requireMatchAccount(uid) {
  const account = await getAuth().getUser(uid);
  if (!account.emailVerified) {
    throw new HttpsError(
      'failed-precondition',
      'Verifica tu correo para usar WOLVES MATCH.',
    );
  }
  const profileSnapshot = await db.collection('users').doc(uid).get();
  const profile = profileSnapshot.data();
  if (!profileSnapshot.exists || !profile) {
    throw new HttpsError(
      'failed-precondition',
      'Completa tu perfil antes de entrar a WOLVES MATCH.',
    );
  }
  const birthDate = Date.parse(profile.birthDate || profile.dateOfBirth || '');
  if (!Number.isFinite(birthDate)) {
    throw new HttpsError(
      'failed-precondition',
      'Completa tu fecha de nacimiento para confirmar que tienes 18 años.',
    );
  }
  const today = new Date();
  const birthday = new Date(birthDate);
  let age = today.getFullYear() - birthday.getFullYear();
  if (
    today.getMonth() < birthday.getMonth() ||
    (today.getMonth() === birthday.getMonth() &&
      today.getDate() < birthday.getDate())
  ) {
    age -= 1;
  }
  if (age < 18) {
    throw new HttpsError(
      'permission-denied',
      'WOLVES MATCH está disponible solo para miembros mayores de 18 años.',
    );
  }
  return { account, profile };
}

function validateMatchProfile(data) {
  const intention = data?.intention;
  const displayName =
    typeof data?.displayName === 'string' ? data.displayName.trim() : '';
  const bio = typeof data?.bio === 'string' ? data.bio.trim() : '';
  const interests = data?.interests;
  const profileText = `${displayName}\n${bio}`;
  const includesPrivateContact =
    /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i.test(profileText) ||
    /\+?\d[\d\s().-]{8,}\d/.test(profileText) ||
    /\b-?\d{1,3}\.\d{3,}\s*[,;]\s*-?\d{1,3}\.\d{3,}\b/.test(profileText) ||
    /\b(?:calle|av(?:enida)?|pasaje|carretera|street|avenue)\s+(?:[a-z]+\s+)?\d+/i.test(
      profileText,
    );
  const allowedInterests = new Set([
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
  ]);
  if (
    !Object.hasOwn(matchIntentions, intention) ||
    displayName.length < 2 ||
    displayName.length > 40 ||
    bio.length > 180 ||
    includesPrivateContact ||
    !Array.isArray(interests) ||
    interests.length > 5 ||
    interests.some((interest) => !allowedInterests.has(interest)) ||
    new Set(interests).size !== interests.length
  ) {
    throw new HttpsError(
      'invalid-argument',
      includesPrivateContact
        ? 'No incluyas correo, teléfono ni ubicación exacta en el perfil.'
        : 'Revisa el nombre, la intención y los intereses de tu perfil.',
    );
  }
  return { intention, displayName, bio, interests };
}

function publicMatchProfile(profile) {
  return {
    id: profile.matchPublicId,
    displayName: profile.displayName,
    bio: profile.bio,
    interests: profile.interests,
    intention: profile.intention,
  };
}

async function resolveMatchPublicId(publicId, requesterUid) {
  if (typeof publicId !== 'string' || publicId.length > 80) {
    throw new HttpsError('invalid-argument', 'Perfil no válido.');
  }
  const mapping = await db.collection('wolvesMatchPublicIds').doc(publicId).get();
  const targetUid = mapping.data()?.uid;
  if (!targetUid || targetUid === requesterUid) {
    throw new HttpsError('not-found', 'Este perfil ya no está disponible.');
  }
  return targetUid;
}

function questionsForGameType(gameType) {
  return coffeePupQuestions.filter((question) =>
    gameType === 'preferences'
      ? question.gameType === 'preferences'
      : question.gameType !== 'preferences',
  );
}

function publicCoffeePupQuestion(index, gameType = 'trivia') {
  const questionBank = questionsForGameType(gameType);
  const { id, type, question, options } =
    questionBank[index % questionBank.length];
  return { id, type, question, options };
}

function questionInstanceId(question) {
  return `${question.id}-${randomUUID()}`;
}

exports.startCoffeePupGame = onCall({ region }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Inicia sesión para continuar.');
  }
  const uid = request.auth.uid;
  const gameType = request.data?.gameType ?? 'trivia';
  if (!['trivia', 'preferences'].includes(gameType)) {
    throw new HttpsError('invalid-argument', 'El tipo de juego no es válido.');
  }
  await requireMatchAccount(uid);
  const otherUid = await resolveMatchPublicId(request.data?.profileId, uid);
  const pairId = matchPairId(uid, otherUid);
  const pairRef = db.collection('wolvesMatchPairs').doc(pairId);
  const ownRef = db.collection('wolvesMatchParticipants').doc(uid);
  const otherRef = db.collection('wolvesMatchParticipants').doc(otherUid);
  const ownBlockRef = db
    .collection('wolvesMatchBlocks')
    .doc(uid)
    .collection('users')
    .doc(otherUid);
  const otherBlockRef = db
    .collection('wolvesMatchBlocks')
    .doc(otherUid)
    .collection('users')
    .doc(uid);

  return db.runTransaction(async (transaction) => {
    const [pair, own, other, ownBlock, otherBlock] = await Promise.all([
      transaction.get(pairRef),
      transaction.get(ownRef),
      transaction.get(otherRef),
      transaction.get(ownBlockRef),
      transaction.get(otherBlockRef),
    ]);
    if (
      !pair.exists ||
      pair.data().status !== 'mutual' ||
      !pair.data().participants.includes(uid) ||
      !pair.data().participants.includes(otherUid) ||
      !own.exists ||
      !other.exists ||
      own.data().status !== 'active' ||
      other.data().status !== 'active' ||
      ownBlock.exists ||
      otherBlock.exists
    ) {
      throw new HttpsError(
        'failed-precondition',
        'El juego solo está disponible para una conexión mutua activa.',
      );
    }

    const activeSessionIds = pair.data().activeGameSessionIds || {};
    const existingSessionId =
      activeSessionIds[gameType] ||
      (gameType === 'trivia' ? pair.data().activeGameSessionId : null);
    if (
      typeof existingSessionId === 'string' &&
      /^[a-f0-9-]{36}$/i.test(existingSessionId)
    ) {
      const existingRef = db.collection('game_sessions').doc(existingSessionId);
      const existing = await transaction.get(existingRef);
      if (existing.exists && existing.data().status === 'active') {
        return { sessionId: existingSessionId };
      }
    }

    const sessionId = randomUUID();
    const sessionRef = db.collection('game_sessions').doc(sessionId);
    const participants = [uid, otherUid].sort();
    const question = publicCoffeePupQuestion(0, gameType);
    transaction.create(sessionRef, {
      participants,
      playerNames: {
        [uid]: own.data().displayName || '',
        [otherUid]: other.data().displayName || '',
      },
      status: 'active',
      gameType,
      currentTurnUid: uid,
      questionIndex: 0,
      questionId: questionInstanceId(question),
      questionType: question.type,
      question: question.question,
      options: question.options,
      answeredUids: [],
      round: 1,
      questionsInRound: 0,
      roundLocked: false,
      lives: {
        [uid]: startingGameLives,
        [otherUid]: startingGameLives,
      },
      scores: {
        [uid]: 0,
        [otherUid]: 0,
      },
      streaks: {
        [uid]: 0,
        [otherUid]: 0,
      },
      pendingStreaks: {},
      turnCount: 0,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(pairRef, {
      activeGameSessionIds: {
        ...activeSessionIds,
        [gameType]: sessionId,
      },
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { sessionId };
  });
});

exports.submitCoffeePupAnswer = onCall({ region }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Inicia sesión para continuar.');
  }
  const uid = request.auth.uid;
  const sessionId = request.data?.sessionId;
  const questionId = request.data?.questionId;
  const answerIndex = request.data?.answerIndex;
  if (
    typeof sessionId !== 'string' ||
    !/^[a-f0-9-]{36}$/i.test(sessionId) ||
    typeof questionId !== 'string' ||
    !Number.isInteger(answerIndex) ||
    answerIndex < 0 ||
    answerIndex > 3
  ) {
    throw new HttpsError('invalid-argument', 'La respuesta no es válida.');
  }

  const sessionRef = db.collection('game_sessions').doc(sessionId);
  return db.runTransaction(async (transaction) => {
    const session = await transaction.get(sessionRef);
    if (!session.exists || !session.data().participants.includes(uid)) {
      throw new HttpsError('permission-denied', 'No perteneces a esta partida.');
    }
    const data = session.data();
    if (data.status !== 'active') {
      throw new HttpsError(
        'failed-precondition',
        'La partida ya terminó.',
      );
    }
    if (data.roundLocked === true) {
      throw new HttpsError(
        'failed-precondition',
        'Mira un anuncio para desbloquear la siguiente ronda.',
      );
    }
    if (data.questionId !== questionId) {
      throw new HttpsError(
        'failed-precondition',
        'La pregunta cambió. Responde la pregunta actual.',
      );
    }

    const lives = { ...data.lives };
    if (!Number.isSafeInteger(lives[uid]) || lives[uid] <= 0) {
      throw new HttpsError(
        'resource-exhausted',
        'Mira un anuncio recompensado para recuperar tus vidas.',
      );
    }
    const questionBank = questionsForGameType(data.gameType || 'trivia');
    const currentQuestion = questionBank[data.questionIndex];
    if (
      !currentQuestion ||
      answerIndex >= currentQuestion.options.length
    ) {
      throw new HttpsError('invalid-argument', 'La respuesta no es válida.');
    }

    if (['opinion', 'preference'].includes(currentQuestion.type)) {
      const otherUid = data.participants.find(
        (participantUid) => participantUid !== uid,
      );
      if (!otherUid) {
        throw new HttpsError('failed-precondition', 'La partida no es válida.');
      }
      const answersRef = sessionRef.collection('privateAnswers');
      const ownAnswerRef = answersRef.doc(uid);
      const otherAnswerRef = answersRef.doc(otherUid);
      const [ownAnswer, otherAnswer] = await Promise.all([
        transaction.get(ownAnswerRef),
        transaction.get(otherAnswerRef),
      ]);
      if (ownAnswer.data()?.questionId === questionId) {
        throw new HttpsError(
          'already-exists',
          'Ya respondiste esta pregunta.',
        );
      }
      const currentAnswers = { [uid]: answerIndex };
      const otherAnswerData = otherAnswer.data();
      const answeredBoth = otherAnswerData?.questionId === questionId;
      if (answeredBoth) {
        currentAnswers[otherUid] = otherAnswerData.answerIndex;
      }
      if (!answeredBoth) {
        transaction.set(ownAnswerRef, {
          questionId,
          answerIndex,
          updatedAt: FieldValue.serverTimestamp(),
        });
        transaction.update(sessionRef, {
          answeredUids: [uid],
          updatedAt: FieldValue.serverTimestamp(),
        });
        return {
          correct: null,
          lives: lives[uid],
          waitingForMatch: true,
          turnCount: data.turnCount || 0,
        };
      }

      const questionsInRound = (data.questionsInRound || 0) + 1;
      const roundLocked =
        data.gameType === 'preferences' && questionsInRound >= 5;
      const nextQuestionIndex = roundLocked
        ? data.questionIndex
        : (data.questionIndex + 1) % questionBank.length;
      const nextQuestion = roundLocked
        ? publicCoffeePupQuestion(data.questionIndex, data.gameType)
        : publicCoffeePupQuestion(nextQuestionIndex, data.gameType);
      const nextQuestionId = roundLocked
        ? data.questionId
        : questionInstanceId(nextQuestion);
      const nextTurnUid = data.participants.find(
        (participantUid) => participantUid !== data.currentTurnUid,
      );
      const matched = currentQuestion.type === 'preference'
        ? currentAnswers[data.participants[0]] ===
          currentAnswers[data.participants[1]]
        : null;
      const progressRefs = data.participants.map((participantUid) =>
        db.collection('coffeePupProfiles').doc(participantUid),
      );
      const progressSnapshots = matched
        ? await Promise.all(
            progressRefs.map((progressRef) => transaction.get(progressRef)),
          )
        : [];
      transaction.set(ownAnswerRef, {
        questionId,
        answerIndex,
        updatedAt: FieldValue.serverTimestamp(),
      });
      if (matched) {
        for (let index = 0; index < data.participants.length; index++) {
          const progress = buildCoffeePupProgress(progressSnapshots[index], {
            preferenceMatches: 1,
          });
          transaction.set(progressRefs[index], progress, { merge: true });
        }
      }
      transaction.update(sessionRef, {
        answeredUids: [],
        currentTurnUid: roundLocked
          ? data.currentTurnUid
          : nextTurnUid || uid,
        questionsInRound:
          data.gameType === 'preferences'
            ? roundLocked
              ? 5
              : questionsInRound
            : 0,
        roundLocked,
        questionIndex: nextQuestionIndex,
        questionId: nextQuestionId,
        questionType: nextQuestion.type,
        question: nextQuestion.question,
        options: nextQuestion.options,
        lastReveal: {
          questionId,
          question: currentQuestion.question,
          options: currentQuestion.options,
          answers: currentAnswers,
          playerNames: data.playerNames,
          matched,
          createdAt: FieldValue.serverTimestamp(),
        },
        turnCount: (data.turnCount || 0) + 1,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {
        correct: null,
        lives: lives[uid],
        waitingForMatch: false,
        revealed: true,
        matched,
        roundLocked,
        turnCount: (data.turnCount || 0) + 1,
      };
    }

    if (data.currentTurnUid !== uid) {
      throw new HttpsError('failed-precondition', 'Aún no es tu turno.');
    }
    const scores = { ...data.scores };
    const streaks = { ...(data.streaks || {}) };
    const pendingStreaks = { ...(data.pendingStreaks || {}) };
    const correct = answerIndex === currentQuestion.answerIndex;
    if (correct) {
      scores[uid] = (scores[uid] || 0) + 1;
      streaks[uid] = (streaks[uid] || 0) + 1;
      delete pendingStreaks[uid];
    } else {
      pendingStreaks[uid] = streaks[uid] || 0;
      streaks[uid] = 0;
      lives[uid] -= 1;
    }
    const progressRef = db.collection('coffeePupProfiles').doc(uid);
    const progressSnapshot = await transaction.get(progressRef);
    const progressIncrements = correct
      ? {
          totalCorrect: 1,
          dogCorrect: currentQuestion.id.startsWith('dog-') ? 1 : 0,
          currentStreak: streaks[uid],
          bestStreak: streaks[uid],
        }
      : { currentStreak: 0 };
    const progress = buildCoffeePupProgress(
      progressSnapshot,
      progressIncrements,
    );

    const playerOutOfLives = lives[uid] === 0;
    const nextQuestionIndex = playerOutOfLives
      ? data.questionIndex
      : (data.questionIndex + 1) % questionBank.length;
    const nextQuestion = publicCoffeePupQuestion(
      nextQuestionIndex,
      data.gameType || 'trivia',
    );
    const otherUid = data.participants.find(
      (participantUid) => participantUid !== uid,
    );
    transaction.update(sessionRef, {
      lives,
      scores,
      streaks,
      pendingStreaks,
      currentTurnUid: playerOutOfLives ? uid : otherUid,
      questionIndex: nextQuestionIndex,
      questionId: playerOutOfLives
        ? data.questionId
        : questionInstanceId(nextQuestion),
      questionType: nextQuestion.type,
      question: nextQuestion.question,
      options: nextQuestion.options,
      turnCount: (data.turnCount || 0) + 1,
      lastTurn: {
        uid,
        questionId,
        correct,
        answerIndex,
        createdAt: FieldValue.serverTimestamp(),
      },
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(progressRef, progress, { merge: true });
    return { correct, lives: lives[uid], turnCount: (data.turnCount || 0) + 1 };
  });
});

exports.getWolvesMatchState = onCall({ region }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Inicia sesión para continuar.');
  }
  const { profile: accountProfile } = await requireMatchAccount(
    request.auth.uid,
  );
  const participantRef = db
    .collection('wolvesMatchParticipants')
    .doc(request.auth.uid);
  const participantSnapshot = await participantRef.get();
  const participant = participantSnapshot.data();
  if (!participantSnapshot.exists || !participant) {
    return {
      status: 'inactive',
      displayName: accountProfile.displayName || '',
      bio: '',
      interests: [],
      intention: null,
      recommendations: [],
      incoming: [],
      outgoing: [],
      connections: [],
    };
  }

  const pairSnapshots = await db
    .collection('wolvesMatchPairs')
    .where('participants', 'array-contains', request.auth.uid)
    .get();
  const relatedIds = new Set();
  const incoming = [];
  const outgoing = [];
  const connections = [];
  const peerSnapshots = await Promise.all(
    pairSnapshots.docs.map(async (pair) => {
      const data = pair.data();
      const otherUid = data.participants.find(
        (uid) => uid !== request.auth.uid,
      );
      if (!otherUid) return null;
      relatedIds.add(otherUid);
      const snapshot = await db
        .collection('wolvesMatchParticipants')
        .doc(otherUid)
        .get();
      const peer = snapshot.data();
      if (!peer?.matchPublicId) return null;
      return { data, peer };
    }),
  );
  for (const row of peerSnapshots) {
    if (!row) continue;
    const item = publicMatchProfile(row.peer);
    if (
      participant.status === 'active' &&
      row.peer.status === 'active' &&
      intentionsAreCompatible(participant.intention, row.peer.intention) &&
      row.data.status === 'mutual'
    ) {
      const progress = await db
        .collection('coffeePupProfiles')
        .doc(row.data.participants.find((uid) => uid !== request.auth.uid))
        .get();
      const progressData = progress.data() || {};
      const allowedAchievements = new Set(
        coffeePupAchievements.map((achievement) => achievement.id),
      );
      connections.push({
        ...item,
        coffeePupRank: progressData.rank || 'Aprendiz',
        coffeePupAchievements: (progressData.achievements || []).filter(
          (achievementId) => allowedAchievements.has(achievementId),
        ),
      });
    }
    if (
      participant.status === 'active' &&
      row.peer.status === 'active' &&
      intentionsAreCompatible(participant.intention, row.peer.intention) &&
      row.data.status === 'pending'
    ) {
      if (row.data.interestFromUid === request.auth.uid) {
        outgoing.push(item);
      } else {
        incoming.push(item);
      }
    }
  }

  const recommendations = [];
  if (participant.status === 'active') {
    const activeCandidates = await db
      .collection('wolvesMatchParticipants')
      .where('status', '==', 'active')
      .get();
    for (const candidateSnapshot of activeCandidates.docs) {
      const candidateUid = candidateSnapshot.id;
      const candidate = candidateSnapshot.data();
      if (
        candidateUid === request.auth.uid ||
        relatedIds.has(candidateUid) ||
        !candidate.matchPublicId ||
        !intentionsAreCompatible(participant.intention, candidate.intention)
      ) {
        continue;
      }
      const [blockedByMe, blockedMe] = await Promise.all([
        db
          .collection('wolvesMatchBlocks')
          .doc(request.auth.uid)
          .collection('users')
          .doc(candidateUid)
          .get(),
        db
          .collection('wolvesMatchBlocks')
          .doc(candidateUid)
          .collection('users')
          .doc(request.auth.uid)
          .get(),
      ]);
      if (!blockedByMe.exists && !blockedMe.exists) {
        recommendations.push(publicMatchProfile(candidate));
      }
    }
  }
  return {
    status: participant.status,
    displayName: participant.displayName,
    bio: participant.bio,
    interests: participant.interests,
    intention: participant.intention,
    recommendations,
    incoming,
    outgoing,
    connections,
  };
});

exports.saveWolvesMatchProfile = onCall({ region }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Inicia sesión para continuar.');
  }
  const { account, profile: accountProfile } = await requireMatchAccount(
    request.auth.uid,
  );
  const status = request.data?.status;
  const participantRef = db
    .collection('wolvesMatchParticipants')
    .doc(account.uid);
  const existing = await participantRef.get();
  if (status === 'paused' || status === 'left') {
    if (!existing.exists) return { status: 'inactive' };
    await participantRef.update({
      status,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { status };
  }
  if (!['configuring', 'active'].includes(status)) {
    throw new HttpsError('invalid-argument', 'Estado de participación inválido.');
  }
  const matchProfile = validateMatchProfile(request.data);
  if (status === 'active' && request.data?.consent !== true) {
    throw new HttpsError(
      'failed-precondition',
      'Confirma tu consentimiento para activar WOLVES MATCH.',
    );
  }
  await db.runTransaction(async (transaction) => {
    const current = await transaction.get(participantRef);
    const publicId = current.data()?.matchPublicId || randomUUID();
    transaction.set(
      participantRef,
      {
        ...matchProfile,
        displayName:
          matchProfile.displayName ||
          account.displayName ||
          accountProfile.displayName ||
          '',
        status,
        matchPublicId: publicId,
        consentAt:
          status === 'active' ? FieldValue.serverTimestamp() : null,
        updatedAt: FieldValue.serverTimestamp(),
        createdAt: current.exists
          ? current.data().createdAt
          : FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    if (current.data()?.matchPublicId !== publicId) {
      transaction.set(
        db.collection('wolvesMatchPublicIds').doc(publicId),
        { uid: account.uid },
      );
    }
  });
  return { status };
});

exports.sendWolvesMatchInterest = onCall({ region }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Inicia sesión para continuar.');
  }
  const uid = request.auth.uid;
  await requireMatchAccount(uid);
  const targetUid = await resolveMatchPublicId(request.data?.profileId, uid);
  const pairRef = db
    .collection('wolvesMatchPairs')
    .doc(matchPairId(uid, targetUid));
  const ownRef = db.collection('wolvesMatchParticipants').doc(uid);
  const targetRef = db.collection('wolvesMatchParticipants').doc(targetUid);
  const blockRef = db
    .collection('wolvesMatchBlocks')
    .doc(uid)
    .collection('users')
    .doc(targetUid);
  const reverseBlockRef = db
    .collection('wolvesMatchBlocks')
    .doc(targetUid)
    .collection('users')
    .doc(uid);
  return db.runTransaction(async (transaction) => {
    const [own, target, pair, blocked, reverseBlocked] = await Promise.all([
      transaction.get(ownRef),
      transaction.get(targetRef),
      transaction.get(pairRef),
      transaction.get(blockRef),
      transaction.get(reverseBlockRef),
    ]);
    if (
      !own.exists ||
      !target.exists ||
      own.data().status !== 'active' ||
      target.data().status !== 'active' ||
      blocked.exists ||
      reverseBlocked.exists ||
      !intentionsAreCompatible(own.data().intention, target.data().intention)
    ) {
      throw new HttpsError(
        'failed-precondition',
        'La conexión ya no está disponible o no es compatible.',
      );
    }
    const existingPair = pair.data();
    if (existingPair?.status === 'mutual') return { status: 'mutual' };
    if (
      existingPair?.status === 'blocked' ||
      existingPair?.status === 'declined'
    ) {
      throw new HttpsError(
        'failed-precondition',
        'Este perfil ya no está disponible.',
      );
    }
    if (
      existingPair?.status === 'pending' &&
      existingPair.interestFromUid !== uid
    ) {
      transaction.update(pairRef, {
        status: 'mutual',
        mutualAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return { status: 'mutual' };
    }
    transaction.set(
      pairRef,
      {
        participants: [uid, targetUid].sort(),
        status: 'pending',
        interestFromUid: uid,
        createdAt: existingPair?.createdAt || FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return { status: 'pending' };
  });
});

exports.respondWolvesMatchInterest = onCall({ region }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Inicia sesión para continuar.');
  }
  const uid = request.auth.uid;
  await requireMatchAccount(uid);
  const otherUid = await resolveMatchPublicId(request.data?.profileId, uid);
  const pairRef = db
    .collection('wolvesMatchPairs')
    .doc(matchPairId(uid, otherUid));
  const ownRef = db.collection('wolvesMatchParticipants').doc(uid);
  const otherRef = db.collection('wolvesMatchParticipants').doc(otherUid);
  const ownBlock = db
    .collection('wolvesMatchBlocks')
    .doc(uid)
    .collection('users')
    .doc(otherUid);
  const otherBlock = db
    .collection('wolvesMatchBlocks')
    .doc(otherUid)
    .collection('users')
    .doc(uid);
  return db.runTransaction(async (transaction) => {
    const [pair, own, other, blocked, reverseBlocked] = await Promise.all([
      transaction.get(pairRef),
      transaction.get(ownRef),
      transaction.get(otherRef),
      transaction.get(ownBlock),
      transaction.get(otherBlock),
    ]);
    if (
      !pair.exists ||
      pair.data().status !== 'pending' ||
      pair.data().interestFromUid === uid ||
      !own.exists ||
      !other.exists ||
      own.data().status !== 'active' ||
      other.data().status !== 'active' ||
      blocked.exists ||
      reverseBlocked.exists
    ) {
      throw new HttpsError(
        'failed-precondition',
        'Este interés ya no está disponible.',
      );
    }
    if (request.data?.accept === true) {
      if (!intentionsAreCompatible(own.data().intention, other.data().intention)) {
        throw new HttpsError(
          'failed-precondition',
          'Las intenciones ya no son compatibles.',
        );
      }
      transaction.update(pairRef, {
        status: 'mutual',
        mutualAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return { status: 'mutual' };
    }
    transaction.update(pairRef, {
      status: 'declined',
      decidedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return { status: 'declined' };
  });
});

exports.dismissWolvesMatchProfile = onCall({ region }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Inicia sesión para continuar.');
  }
  const uid = request.auth.uid;
  await requireMatchAccount(uid);
  const otherUid = await resolveMatchPublicId(request.data?.profileId, uid);
  const pairRef = db
    .collection('wolvesMatchPairs')
    .doc(matchPairId(uid, otherUid));
  await db.runTransaction(async (transaction) => {
    const pair = await transaction.get(pairRef);
    if (pair.data()?.status === 'mutual') {
      throw new HttpsError(
        'failed-precondition',
        'Una conexión mutua no puede descartarse como recomendación.',
      );
    }
    if (pair.data()?.status === 'blocked') return;
    transaction.set(
      pairRef,
      {
        participants: [uid, otherUid].sort(),
        status: 'declined',
        decidedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
  return { status: 'declined' };
});

exports.blockWolvesMatchProfile = onCall({ region }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Inicia sesión para continuar.');
  }
  const uid = request.auth.uid;
  await requireMatchAccount(uid);
  const otherUid = await resolveMatchPublicId(request.data?.profileId, uid);
  const blockRef = db
    .collection('wolvesMatchBlocks')
    .doc(uid)
    .collection('users')
    .doc(otherUid);
  const pairRef = db
    .collection('wolvesMatchPairs')
    .doc(matchPairId(uid, otherUid));
  const batch = db.batch();
  batch.set(blockRef, { createdAt: FieldValue.serverTimestamp() });
  batch.set(
    pairRef,
    {
      participants: [uid, otherUid].sort(),
      status: 'blocked',
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  await batch.commit();
  return { status: 'blocked' };
});

exports.reportWolvesMatchProfile = onCall({ region }, async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Inicia sesión para continuar.');
  }
  const uid = request.auth.uid;
  await requireMatchAccount(uid);
  const publicId = request.data?.profileId;
  const reason = request.data?.reason;
  const details =
    typeof request.data?.details === 'string'
      ? request.data.details.trim()
      : '';
  const allowedReasons = ['inappropriate', 'fake', 'harassment', 'other'];
  const targetUid = await resolveMatchPublicId(publicId, uid);
  if (
    !allowedReasons.includes(reason) ||
    details.length > 500
  ) {
    throw new HttpsError('invalid-argument', 'El reporte no es válido.');
  }
  await db.collection('wolvesMatchReports').add({
    reporterUid: uid,
    targetUid,
    reason,
    details,
    status: 'open',
    createdAt: FieldValue.serverTimestamp(),
  });
  return { submitted: true };
});

exports.moderateProfilePhoto = onCall(
  {
    region,
    secrets: [visionApiKey],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Inicia sesión para continuar.');
    }

    const account = await getAuth().getUser(request.auth.uid);
    if (!account.emailVerified && !account.phoneNumber) {
      throw new HttpsError(
        'failed-precondition',
        'Verifica tu correo o teléfono antes de validar la foto.',
      );
    }

    const encodedImage = request.data?.imageBase64;
    if (
      typeof encodedImage !== 'string' ||
      encodedImage.length === 0 ||
      encodedImage.length > 2_800_000
    ) {
      throw new HttpsError('invalid-argument', 'La imagen no es válida.');
    }

    const image = Buffer.from(encodedImage, 'base64');
    const isJpeg =
      image.length >= 3 &&
      image[0] === 0xff &&
      image[1] === 0xd8 &&
      image[2] === 0xff;
    const isPng =
      image.length >= 8 &&
      image.subarray(0, 8).equals(
        Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
      );
    if (image.length > 2_000_000 || (!isJpeg && !isPng)) {
      throw new HttpsError('invalid-argument', 'La imagen no es válida.');
    }

    const profile = await db.collection('users').doc(account.uid).get();
    if (!profile.exists) {
      throw new HttpsError(
        'failed-precondition',
        'Completa el perfil antes de validar la foto.',
      );
    }
    let visionResponse;
    try {
      const response = await fetch(
        `https://vision.googleapis.com/v1/images:annotate?key=${encodeURIComponent(visionApiKey.value())}`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            requests: [
              {
                image: { content: image.toString('base64') },
                features: [
                  { type: 'SAFE_SEARCH_DETECTION' },
                  { type: 'FACE_DETECTION', maxResults: 5 },
                  { type: 'TEXT_DETECTION' },
                ],
              },
            ],
          }),
        },
      );
      if (!response.ok) {
        logger.error('Cloud Vision rechazó la solicitud de moderación.', {
          status: response.status,
        });
        throw new HttpsError(
          'unavailable',
          'No se pudo analizar la imagen. Inténtalo más tarde.',
        );
      }
      visionResponse = await response.json();
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      logger.error('No se pudo contactar Cloud Vision.', {
        error: error.message,
      });
      throw new HttpsError(
        'unavailable',
        'No se pudo analizar la imagen. Inténtalo más tarde.',
      );
    }

    const annotation = visionResponse.responses?.[0];
    if (annotation?.error || !annotation) {
      logger.error('Cloud Vision devolvió un error de análisis.', {
        error: annotation?.error?.message,
      });
      throw new HttpsError(
        'unavailable',
        'No se pudo analizar la imagen. Inténtalo más tarde.',
      );
    }

    const likelihoodRank = {
      UNKNOWN: 0,
      VERY_UNLIKELY: 1,
      UNLIKELY: 2,
      POSSIBLE: 3,
      LIKELY: 4,
      VERY_LIKELY: 5,
    };
    const safeSearch = annotation.safeSearchAnnotation;
    const rejectedCategories = ['adult', 'racy', 'violence', 'spoof'];
    const hasUnsafeContent =
      !safeSearch ||
      rejectedCategories.some(
        (category) => {
          const likelihood = likelihoodRank[safeSearch[category]];
          return likelihood == null || likelihood >= 4;
        },
      );
    const hasFace = (annotation.faceAnnotations || []).length > 0;
    const recognizedText = annotation.fullTextAnnotation?.text || '';
    const exposesCredential = /\b(password|contrase(?:ña|na)|api[\s_-]?key|access[\s_-]?token|secret|clave)\s*[:=]\s*\S+/i
      .test(recognizedText);
    if (hasUnsafeContent || !hasFace || exposesCredential) {
      throw new HttpsError(
        'failed-precondition',
        'profile-photo-rejected',
      );
    }

    const contentType = isJpeg ? 'image/jpeg' : 'image/png';
    const extension = isJpeg ? 'jpg' : 'png';
    const objectPath = `profile-images/${account.uid}/avatar.${extension}`;
    const downloadToken = randomUUID();
    await getStorage().bucket().file(objectPath).save(image, {
      resumable: false,
      metadata: {
        contentType,
        cacheControl: 'private, max-age=3600',
        metadata: {
          ownerUid: account.uid,
          firebaseStorageDownloadTokens: downloadToken,
        },
      },
    });
    await db.collection('users').doc(account.uid).set(
      {
        profilePhotoPath: objectPath,
        isVerified: true,
        avatarModeratedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    return { path: objectPath };
  },
);

exports.resolveUsernameForSignIn = onCall(
  { region },
  async (request) => {
    const username = request.data?.username;
    const password = request.data?.password;
    const apiKey = request.data?.apiKey;
    if (
      typeof username !== 'string' ||
      !/^[a-zA-Z0-9._-]{3,20}$/.test(username.trim()) ||
      typeof password !== 'string' ||
      password.length < 1 ||
      password.length > 128 ||
      typeof apiKey !== 'string' ||
      apiKey.length > 256
    ) {
      throw new HttpsError(
        'invalid-argument',
        'Ingresa un Username y contraseña válidos.',
      );
    }

    const usernameSnapshot = await db
      .collection('usernameRegistry')
      .doc(username.trim().toLowerCase())
      .get();
    const uid = usernameSnapshot.data()?.uid;
    if (
      !usernameSnapshot.exists ||
      usernameSnapshot.data()?.role !== 'user' ||
      typeof uid !== 'string'
    ) {
      throw new HttpsError(
        'unauthenticated',
        'Username o contraseña incorrectos.',
      );
    }

    const profileSnapshot = await db.collection('users').doc(uid).get();
    const profile = profileSnapshot.data();
    if (
      !profileSnapshot.exists ||
      profile?.role !== 'user' ||
      typeof profile.username !== 'string' ||
      profile.username.trim().toLowerCase() !== username.trim().toLowerCase()
    ) {
      throw new HttpsError(
        'unauthenticated',
        'Username o contraseña incorrectos.',
      );
    }

    let account;
    try {
      account = await getAuth().getUser(uid);
    } catch (error) {
      if (error.code === 'auth/user-not-found') {
        throw new HttpsError(
          'unauthenticated',
          'Username o contraseña incorrectos.',
        );
      }
      logger.error('No se pudo consultar la cuenta del Username.', {
        error: error.message,
      });
      throw new HttpsError(
        'unavailable',
        'No se pudo validar el acceso. Inténtalo de nuevo.',
      );
    }
    if (!account.email || account.disabled) {
      throw new HttpsError(
        'unauthenticated',
        'Username o contraseña incorrectos.',
      );
    }

    let authResponse;
    try {
      const response = await fetch(
        `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${encodeURIComponent(apiKey)}`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            ...(typeof request.rawRequest.headers.origin === 'string'
              ? { Referer: request.rawRequest.headers.origin }
              : {}),
          },
          body: JSON.stringify({
            email: account.email,
            password,
            returnSecureToken: true,
          }),
          signal: AbortSignal.timeout(10_000),
        },
      );
      authResponse = await response.json();
      if (!response.ok || authResponse.localId !== uid) {
        const authError = authResponse.error?.message;
        if (authError === 'USER_DISABLED') {
          throw new HttpsError(
            'permission-denied',
            'Esta cuenta está deshabilitada.',
          );
        }
        throw new HttpsError(
          'unauthenticated',
          'Username o contraseña incorrectos.',
        );
      }
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      logger.error('No se pudo validar el acceso por Username.', {
        error: error.message,
      });
      throw new HttpsError(
        'unavailable',
        'No se pudo validar el acceso. Inténtalo de nuevo.',
      );
    }

    try {
      const customToken = await getAuth().createCustomToken(uid);
      return { customToken };
    } catch (error) {
      logger.error('No se pudo emitir el token de acceso por Username.', {
        uid,
        error: error.message,
      });
      throw new HttpsError(
        'internal',
        'No se pudo completar el acceso. Inténtalo de nuevo.',
      );
    }
  },
);

async function getAuthorizedKitchenTokens() {
  const [posStaff, legacyStaff, management] = await Promise.all([
    db
      .collection('pos_staff')
      .where('role', 'in', ['barista', 'cajero', 'cocina'])
      .get(),
    db
      .collection('users')
      .where('role', 'in', ['barista', 'cajero', 'cocina', 'admin', 'gerente'])
      .get(),
    db
      .collection('management')
      .where('role', 'in', ['admin', 'gerente'])
      .get(),
  ]);
  const staffUids = new Set(
    [
      ...posStaff.docs,
      ...legacyStaff.docs,
      ...management.docs,
    ].map((profile) => profile.id),
  );
  const tokens = [];

  for (const uid of staffUids) {
    try {
      const account = await getAuth().getUser(uid);
      if (account.disabled || !account.emailVerified) continue;
    } catch (error) {
      logger.warn('No se pudo validar la cuenta de personal para push.', {
        uid,
        error: error.message,
      });
      continue;
    }

    const registrations = await db
      .collection('users')
      .doc(uid)
      .collection('pushTokens')
      .get();
    for (const registration of registrations.docs) {
      const token = registration.data().token;
      if (typeof token === 'string' && token.length > 0) {
        tokens.push({ token, reference: registration.ref });
      }
    }
  }

  return tokens;
}

async function getAuthorizedManagementTokens() {
  const managementRoles = new Set([
    'admin',
    'gerente',
    'gerencia',
    'manager',
    'management',
    'administrator',
  ]);
  const [managementProfiles, usersByRole, usersByLegacyRole] =
    await Promise.all([
      db.collection('management').get(),
      db
        .collection('users')
        .where('role', 'in', [...managementRoles])
        .get(),
      db
        .collection('users')
        .where('rol', 'in', [...managementRoles])
        .get(),
    ]);
  const managerUids = new Set(
    [
      ...managementProfiles.docs,
      ...usersByRole.docs,
      ...usersByLegacyRole.docs,
    ]
      .filter((profile) => {
        const role = profile.data().role ?? profile.data().rol;
        return typeof role === 'string' &&
          managementRoles.has(role.toLowerCase());
      })
      .map((profile) => profile.id),
  );
  const tokens = [];

  for (const uid of managerUids) {
    try {
      const account = await getAuth().getUser(uid);
      if (account.disabled || !account.emailVerified) continue;
    } catch (error) {
      logger.warn('No se pudo validar la cuenta de Gerencia para push.', {
        uid,
        error: error.message,
      });
      continue;
    }

    const registrations = await db
      .collection('users')
      .doc(uid)
      .collection('pushTokens')
      .get();
    for (const registration of registrations.docs) {
      const token = registration.data().token;
      if (typeof token === 'string' && token.length > 0) {
        tokens.push({ token, reference: registration.ref });
      }
    }
  }

  return tokens;
}

async function notifyManagementProductOutOfStock(productId, product) {
  const registrations = await getAuthorizedManagementTokens();
  if (registrations.length === 0) {
    logger.warn('No hay dispositivos push de Gerencia registrados.', {
      productId,
    });
    return;
  }

  const title = 'Coffee Wolves · Producto agotado';
  const body = `${product.name || 'Un producto del menú'} llegó a cero unidades.`;
  for (let offset = 0; offset < registrations.length; offset += 500) {
    const batch = registrations.slice(offset, offset + 500);
    const response = await getMessaging().sendEachForMulticast({
      tokens: batch.map((registration) => registration.token),
      data: {
        title,
        body,
        productId,
        url: '/',
      },
      webpush: {
        headers: {
          Urgency: 'high',
          TTL: '86400',
        },
      },
    });

    const invalidRegistrations = [];
    response.responses.forEach((result, index) => {
      if (
        !result.success &&
        [
          'messaging/invalid-registration-token',
          'messaging/registration-token-not-registered',
        ].includes(result.error?.code)
      ) {
        invalidRegistrations.push(batch[index].reference.delete());
      }
    });
    await Promise.all(invalidRegistrations);
  }
}

function orderDescription(order, items = []) {
  const summary = items
    .slice(0, 4)
    .map((item) => `${item.quantity || 1} × ${item.name || 'Producto'}`)
    .join(', ');
  const label = Number.isInteger(order.tableNumber)
    ? `Mesa ${order.tableNumber}`
    : order.serviceType === 'dineIn'
      ? 'Local'
      : order.serviceType === 'delivery'
        ? 'Delivery'
        : 'Llevar';
  const table = `${label}: `;
  return `${table}${summary || 'Nueva comanda pendiente'}`;
}

async function notifyKitchen(orderId, order, items = order.items) {
  const registrations = await getAuthorizedKitchenTokens();
  if (registrations.length === 0) {
    logger.warn('No hay dispositivos push autorizados registrados.', { orderId });
    return;
  }

  const body = orderDescription(order, items).slice(0, 180);
  for (let offset = 0; offset < registrations.length; offset += 500) {
    const batch = registrations.slice(offset, offset + 500);
    const response = await getMessaging().sendEachForMulticast({
      tokens: batch.map((registration) => registration.token),
      data: {
        title: orderTitle,
        body,
        orderId,
        url: '/',
      },
      webpush: {
        headers: {
          Urgency: 'high',
          TTL: '300',
        },
      },
    });

    const invalidRegistrations = [];
    response.responses.forEach((result, index) => {
      if (
        !result.success &&
        [
          'messaging/invalid-registration-token',
          'messaging/registration-token-not-registered',
        ].includes(result.error?.code)
      ) {
        invalidRegistrations.push(batch[index].reference.delete());
      }
    });
    await Promise.all(invalidRegistrations);
  }
}

async function closeKitchenNotifications(orderId) {
  const registrations = await getAuthorizedKitchenTokens();
  for (let offset = 0; offset < registrations.length; offset += 500) {
    const batch = registrations.slice(offset, offset + 500);
    const response = await getMessaging().sendEachForMulticast({
      tokens: batch.map((registration) => registration.token),
      data: {
        action: 'acknowledged',
        orderId,
      },
      webpush: {
        headers: {
          Urgency: 'high',
          TTL: '300',
        },
      },
    });
    const invalidRegistrations = [];
    response.responses.forEach((result, index) => {
      if (
        !result.success &&
        [
          'messaging/invalid-registration-token',
          'messaging/registration-token-not-registered',
        ].includes(result.error?.code)
      ) {
        invalidRegistrations.push(batch[index].reference.delete());
      }
    });
    await Promise.all(invalidRegistrations);
  }
}

async function sendPendingOrderAlert(orderId, orderReference) {
  const beforeSend = await orderReference.get();
  if (!beforeSend.exists || beforeSend.data().status !== 'pending') return;

  await orderReference.update({
    lastNotificationAt: FieldValue.serverTimestamp(),
  });
  await notifyKitchen(orderId, beforeSend.data());
}

async function sendPendingKitchenOrderAlert(orderId, orderReference) {
  const beforeSend = await orderReference.get();
  if (!beforeSend.exists || beforeSend.data().status !== 'pending') return;
  const itemSnapshot = await orderReference
    .collection('items')
    .orderBy('position')
    .get();
  const items = itemSnapshot.docs.map((item) => item.data());

  await orderReference.update({
    lastNotificationAt: FieldValue.serverTimestamp(),
  });
  await notifyKitchen(orderId, beforeSend.data(), items);
}

exports.notifyKitchenOnNewKitchenOrder = onDocumentCreated(
  {
    document: 'kitchenOrders/{orderId}',
    region,
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot || snapshot.data().status !== 'pending') return;
    await sendPendingKitchenOrderAlert(event.params.orderId, snapshot.ref);
  },
);

exports.closeKitchenAlertWhenPreparationStarts = onDocumentUpdated(
  {
    document: 'kitchenOrders/{orderId}',
    region,
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (before?.status !== 'pending' || after?.status !== 'preparing') return;
    await closeKitchenNotifications(event.params.orderId);
  },
);

exports.notifyKitchenOnNewOrder = onDocumentCreated(
  {
    document: 'cafeOrders/{orderId}',
    region,
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot || snapshot.data().status !== 'pending') return;
    await sendPendingOrderAlert(event.params.orderId, snapshot.ref);
  },
);

exports.notifyManagementOnCafeProductOutOfStock = onDocumentUpdated(
  {
    document: 'cafeCatalog/{productId}',
    region,
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (
      !before ||
      !after ||
      after.stockTracked !== true ||
      typeof before.stock !== 'number' ||
      before.stock <= 0 ||
      after.stock !== 0
    ) {
      return;
    }
    await notifyManagementProductOutOfStock(event.params.productId, after);
  },
);

exports.closeKitchenAlertOnAcknowledgement = onDocumentUpdated(
  {
    document: 'cafeOrders/{orderId}',
    region,
  },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (before?.status !== 'pending' || after?.status !== 'acknowledged') {
      return;
    }
    await closeKitchenNotifications(event.params.orderId);
  },
);

exports.repeatPendingKitchenAlerts = onSchedule(
  {
    schedule: 'every 1 minutes',
    region,
    timeZone: 'America/La_Paz',
  },
  async () => {
    const pendingOrderCollections = await Promise.all(
      ['kitchenOrders', 'cafeOrders'].map((collectionName) =>
        db
          .collection(collectionName)
          .where('status', '==', 'pending')
          .limit(200)
          .get(),
      ),
    );
    const now = Date.now();
    const repeatIntervalMs = 60_000;

    for (const pendingOrders of pendingOrderCollections) {
      for (const order of pendingOrders.docs) {
        const lastNotificationAt = order.data().lastNotificationAt?.toMillis();
        if (
          lastNotificationAt != null &&
          now - lastNotificationAt < repeatIntervalMs
        ) {
          continue;
        }
        if (order.ref.parent.id === 'kitchenOrders') {
          await sendPendingKitchenOrderAlert(order.id, order.ref);
        } else {
          await sendPendingOrderAlert(order.id, order.ref);
        }
      }
    }
  },
);

exports.expireWolvesShopOrders = onSchedule(
  {
    schedule: 'every 60 minutes',
    region,
    timeZone: 'America/La_Paz',
  },
  async () => {
    const expiresBefore = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
    const expirationTimestamp = Timestamp.fromDate(expiresBefore);
    let deletedCount = 0;

    while (true) {
      const expiredOrders = await db
        .collection('wolvesShopOrders')
        .where('createdAt', '<=', expirationTimestamp)
        .orderBy('createdAt')
        .limit(400)
        .get();
      if (expiredOrders.empty) break;

      const batch = db.batch();
      for (const order of expiredOrders.docs) {
        batch.delete(order.ref);
      }
      await batch.commit();
      deletedCount += expiredOrders.size;
    }

    if (deletedCount > 0) {
      logger.info('Se eliminaron pedidos Wolves Shop con más de 7 días.', {
        deletedCount,
      });
    }
  },
);
