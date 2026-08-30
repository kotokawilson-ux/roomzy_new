const { setGlobalOptions } = require("firebase-functions");
const { onRequest } = require("firebase-functions/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

setGlobalOptions({ maxInstances: 10 });

// ── Auto-expire stale pre-bookings ──────────────────────────────────────────
exports.expirePreBookings = onSchedule("every 24 hours", async (event) => {
    const now = admin.firestore.Timestamp.now();
    const snap = await db.collection("pre_bookings")
        .where("status", "==", "active")
        .where("expires_at", "<=", now)
        .get();

    if (snap.empty) {
        logger.info("No pre-bookings to expire");
        return;
    }

    let batch = db.batch();
    let count = 0;
    const commits = [];

    for (const doc of snap.docs) {
        batch.update(doc.ref, {
            status: "expired",
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });
        count++;
        if (count === 450) {
            commits.push(batch.commit());
            batch = db.batch();
            count = 0;
        }
    }
    if (count > 0) commits.push(batch.commit());

    await Promise.all(commits);
    logger.info(`Expired ${snap.docs.length} pre-booking(s)`);
});