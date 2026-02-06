import app from "..";
import { Atlas } from "../utils/handlers/errors";
import logger from "../utils/logger/logger";

const keychain = await Bun.file("static/shop/keychain.json").json();
const sourceCatalog = await Bun.file("static/shop/v1.json").json();

function deepClone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value));
}

function dedupeCatalogEntries(entries: any[]) {
  const seen = new Set<string>();
  const deduped: any[] = [];

  for (const entry of entries) {
    const offerId =
      typeof entry?.offerId === "string" && entry.offerId.length > 0
        ? entry.offerId
        : JSON.stringify(entry?.itemGrants ?? entry ?? {});
    if (seen.has(offerId)) {
      continue;
    }
    seen.add(offerId);
    deduped.push(entry);
  }

  return deduped;
}

function normalizeSharedCatalog(catalog: any) {
  const normalized = deepClone(catalog ?? {});
  const storefronts = Array.isArray(normalized.storefronts)
    ? normalized.storefronts
    : [];

  const findEntries = (names: string[]) => {
    for (const name of names) {
      const storefront = storefronts.find((entry: any) => entry?.name === name);
      if (storefront && Array.isArray(storefront.catalogEntries) && storefront.catalogEntries.length > 0) {
        return deepClone(storefront.catalogEntries);
      }
    }
    return [];
  };

  const dailyEntries = dedupeCatalogEntries(
    findEntries(["BRDailyStorefront", "BRSpecialDaily"])
  );
  const featuredEntries = dedupeCatalogEntries(
    findEntries(["BRWeeklyStorefront", "BRSpecialFeatured"])
  );

  const upsertStorefront = (name: string, entries: any[]) => {
    const existing = storefronts.find((entry: any) => entry?.name === name);
    if (existing) {
      existing.catalogEntries = deepClone(entries);
      return;
    }
    storefronts.push({
      name,
      catalogEntries: deepClone(entries),
    });
  };

  upsertStorefront("BRDailyStorefront", dailyEntries);
  upsertStorefront("BRWeeklyStorefront", featuredEntries);
  upsertStorefront("BRSeasonalStorefront", []);
  upsertStorefront("BRSpecialDaily", []);
  upsertStorefront("BRSpecialFeatured", []);

  normalized.storefronts = storefronts;
  normalized.expiration = "9999-12-31T23:59:59.999Z";

  return normalized;
}

const sharedCatalog = normalizeSharedCatalog(sourceCatalog);

export default function () {
  app.get("/fortnite/api/storefront/v2/keychain", async (c) => {
    return c.json(keychain);
  });

  app.get("/catalog/api/shared/bulk/offers", async (c) => {
    return c.json([]);
  });

  app.get("/fortnite/api/storeaccess/v1/request_access/:accountId", async (c) => {
    return c.json([]);
  });

  app.get("/affiliate/api/public/affiliates/slug/:affiliateName", async (c) => {
    const affiliateName = c.req.param("affiliateName");
    return c.json({
      id: "aabbccddeeff11223344556677889900",
      slug: affiliateName,
      displayName: affiliateName,
      status: "ACTIVE",
      verified: true,
    });
  });

  app.get("/fortnite/api/storefront/v2/catalog", async (c) => {
    const useragent: any = c.req.header("user-agent");
    if (!useragent) return c.json(Atlas.internal.invalidUserAgent);

    const totalEntries = Array.isArray(sharedCatalog.storefronts)
      ? sharedCatalog.storefronts.reduce(
          (count: number, storefront: any) =>
            count +
            (Array.isArray(storefront?.catalogEntries)
              ? storefront.catalogEntries.length
              : 0),
          0
        )
      : 0;
    logger.debug(
      `[SHOP] shared catalog served storefronts=${sharedCatalog.storefronts?.length ?? 0} entries=${totalEntries}`
    );

    return c.json(sharedCatalog);
  });
}
