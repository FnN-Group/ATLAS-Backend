import app, { setStatusMessage } from "..";
import jwt from "jsonwebtoken";
import getVersion from "../utils/handlers/getVersion";
import {
  getConfiguredGameServer,
  getConfiguredMatchmakerUrl,
  parseHostPort,
} from "../utils/matchmaking/config";

interface MatchmakingSessionInfo {
  buildUniqueId: string;
  serverAddress: string;
  serverPort: number;
  playlistName: string;
  region: string;
}

const matchmakingSessions: Record<string, MatchmakingSessionInfo> = {};

function getAccountIdFromRequest(c: any): string {
  const token = c.req.header("Authorization")?.replace("bearer ", "");
  if (!token) {
    return "default";
  }

  try {
    const decoded = jwt.verify(token, "LVe51Izk03lzceNf1ZGZs0glGx5tKh7f") as any;
    return decoded.accountId || "default";
  } catch {
    return "default";
  }
}

function getStoredSessionInfo(accountId: string): MatchmakingSessionInfo {
  const stored = matchmakingSessions[accountId];
  if (stored) {
    return stored;
  }

  const configuredServer = getConfiguredGameServer();
  return {
    buildUniqueId: "0",
    serverAddress: configuredServer.host,
    serverPort: configuredServer.port,
    playlistName: "Playlist_DefaultSolo",
    region: "NAE",
  };
}

export default function () {
  app.get("/waitingroom/api/waitingroom", async (c) => {
    return c.json([]);
  });
  app.get("/fortnite/api/matchmaking/session/findPlayer/:id", async (c) => {
    return c.json([]);
  });

  app.get("/fortnite/api/game/v2/matchmakingservice/ticket/player/*", async (c) => {
    const bucketId = c.req.query("bucketId") ?? "";
    const playerMatchmakingKey = c.req.query("player.option.customKey");
    const bucketParts = bucketId.split(":");
    const playerPlaylist = bucketParts[3] || "Playlist_DefaultSolo";
    const playerRegion = bucketParts[2] || "NAE";
    const ver = getVersion(c);
    const accountId = getAccountIdFromRequest(c);

    const configuredServer = getConfiguredGameServer();
    const customServer =
      typeof playerMatchmakingKey === "string" ? parseHostPort(playerMatchmakingKey) : null;
    const selectedServer = customServer ?? configuredServer;

    matchmakingSessions[accountId] = {
      buildUniqueId: bucketParts[0] || "0",
      serverAddress: selectedServer.host,
      serverPort: selectedServer.port,
      playlistName: playerPlaylist,
      region: playerRegion,
    };

    setStatusMessage(`\x1b[33m[MATCHMAKING]\x1b[0m Ticket created for ${accountId}`);

    const mmData = jwt.sign(
      {
        region: playerRegion,
        playlist: playerPlaylist,
        type: customServer ? "custom" : "normal",
        key: customServer ? playerMatchmakingKey : undefined,
        bucket: bucketId,
        version: `${ver.build}`,
        accountId: accountId,
      },
      "LVe51Izk03lzceNf1ZGZs0glGx5tKh7f",
    );
    var data = mmData.split(".");
    return c.json({
      serviceUrl: getConfiguredMatchmakerUrl(),
      ticketType: "mms-player",
      payload: data[0],
      signature: "account",
    });
  });

  app.post("/fortnite/api/matchmaking/session/:SessionId/join", async (c) => {
    return c.json([]);
  });

  app.get("/fortnite/api/matchmaking/session/:sessionId", async (c) => {
    const sessionId = c.req.param("sessionId");
    setStatusMessage(`\x1b[33m[MATCHMAKING]\x1b[0m Joining session...`);

    const accountId = getAccountIdFromRequest(c);
    const sessionInfo = getStoredSessionInfo(accountId);
    const addressWithPort = `${sessionInfo.serverAddress}:${sessionInfo.serverPort}`;
    const linkId = `${sessionInfo.playlistName.toLowerCase()}?v=95`;
    setStatusMessage(`\x1b[33m[MATCHMAKING]\x1b[0m Connecting to server...`);

    return c.json({
      id: sessionId,
      ownerId: crypto.randomUUID().replace(/-/gi, "").toUpperCase(),
      ownerName: "[DS]fortnite-liveeugcec1c2e30ubrcore0a-z8hj-1968",
      serverName: "[DS]fortnite-liveeugcec1c2e30ubrcore0a-z8hj-1968",
      serverAddress: sessionInfo.serverAddress,
      serverPort: sessionInfo.serverPort,
      maxPublicPlayers: 220,
      openPublicPlayers: 175,
      maxPrivatePlayers: 0,
      openPrivatePlayers: 0,
      attributes: {
        REGION_s: sessionInfo.region,
        GAMEMODE_s: "FORTATHENA",
        ALLOWBROADCASTING_b: true,
        SUBREGION_s: "GB",
        DCID_s: "FORTNITE-LIVEEUGCEC1C2E30UBRCORE0A-14840880",
        tenant_s: "Fortnite",
        MATCHMAKINGPOOL_s: "Any",
        STORMSHIELDDEFENSETYPE_i: 0,
        HOTFIXVERSION_i: 0,
        PLAYLISTNAME_s: sessionInfo.playlistName,
        SESSIONKEY_s: crypto.randomUUID().replace(/-/gi, "").toUpperCase(),
        TENANT_s: "Fortnite",
        BEACONPORT_i: 15009,
        ALLOWMIGRATION_s: "false",
        REJOINAFTERKICK_s: "OPEN",
        CHECKSANCTIONS_s: "false",
        BUCKET_s: "",
        DEPLOYMENT_s: "Fortnite",
        LASTUPDATED_s: new Date().toISOString(),
        LINKID_s: linkId,
        allowMigration_s: false,
        ALLOWREADBYID_s: "false",
        SERVERADDRESS_s: addressWithPort,
        NETWORKMODULE_b: true,
        lastUpdated_s: new Date().toISOString(),
        allowReadById_s: false,
        serverAddress_s: addressWithPort,
        LINKTYPE_s: "BR:Playlist",
        deployment_s: "Fortnite",
        ADDRESS_s: addressWithPort,
        bucket_s: "",
        checkSanctions_s: false,
        rejoinAfterKick_s: "OPEN",
      },
      publicPlayers: [],
      privatePlayers: [],
      totalPlayers: 45,
      allowJoinInProgress: false,
      shouldAdvertise: false,
      isDedicated: false,
      usesStats: false,
      allowInvites: false,
      usesPresence: false,
      allowJoinViaPresence: true,
      allowJoinViaPresenceFriendsOnly: false,
      buildUniqueId: sessionInfo.buildUniqueId,
      lastUpdated: new Date().toISOString(),
      started: false,
    });
  });

  app.get("/fortnite/api/matchmaking/session/matchMakingRequest", async (c) => {
    setStatusMessage("\x1b[33m[MATCHMAKING]\x1b[0m Request received");
    return c.json([]);
  });

  app.get("/fortnite/api/game/v2/matchmaking/account/:accountId/session/:sessionId", async (c) => {
    const accountId = c.req.param("accountId");
    const sessionId = c.req.param("sessionId");
    setStatusMessage(`\x1b[33m[MATCHMAKING]\x1b[0m Session validation`);
    
    return c.json({
      accountId: accountId,
      sessionId: sessionId,
      key: "none",
    });
  });

  app.post("/fortnite/api/game/v2/matchmaking/account/:accountId/session/:sessionId", async (c) => {
    const accountId = c.req.param("accountId");
    const sessionId = c.req.param("sessionId");
    setStatusMessage(`\x1b[33m[MATCHMAKING]\x1b[0m Session confirmed`);
    
    return c.json({
      accountId: accountId,
      sessionId: sessionId,
      key: crypto.randomUUID().replace(/-/gi, ""),
    });
  });
}
