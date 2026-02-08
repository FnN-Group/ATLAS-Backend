# Discord Rich Presence Setup Guide

This guide will help you set up Discord Rich Presence for your ATLAS Backend.

## Prerequisites
- Discord desktop app installed and running
- An active Discord account

## Setup Steps

### 1. Create a Discord Application

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Click **"New Application"**
3. Enter a name (e.g., "ATLAS Backend")
4. Click **"Create"**
5. Copy your **Application ID** from the "Application" tab

### 2. Upload Rich Presence Assets (Optional but Recommended)

1. In your Discord Application, go to **"Rich Presence" → "Art Assets"**
2. Upload an image for your logo (recommended: 1024x1024 PNG)
3. Name it `atlas_logo` (this matches the config in the code)
4. Click **"Save Changes"**

### 3. Configure Your Backend

1. Open `src/utils/discordRPC.ts`
2. Replace `YOUR_DISCORD_CLIENT_ID_HERE` with your Application ID:
   ```typescript
   const CLIENT_ID = "1234567890123456789"; // Your Application ID here
   ```
3. Save the file

### 4. Run Your Backend

Start your ATLAS Backend normally. You should see:
```
Discord RPC: Connected successfully
```

If Discord is not running, you'll see:
```
Discord RPC: Failed to initialize
Discord RPC: Attempting to reconnect...
```

The system will automatically retry every 15 seconds.

## Customizing Your Presence

### Update Presence from Anywhere

You can update the Discord presence from any part of your code:

```typescript
import { updateDiscordPresence } from "./utils/discordRPC";

// Simple update
updateDiscordPresence("Processing requests", "5 active users");

// With custom timestamp
updateDiscordPresence("Backend Active", "Idle", Date.now());
```

### Available Functions

- `initializeDiscordRPC()` - Initialize connection (called automatically on startup)
- `updateDiscordPresence(details, state?, timestamp?)` - Update presence
- `updateServerStats(connections, port)` - Update with server stats
- `clearDiscordPresence()` - Clear the presence
- `disconnectDiscordRPC()` - Disconnect (called automatically on shutdown)
- `isDiscordRPCConnected()` - Check connection status

## Troubleshooting

### Discord RPC Not Showing

1. **Ensure Discord is running** - The desktop app must be open
2. **Check your Client ID** - Make sure it matches your Application ID
3. **Check Discord settings** - Go to Settings → Activity Privacy → "Display current activity as a status message" must be enabled
4. **Wait a moment** - It can take 15-20 seconds for the presence to appear

### Connection Issues

- The system automatically reconnects if Discord closes and reopens
- Check console logs for error messages
- Ensure the `discord-rpc` package is installed: `bun add discord-rpc`

## Example Presence Output

When configured correctly, users will see:

```
Playing ATLAS Backend
ATLAS Backend Active
Running on port 3551
```

With your logo and "elapsed time" indicator.

## Disabling Discord RPC

If you want to disable Discord RPC:

1. Keep the Client ID as `YOUR_DISCORD_CLIENT_ID_HERE`
2. The system will automatically skip initialization

Or comment out these lines in `src/index.ts`:

```typescript
// await initializeDiscordRPC();
// updateDiscordPresence("ATLAS Backend Active", `Running on port ${PORT}`);
```
