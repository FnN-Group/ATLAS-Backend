import fs from "node:fs";
import path from "node:path";

interface BattlePassData {
  battlePassOfferId: string;
  battleBundleOfferId: string;
  tierOfferId: string;
  freeRewards: Record<string, number>[];
  paidRewards: Record<string, number>[];
}

interface VariantEntry {
  id: string;
  variants: { channel: string; active: string; owned: string[] }[];
}

let variantsCache: VariantEntry[] | null = null;

function loadVariants(): VariantEntry[] {
  if (variantsCache) return variantsCache;
  try {
    const raw = fs.readFileSync(
      path.join(__dirname, "../../../static/shop/variants.json"),
      "utf8"
    );
    variantsCache = JSON.parse(raw);
    return variantsCache!;
  } catch {
    return [];
  }
}

function findVariantEntry(templateId: string): any[] | null {
  const variants = loadVariants();
  const entry = variants.find(
    (v) => v.id.toLowerCase() === templateId.toLowerCase()
  );
  return entry ? entry.variants : null;
}

export function loadBattlePassData(season: number): BattlePassData | null {
  const bpPath = path.join(
    __dirname,
    `../../../static/battlepass/S${season}.json`
  );
  try {
    const raw = fs.readFileSync(bpPath, "utf8");
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

export function isBattlePassOffer(
  bp: BattlePassData,
  offerId: string
): "battlepass" | "tier" | null {
  if (bp.battlePassOfferId === offerId || bp.battleBundleOfferId === offerId) {
    return "battlepass";
  }
  if (bp.tierOfferId === offerId) {
    return "tier";
  }
  return null;
}

function processRewardTier(
  athena: any,
  profile: any,
  tier: Record<string, number> | null,
  profileChanges: any[],
  athenaChanges: any[]
): any[] {
  if (!tier) return [];

  const lootList: any[] = [];

  for (const templateId of Object.keys(tier)) {
    const lowerItem = templateId.toLowerCase();

    // XP Boosts
    if (
      lowerItem === "token:athenaseasonxpboost" ||
      lowerItem === "token:athenaseasonfriendxpboost"
    ) {
      continue;
    }

    // Currency (V-Bucks)
    if (lowerItem.startsWith("currency:mtx")) {
      const quantity = tier[templateId] ?? 0;
      if (quantity <= 0) continue;

      for (const key of Object.keys(profile.items)) {
        const item = profile.items[key];
        if (
          item?.templateId?.toLowerCase() === "currency:mtxpurchased"
        ) {
          item.quantity = (item.quantity ?? 0) + quantity;
          profileChanges.push({
            changeType: "itemQuantityChanged",
            itemId: key,
            quantity: item.quantity,
          });
          lootList.push({
            itemType: item.templateId,
            itemGuid: key,
            quantity,
          });
          break;
        }
      }
      continue;
    }

    // Cosmetic items — check if athena or profile item
    const targetItems = lowerItem.startsWith("athena")
      ? athena.items
      : profile.items;

    // Check if already owned
    let existingId = "";
    for (const [id, itm] of Object.entries(targetItems)) {
      if ((itm as any)?.templateId?.toLowerCase() === lowerItem) {
        existingId = id;
        break;
      }
    }

    if (!existingId) {
      const id = crypto.randomUUID().replace(/-/g, "");
      const variants = findVariantEntry(templateId);
      const item: any = {
        templateId,
        attributes: {
          item_seen: false,
          variants: variants ?? [],
        },
        quantity: 1,
      };
      targetItems[id] = item;
      existingId = id;
    }

    athenaChanges.push({
      changeType: "itemAdded",
      itemId: existingId,
      item: targetItems[existingId],
    });

    lootList.push({
      itemType: templateId,
      itemGuid: existingId,
      quantity: 1,
    });
  }

  return lootList;
}

export function handleBattlePassPurchase(
  athena: any,
  profile: any,
  bp: BattlePassData,
  offerId: string,
  season: number,
  profileChanges: any[],
  athenaChanges: any[]
): any[] {
  const attrs = athena.stats.attributes;
  attrs.book_purchased = true;

  // Add BP token
  const tokenKey = `Token:Athena_S${season}_NoBattleBundleOption_Token`;
  const tokenData = {
    templateId: `Token:athena_s${season}_nobattlebundleoption_token`,
    attributes: {
      max_level_bonus: 0,
      level: 1,
      item_seen: true,
      xp: 0,
      favorite: false,
    },
    quantity: 1,
  };
  profile.items[tokenKey] = tokenData;
  profileChanges.push({
    changeType: "itemAdded",
    itemId: tokenKey,
    item: tokenData,
  });

  let tierIncrement = 1;

  // Battle bundle grants 25 tiers
  if (bp.battleBundleOfferId === offerId) {
    tierIncrement = 25;
    attrs.book_level = (attrs.book_level ?? 1) + tierIncrement;
    // Chapter 2+ (season >= 11) updates level alongside book_level
    if (season >= 11) {
      attrs.level = (attrs.level ?? 1) + tierIncrement;
    }
    if (attrs.book_level > 100) {
      attrs.book_level = 100;
    }
  }

  const endingTier = Math.min(attrs.book_level ?? 1, 100);
  const startTier = Math.max(endingTier - tierIncrement, 0);

  const lootList: any[] = [];
  for (let i = startTier; i < endingTier; i++) {
    const freeTier = bp.freeRewards[i] ?? null;
    const paidTier = bp.paidRewards[i] ?? null;
    lootList.push(
      ...processRewardTier(athena, profile, freeTier, profileChanges, athenaChanges)
    );
    lootList.push(
      ...processRewardTier(athena, profile, paidTier, profileChanges, athenaChanges)
    );
  }

  athenaChanges.push(
    { changeType: "statModified", name: "book_purchased", value: true },
    { changeType: "statModified", name: "book_level", value: attrs.book_level },
    { changeType: "statModified", name: "level", value: attrs.level }
  );

  return lootList;
}

export function handleTierPurchase(
  athena: any,
  profile: any,
  bp: BattlePassData,
  purchaseQuantity: number,
  season: number,
  profileChanges: any[],
  athenaChanges: any[]
): any[] {
  const attrs = athena.stats.attributes;

  const startingTier = attrs.book_level ?? 1;
  attrs.book_level = Math.min(startingTier + purchaseQuantity, 100);

  // Chapter 2+ (season >= 11) updates level alongside book_level
  if (season >= 11) {
    attrs.level = (attrs.level ?? 1) + purchaseQuantity;
    athenaChanges.push({
      changeType: "statModified",
      name: "level",
      value: attrs.level,
    });
  }

  const endingTier = attrs.book_level;
  const bookPurchased = attrs.book_purchased === true;

  const lootList: any[] = [];
  for (let i = startingTier; i < endingTier; i++) {
    const freeTier = bp.freeRewards[i] ?? null;
    const paidTier = bookPurchased ? (bp.paidRewards[i] ?? null) : null;
    lootList.push(
      ...processRewardTier(athena, profile, freeTier, profileChanges, athenaChanges)
    );
    if (paidTier) {
      lootList.push(
        ...processRewardTier(athena, profile, paidTier, profileChanges, athenaChanges)
      );
    }
  }

  athenaChanges.push({
    changeType: "statModified",
    name: "book_level",
    value: attrs.book_level,
  });

  return lootList;
}
