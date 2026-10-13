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
  let cursor;
  let scanned = 0;
  let deleted = 0;
  let migrated = 0;

  while (true) {
    let pageQuery = posts.orderBy(fieldPath.documentId()).limit(pageSize);
    if (cursor) pageQuery = pageQuery.startAfter(cursor);
    const page = await pageQuery.get();
    if (page.empty) break;

    const batch = db.batch();
    let pendingWrites = 0;
    for (const document of page.docs) {
      scanned += 1;
      const data = document.data();
      const expiration = data.fecha_Expiracion;
      const expirationDate = expiration instanceof timestamp
        ? expiration.toDate()
        : data.createdAt instanceof timestamp
          ? data.createdAt.toDate()
          : now;
      const effectiveExpiration =
        expiration instanceof timestamp
          ? expirationDate
          : new Date(expirationDate.getTime() + 7 * 24 * 60 * 60 * 1000);

      if (effectiveExpiration <= now) {
        batch.delete(document.ref);
        deleted += 1;
      } else if (!(expiration instanceof timestamp)) {
        batch.update(document.ref, {
          fecha_Expiracion: timestamp.fromDate(effectiveExpiration),
        });
        migrated += 1;
      } else {
        continue;
      }
      pendingWrites += 1;
    }

    if (pendingWrites > 0) await batch.commit();
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
  if (existingStats.exists) return;

  const utcMidnight = new Date(Date.UTC(
    now.getUTCFullYear(),
    now.getUTCMonth(),
    now.getUTCDate(),
  ));
  const [users, postsToday] = await Promise.all([
    db.collection('users').count().get(),
    db.collection('mischiefPosts')
      .where('createdAt', '>=', timestamp.fromDate(utcMidnight))
      .count()
      .get(),
  ]);
  const dateKey = now.toISOString().slice(0, 10);

  await db.runTransaction(async (transaction) => {
    const currentStats = await transaction.get(statsRef);
    if (currentStats.exists) return;
    transaction.create(statsRef, {
      memberCount: users.data().count,
      dailyPostDate: dateKey,
      dailyPostCount: postsToday.data().count,
      lastMemberUid: '',
      lastPostId: '',
      updatedAt: fieldValue.serverTimestamp(),
    });
  });
  console.log(
    `Contadores inicializados: ${users.data().count} miembros y ` +
    `${postsToday.data().count} publicaciones hoy (UTC).`,
  );
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
