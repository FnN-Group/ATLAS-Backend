// @ts-ignore - No types available for discord-rich-presence
import DiscordRichPresence from "discord-rich-presence";
import logger from "./logger/logger";

// Discord Application Client ID
const CLIENT_ID = "1469880369573658645"; // Your new Application ID

let client: any = null;
let isConnected = false;
let reconnectTimer: Timer | null = null;
let hasLoggedConnectionWarning = false;
const RECONNECT_DELAY = 15000; // 15 seconds

/**
 * Initialize Discord Rich Presence
 */
export async function initializeDiscordRPC(): Promise<void> {
  if (!CLIENT_ID || CLIENT_ID.length === 0) {
    logger.warning("Discord RPC: Client ID not configured. Skipping initialization.");
    return;
  }

  logger.info(`Discord RPC: Attempting to connect with Client ID: ${CLIENT_ID}`);
  
  try {
    // Wrap the entire client creation in a promise to catch async errors
    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error("Connection timeout"));
      }, 12000);
      
      try {
        client = DiscordRichPresence(CLIENT_ID);
        
        // Give it time to connect
        setTimeout(() => {
          try {
            if (client) {
              client.updatePresence({
                details: "ATLAS Backend Running",
                state: "Idle",
                startTimestamp: Date.now(),
                largeImageKey: "atlas_logo",
                largeImageText: "ATLAS",
                instance: false,
              });
              
              clearTimeout(timeout);
              isConnected = true;
              hasLoggedConnectionWarning = false;
              logger.info("Discord RPC: Connected successfully");
              resolve();
            } else {
              clearTimeout(timeout);
              reject(new Error("Client is null"));
            }
          } catch (err) {
            clearTimeout(timeout);
            reject(err);
          }
        }, 1500);
      } catch (err) {
        clearTimeout(timeout);
        reject(err);
      }
    });
    
  } catch (error) {
    isConnected = false;
    const errorMessage = String(error);
    
    if (!hasLoggedConnectionWarning) {
      logger.warning("Discord RPC: Could not connect to Discord");
      logger.info("The backend will continue running without Rich Presence");
      logger.info("To enable: Ensure Discord desktop is running and restart ATLAS");
      hasLoggedConnectionWarning = true;
    }
    
    // Don't schedule reconnect to avoid repeated crashes
    // scheduleReconnect();
  }
}

/**
 * Update Discord Rich Presence with custom activity
 */
export function updateDiscordPresence(
  details: string,
  state?: string,
  startTimestamp?: number
): void {
  if (!client || !isConnected) return;

  try {
    client.updatePresence({
      details,
      state: state || undefined,
      startTimestamp: startTimestamp || Date.now(),
      largeImageKey: "atlas_logo",
      largeImageText: "ATLAS",
      instance: false,
    });
  } catch (error) {
    logger.error(`Discord RPC: Failed to update presence - ${error}`);
  }
}

/**
 * Update presence with server stats
 */
export function updateServerStats(activeConnections: number, port: number): void {
  if (!client || !isConnected) return;

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
  if (!client || !isConnected) return;

  try {
    client.disconnect();
  } catch (error) {
    logger.error(`Discord RPC: Failed to clear presence - ${error}`);
  }
}

/**
 * Disconnect from Discord RPC
 */
export async function disconnectDiscordRPC(): Promise<void> {
  if (reconnectTimer) {
    clearTimeout(reconnectTimer);
    reconnectTimer = null;
  }

  if (client && isConnected) {
    try {
      client.disconnect();
      logger.info("Discord RPC: Disconnected");
    } catch (error) {
      logger.error(`Discord RPC: Error during disconnect - ${error}`);
    }
  }

  client = null;
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
