import DiscordRPC from "discord-rpc";
import logger from "./logger/logger";

// ============================================
// SET TO false TO DISABLE DISCORD RPC
// ============================================
const ENABLE_DISCORD_RPC = false;

// Discord Application Client ID - You'll need to create an application at https://discord.com/developers/applications
const CLIENT_ID: string = "1469880369573658645"; // Replace with your Discord Application ID

let rpc: DiscordRPC.Client | null = null;
let isConnected = false;
let reconnectTimer: Timer | null = null;
let hasLoggedConnectionWarning = false;
const RECONNECT_DELAY = 15000; // 15 seconds

/**
 * Initialize Discord Rich Presence
 */
export async function initializeDiscordRPC(): Promise<void> {
  if (!ENABLE_DISCORD_RPC) {
    logger.info("Discord RPC: Disabled (set ENABLE_DISCORD_RPC = true to enable)");
    return;
  }
  
  if (CLIENT_ID === "YOUR_DISCORD_CLIENT_ID_HERE") {
    logger.warning("Discord RPC: Client ID not configured. Skipping initialization.");
    logger.warning("To enable Discord RPC, create an application at https://discord.com/developers/applications");
    return;
  }

  try {
    rpc = new DiscordRPC.Client({ transport: "ipc" });

    rpc.on("ready", () => {
      isConnected = true;
      hasLoggedConnectionWarning = false; // Reset warning flag on successful connection
      logger.info("Discord RPC: Connected successfully");
      setDefaultPresence();
    });

    rpc.on("disconnected", () => {
      isConnected = false;
      logger.warning("Discord RPC: Disconnected");
      scheduleReconnect();
    });

    logger.info(`Discord RPC: Attempting to connect with Client ID: ${CLIENT_ID}`);
    await rpc.login({ clientId: CLIENT_ID });
  } catch (error) {
    const errorMessage = String(error);
    logger.error(`Discord RPC: Full error details - ${JSON.stringify(error, null, 2)}`);
    
    if (errorMessage.includes("RPC_CONNECTION_TIMEOUT")) {
      if (!hasLoggedConnectionWarning) {
        logger.warning("Discord RPC: Could not connect to Discord");
        logger.info("Possible solutions:");
        logger.info("  1. Ensure Discord desktop app is fully loaded (wait 10-15 seconds after opening)");
        logger.info("  2. In Discord: Settings → Activity Privacy → Enable 'Display current activity as a status message'");
        logger.info("  3. Try restarting Discord");
        logger.info("  4. Verify your Application ID at https://discord.com/developers/applications");
        logger.info("Discord RPC will retry automatically every 15 seconds");
        hasLoggedConnectionWarning = true;
      }
    } else {
      logger.error(`Discord RPC: Failed to initialize - ${error}`);
    }
    
    scheduleReconnect();
  }
}

/**
 * Set the default presence (shown when backend is idle)
 */
function setDefaultPresence(): void {
  if (!rpc || !isConnected) return;

  rpc.setActivity({
    details: "ATLAS Backend Running",
    state: "Idle",
    startTimestamp: Date.now(),
    largeImageKey: "atlas_logo", // Upload this in your Discord Developer Portal
    largeImageText: "ATLAS",
    instance: false,
  }).catch((error) => {
    logger.error(`Discord RPC: Failed to set presence - ${error}`);
  });
}

/**
 * Update Discord Rich Presence with custom activity
 * @param details Main line of text (e.g., "Processing request")
 * @param state Secondary line of text (e.g., "Active users: 5")
 * @param startTimestamp Optional timestamp for "elapsed" timer
 */
export function updateDiscordPresence(
  details: string,
  state?: string,
  startTimestamp?: number
): void {
  if (!rpc || !isConnected) return;

  const activity: DiscordRPC.Presence = {
    details,
    startTimestamp: startTimestamp || Date.now(),
    largeImageKey: "atlas_logo",
    largeImageText: "ATLAS",
    instance: false,
  };

  if (state) {
    activity.state = state;
  }

  rpc.setActivity(activity).catch((error) => {
    logger.error(`Discord RPC: Failed to update presence - ${error}`);
  });
}

/**
 * Update presence with server stats
 * @param activeConnections Number of active connections
 * @param port Server port
 */
export function updateServerStats(activeConnections: number, port: number): void {
  if (!rpc || !isConnected) return;

  updateDiscordPresence(
    "ATLAS Backend Active",
    `Port ${port} | ${activeConnections} connection${activeConnections !== 1 ? 's' : ''}`,
    Date.now()
  );
}

/**
 * Clear Discord Rich Presence
 */
export function clearDiscordPresence(): void {
  if (!rpc || !isConnected) return;

  rpc.clearActivity().catch((error) => {
    logger.error(`Discord RPC: Failed to clear presence - ${error}`);
  });
}

/**
 * Disconnect from Discord RPC
 */
export async function disconnectDiscordRPC(): Promise<void> {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }

  if (rpc && isConnected) {
    try {
      await rpc.destroy();
      logger.info("Discord RPC: Disconnected");
    } catch (error) {
      logger.error(`Discord RPC: Error during disconnect - ${error}`);
    }
  }

  rpc = null;
  isConnected = false;
}

/**
 * Schedule a reconnection attempt
 */
function scheduleReconnect(): void {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
  }

  reconnectTimer = setTimeout(() => {
    // Silently attempt to reconnect - will log only on success or new errors
    initializeDiscordRPC();
  }, RECONNECT_DELAY);
}

/**
 * Check if Discord RPC is currently connected
 */
export function isDiscordRPCConnected(): boolean {
  return isConnected;
}

// Handle process termination
process.on("SIGINT", async () => {
  await disconnectDiscordRPC();
  process.exit(0);
});

process.on("SIGTERM", async () => {
  await disconnectDiscordRPC();
  process.exit(0);
});
