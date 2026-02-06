import app from "..";

const emptyList: unknown[] = [];
const defaultSettings = {
  acceptInvites: "friends",
  invitePermission: "all",
  mutualPrivacy: "all",
  inviteTimeoutSeconds: 0,
};

export default function () {
  app.get("/friends/api/public/friends/:accountId", async (c) => {
    return c.json(emptyList);
  });

  app.get("/friends/api/public/blocklist/:accountId", async (c) => {
    return c.json(emptyList);
  });

  app.get("/friends/api/public/list/fortnite/:accountId/recentPlayers", async (c) => {
    return c.json(emptyList);
  });

  app.get("/friends/api/v1/:accountId/settings", async (c) => {
    return c.json(defaultSettings);
  });
}
