const admin = require('firebase-admin');

const projectId = process.env.GCLOUD_PROJECT || 'wolves-club-fb24a';
const intervalMs = 6 * 60 * 60 * 1000;
const pageSize = 200;

admin.initializeApp({ projectId });

const db = admin.firestore();
const timestamp = admin.firestore.Timestamp;
const fieldPath = admin.firestore.FieldPath;
const fieldValue = admin.firestore.FieldValue;

async function migrateAndDeleteExpiredPosts(now) {
  const posts = db.collection('mischiefPosts');
  const migrate = process.argv.includes('--migrate');
  let cursor;
  let scanned = 0;
  let deleted = 0;
  let migrated = 0;

  while (true) {
    let pageQuery = migrate
      ? posts.orderBy(fieldPath.documentId()).limit(pageSize)
      : posts
        .where('fecha_Expiracion', '<=', timestamp.fromDate(now))
        .orderBy('fecha_Expiracion')
        .limit(pageSize);
    if (cursor) pageQuery = pageQuery.startAfter(cursor);
    const page = await pageQuery.get();
    if (page.empty) break;

    for (const document of page.docs) {
      scanned += 1;
      const data = document.data();
      const effectiveExpiration = migrate
        ? data.createdAt instanceof timestamp
          ? new Date(
            data.createdAt.toDate().getTime() + 7 * 24 * 60 * 60 * 1000,
          )
          : data.fecha_Expiracion instanceof timestamp
            ? data.fecha_Expiracion.toDate()
            : new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000)
        : data.fecha_Expiracion instanceof timestamp
          ? data.fecha_Expiracion.toDate()
          : now;
      if (effectiveExpiration <= now) {
        const chunks = await document.ref.collection('videoChunks').get();
        const batch = db.batch();
        for (const chunk of chunks.docs) batch.delete(chunk.ref);
        batch.delete(document.ref);
        await batch.commit();
        deleted += 1;
        continue;
      }

      if (migrate) {
        const expiration = timestamp.fromDate(effectiveExpiration);
        if (!(data.fecha_Expiracion instanceof timestamp)
            || data.fecha_Expiracion.toMillis() !== expiration.toMillis()) {
          await document.ref.update({ fecha_Expiracion: expiration });
          migrated += 1;
        }
      }
    }

    cursor = page.docs[page.docs.length - 1];
    if (page.size < pageSize) break;
  }

  console.log(
    `Muro: ${scanned} publicaciones revisadas, ` +
    `${migrated} expiraciones agregadas, ${deleted} publicaciones vencidas eliminadas.`,
  );
}

async function initializeCommunityStats(now) {
  const statsRef = db.collection('communityStats').doc('mischiefWall');
  const existingStats = await statsRef.get();
  const recountMembers = process.argv.includes('--recount-members');
  if (existingStats.exists && !recountMembers) return;
  const utcMidnight = new Date(Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate(),
  ));
  const users = await db.collection('users').count().get();
  const postsToday = existingStats.exists
    ? null
    : await db.collection('mischiefPosts')
      .where('createdAt', '>=', timestamp.fromDate(utcMidnight))
      .count()
      .get();
  const dateKey = now.toISOString().slice(0, 10);

  await db.runTransaction(async (transaction) => {
    const currentStats = await transaction.get(statsRef);
    if (currentStats.exists) {
      if (recountMembers) {
        transaction.update(statsRef, {
          memberCount: users.data().count,
          updatedAt: fieldValue.serverTimestamp(),
        });
      }
    } else {
      transaction.create(statsRef, {
        memberCount: users.data().count,
        dailyPostDate: dateKey,
        dailyPostCount: postsToday.data().count,
        lastMemberUid: '',
        lastPostId: '',
        updatedAt: fieldValue.serverTimestamp(),
      });
    }
  });
  if (existingStats.exists) {
    console.log(`Contador de miembros actualizado: ${users.data().count}.`);
  } else {
    console.log(
      `Contadores inicializados: ${users.data().count} miembros y ` +
      `${postsToday.data().count} publicaciones hoy (UTC).`,
    );
  }
}

async function runMaintenance() {
  const now = new Date();
  await migrateAndDeleteExpiredPosts(now);
  await initializeCommunityStats(now);
}

async function main() {
  const watch = process.argv.includes('--watch');
  do {
    try {
      await runMaintenance();
    } catch (error) {
      console.error('Falló la limpieza del Muro:', error);
      if (!watch) throw error;
    }
    if (!watch) return;
    console.log('Próxima limpieza en 6 horas. Mantén esta terminal abierta.');
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  } while (watch);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
