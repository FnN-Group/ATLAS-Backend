import app from "..";
import crypto from "crypto";
import fs from "node:fs";
import path from "node:path";
import getVersion from "../utils/handlers/getVersion";
// Cache for hotfix files to avoid repeated disk reads
const hotfixCache = new Map<
  string,
  { content: string; mtimeMs: number; size: number }
>();

export default function () {
  app.get("/fortnite/api/cloudstorage/system", async (c) => {
    try {
      const hotfixesDir = path.join(__dirname, "../../static/hotfixes");
      const csFiles: any = [];

      const files = await fs.promises.readdir(hotfixesDir);
      for (const file of files) {
        const filePath = path.join(hotfixesDir, file);
        const [f, fileStat] = await Promise.all([
          fs.promises.readFile(filePath),
          fs.promises.stat(filePath)
        ]);

        csFiles.push({
          uniqueFilename: file,
          filename: file,
          hash: crypto.createHash("sha1").update(f as any).digest("hex"),
          hash256: crypto.createHash("sha256").update(f as any).digest("hex"),
          length: fileStat.size,
          contentType: "application/octet-stream",
          uploaded: new Date().toISOString(),
          storageType: "S3",
          storageIds: {},
          doNotCache: true,
        });
      }

      return c.json(csFiles);
    } catch (err) {
      console.error("Error fetching system cloudstorage:", err);
      return c.status(500);
    }
  });

  app.get("/fortnite/api/cloudstorage/system/config", async (c) => {
    try {
      const hotfixesDir = path.join(__dirname, "../../static/hotfixes");
      const csFiles: any = [];

      const files = await fs.promises.readdir(hotfixesDir);
      for (const file of files) {
        const filePath = path.join(hotfixesDir, file);
        const [f, fileStat] = await Promise.all([
          fs.promises.readFile(filePath),
          fs.promises.stat(filePath)
        ]);

        csFiles.push({
          uniqueFilename: file,
          filename: file,
          hash: crypto.createHash("sha1").update(f as any).digest("hex"),
          hash256: crypto.createHash("sha256").update(f as any).digest("hex"),
          length: fileStat.size,
          contentType: "application/octet-stream",
          uploaded: new Date().toISOString(),
          storageType: "S3",
          storageIds: {},
          doNotCache: true,
        });
      }

      return c.json(csFiles);
    } catch (err) {
      console.error("Error fetching system config cloudstorage:", err);
      return c.status(500);
    }
  });

  app.get("/fortnite/api/cloudstorage/system/:file", async (c) => {
    try {
      const version = getVersion(c);
      const fileName = c.req.param("file");
      const filePath = path.join(
        __dirname,
        "../../static/hotfixes",
        fileName
      );
      
      // Revalidate cache using file metadata so runtime edits are picked up.
      const fileStat = await fs.promises.stat(filePath);

      let fileContent: string;
      const cached = hotfixCache.get(fileName);
      if (
        cached &&
        cached.mtimeMs === fileStat.mtimeMs &&
        cached.size === fileStat.size
      ) {
        fileContent = cached.content;
      } else {
        // Load from disk and refresh cache.
        fileContent = await fs.promises.readFile(filePath, { encoding: "utf8" });
        hotfixCache.set(fileName, {
          content: fileContent,
          mtimeMs: fileStat.mtimeMs,
          size: fileStat.size,
        });
      }

      if (fileName === "DefaultGame.ini") {
        const replacements: {
          [key: number]: { find: string; replace: string };
        } = {
          7.3: {
            find: "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Low, PlaylistAccess=(bEnabled=false, CategoryIndex=1, DisplayPriority=-999))",
            replace:
              "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Low, PlaylistAccess=(bEnabled=true, CategoryIndex=1, DisplayPriority=-999))",
          },
          7.4: {
            find: "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_High, PlaylistAccess=(bEnabled=false, CategoryIndex=1, DisplayPriority=-999))",
            replace:
              "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_High, PlaylistAccess=(bEnabled=true, CategoryIndex=1, DisplayPriority=-999))",
          },
          8.51: {
            find: "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Med, PlaylistAccess=(bEnabled=false, CategoryIndex=1, DisplayPriority=-999))",
            replace:
              "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Med, PlaylistAccess=(bEnabled=true, CategoryIndex=1, DisplayPriority=-999))",
          },
          9.4: {
            find: "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Higher, PlaylistAccess=(bEnabled=false, CategoryIndex=1, DisplayPriority=-999))",
            replace:
              "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Higher, PlaylistAccess=(bEnabled=true, CategoryIndex=1, DisplayPriority=-999))",
          },
          9.41: {
            find: "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Higher, PlaylistAccess=(bEnabled=false, CategoryIndex=1, DisplayPriority=-999))",
            replace:
              "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Higher, PlaylistAccess=(bEnabled=true, CategoryIndex=1, DisplayPriority=-999))",
          },
          10.4: {
            find: "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Highest, PlaylistAccess=(bEnabled=false, CategoryIndex=1, DisplayPriority=-999))",
            replace:
              "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Highest, PlaylistAccess=(bEnabled=true, CategoryIndex=1, DisplayPriority=-999))",
          },
          11.3: {
            find: "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Lowest, PlaylistAccess=(bEnabled=false, CategoryIndex=1, DisplayPriority=-999))",
            replace:
              "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Lowest, PlaylistAccess=(bEnabled=true, CategoryIndex=1, DisplayPriority=-999))",
          },
          12.41: {
            find: "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_High, PlaylistAccess=(bEnabled=false, CategoryIndex=1, DisplayPriority=-999))",
            replace:
              "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_High, PlaylistAccess=(bEnabled=true, CategoryIndex=1, DisplayPriority=-999))",
          },
          12.61: {
            find: "+FrontEndPlaylistData=(PlaylistName=Playlist_Fritter_64, PlaylistAccess=(bEnabled=false, CategoryIndex=1, DisplayPriority=-999))",
            replace:
              "+FrontEndPlaylistData=(PlaylistName=Playlist_Fritter_64, PlaylistAccess=(bEnabled=true, CategoryIndex=1, DisplayPriority=-999))",
          },
        };

        const replacement = replacements[version.build];
        if (replacement) {
          fileContent = fileContent.replace(
            replacement.find,
            replacement.replace
          );
        }
      }

      c.header("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate");
      c.header("Pragma", "no-cache");
      c.header("Expires", "0");
      return c.text(fileContent);
    } catch (err) {
      console.error("Error fetching system file:", err);
      return c.notFound();
    }
  });

  app.get("/fortnite/api/cloudstorage/user/:accountId", async (c) => {
    const accountId = c.req.param("accountId");
    try {
      const clientSettingsPath = path.join(
        __dirname,
        "..",
        "..",
        "static",
        "ClientSettings",
        accountId
      );
      await fs.promises.mkdir(clientSettingsPath, { recursive: true });

      const ver = getVersion(c);

      const file = path.join(
        clientSettingsPath,
        `ClientSettings-${ver.season}.Sav`
      );

      try {
        const parsedFile = await fs.promises.readFile(file);
        const parsedStats = await fs.promises.stat(file);

        return c.json([
          {
            uniqueFilename: "ClientSettings.Sav",
            filename: "ClientSettings.Sav",
            hash: crypto.createHash("sha1").update(parsedFile).digest("hex"),
            hash256: crypto
              .createHash("sha256")
              .update(parsedFile)
              .digest("hex"),
            length: parsedStats.size,
            contentType: "application/octet-stream",
            uploaded: parsedStats.mtime,
            storageType: "S3",
            storageIds: {},
            accountId: accountId,
            doNotCache: false,
          },
        ]);
      } catch {
        // File doesn't exist
        return c.json([]);
      }
    } catch (err) {
      console.error("Error fetching user cloudstorage:", err);
      c.status(500);
      return c.json([]);
    }
  });

  app.put("/fortnite/api/cloudstorage/user/:accountId/:file", async (c) => {
    const filename = c.req.param("file");
    const accountId = c.req.param("accountId");

    const clientSettingsPath = path.join(
        __dirname,
        "..",
        "..",
        "static",
        "ClientSettings",
        accountId
      );
    
    if (filename.toLowerCase() !== "clientsettings.sav") {
      return c.json([]);
    }

    const ver = getVersion(c);

    const file = path.join(
      clientSettingsPath,
      `ClientSettings-${ver.season}.Sav`
    );

    try {
      const body = await c.req.arrayBuffer();
      const buffer = Buffer.from(body);

      await fs.promises.mkdir(clientSettingsPath, { recursive: true });

      // Write atomically to avoid partial/corrupt saves if the process exits mid-write.
      const tmpFile = `${file}.${process.pid}.${Date.now()}.tmp`;
      try {
        await fs.promises.writeFile(tmpFile, buffer);
        await fs.promises.rename(tmpFile, file);
      } finally {
        // Best-effort cleanup (rename may fail and leave tmp behind).
        fs.promises.unlink(tmpFile).catch(() => {});
      }

      return c.json([]);
    } catch (error) {
      console.error("Error writing ClientSettings:", error);

      return c.json({ error: "Failed to save the settings" }, 500);
    }
  });

  app.get("/fortnite/api/cloudstorage/user/:accountId/:file", async (c) => {
    const accountId = c.req.param("accountId");
    const clientSettingsPath = path.join(
        __dirname,
        "..",
        "..",
        "static",
        "ClientSettings",
        accountId
      );
    await fs.promises.mkdir(clientSettingsPath, { recursive: true });

    const ver = getVersion(c);

    const file = path.join(
      clientSettingsPath,
      `ClientSettings-${ver.season}.Sav`
    );

    try {
      const data = await fs.promises.readFile(file);
      return c.body(data as any);
    } catch {
      return c.json([]);
    }
  });
}
