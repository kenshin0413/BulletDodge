const {initializeApp} = require("firebase-admin/app");
const {getFirestore, FieldValue, Timestamp} = require("firebase-admin/firestore");

initializeApp();

const FIRST_SEASON_YEAR = 2026;
const FIRST_SEASON_MONTH = 8;
const CHAMPION_ICONS = new Map([
  [1, "season_champion"],
  [2, "season_champion_2"],
  [3, "season_champion_3"],
  [4, "season_champion_4"],
  [5, "season_champion_5"],
]);
const EXCLUDED_REWARD_UIDS = new Set([
  "lNOc8N0menYh0CUS5aFGYH9wHXb2", // Official developer account
]);

function currentSeasonNumber(date = new Date()) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Tokyo",
    year: "numeric",
    month: "numeric",
  }).formatToParts(date);
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return (Number(value.year) - FIRST_SEASON_YEAR) * 12
    + Number(value.month) - FIRST_SEASON_MONTH + 1;
}

function seasonDate(number) {
  const zeroBased = FIRST_SEASON_MONTH - 1 + number - 1;
  return {
    year: FIRST_SEASON_YEAR + Math.floor(zeroBased / 12),
    month: zeroBased % 12 + 1,
  };
}

async function awardSeason(db, seasonNumber) {
  const iconID = CHAMPION_ICONS.get(seasonNumber);
  const awardRef = db.collection("seasonAwards").doc(`v${seasonNumber}`);
  const existing = await awardRef.get();
  if (existing.exists && existing.get("status") === "awarded") {
    console.log(`Season ${seasonNumber}: already awarded`);
    return;
  }

  const winnerSnapshot = await db.collection("leaderboards")
      .doc(`v${seasonNumber}`).collection("entries")
      .orderBy("survivalMilliseconds", "desc")
      .orderBy("dodgedCount", "desc")
      .orderBy("achievedAt", "asc")
      .limit(100)
      .get();

  const winner = winnerSnapshot.docs.find(
      (entry) => !EXCLUDED_REWARD_UIDS.has(entry.id),
  );
  if (!winner) {
    const date = seasonDate(seasonNumber);
    await awardRef.set({
      seasonNumber,
      seasonYear: date.year,
      seasonMonth: date.month,
      status: "no_eligible_entries",
      checkedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    console.log(`Season ${seasonNumber}: no eligible entries; will check again tomorrow`);
    return;
  }

  const rewardRef = db.collection("profileRewards").doc(winner.id);
  const date = seasonDate(seasonNumber);
  await db.runTransaction(async (transaction) => {
    const award = await transaction.get(awardRef);
    if (award.exists && award.get("status") === "awarded") return;

    transaction.set(rewardRef, {
      unlockedIconIDs: FieldValue.arrayUnion(iconID),
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
    transaction.set(awardRef, {
      seasonNumber,
      seasonYear: date.year,
      seasonMonth: date.month,
      winnerUid: winner.id,
      winnerDisplayName: winner.get("displayName") || "",
      iconID,
      status: "awarded",
      awardedAt: FieldValue.serverTimestamp(),
      sourceAchievedAt: winner.get("achievedAt") || Timestamp.fromMillis(0),
    });
  });

  console.log(`Season ${seasonNumber}: awarded ${iconID} to ${winner.id}`);
}

async function withRetry(operation, attempts = 4) {
  let lastError;
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      return await operation();
    } catch (error) {
      lastError = error;
      if (attempt < attempts) {
        const delay = 2 ** attempt * 1000;
        console.warn(`Attempt ${attempt} failed; retrying in ${delay / 1000}s`, error.message);
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }
  throw lastError;
}

async function main() {
  const latestCompleted = currentSeasonNumber() - 1;
  if (latestCompleted < 1) {
    console.log("No completed season yet");
    return;
  }

  const db = getFirestore();
  const finalConfiguredSeason = Math.min(latestCompleted, Math.max(...CHAMPION_ICONS.keys()));
  for (let season = 1; season <= finalConfiguredSeason; season += 1) {
    await withRetry(() => awardSeason(db, season));
  }
}

main().catch((error) => {
  console.error("Season award automation failed", error);
  process.exitCode = 1;
});
