import fs from "node:fs";
import path from "node:path";

function normalizeAbsolutePath(input: string): string {
  return path.resolve(input);
}

function samePath(a: string, b: string): boolean {
  return normalizeAbsolutePath(a).toLowerCase() === normalizeAbsolutePath(b).toLowerCase();
}

function resolveInstallRoot(): string {
  const envRoot = process.env.ATLAS_INSTALL_ROOT?.trim();
  if (envRoot) {
    return normalizeAbsolutePath(envRoot);
  }

  return normalizeAbsolutePath(path.join(__dirname, "..", ".."));
}

function resolveDataRoot(installRoot: string): string {
  const envRoot = process.env.ATLAS_DATA_ROOT?.trim();
  if (envRoot) {
    return normalizeAbsolutePath(envRoot);
  }

  return installRoot;
}

const installRoot = resolveInstallRoot();
const dataRoot = resolveDataRoot(installRoot);

export function getAtlasInstallRoot(): string {
  return installRoot;
}

export function getAtlasDataRoot(): string {
  return dataRoot;
}

export function isUsingSeparateAtlasDataRoot(): boolean {
  return !samePath(installRoot, dataRoot);
}

export function atlasInstallPath(...parts: string[]): string {
  return path.join(installRoot, ...parts);
}

export function atlasDataPath(...parts: string[]): string {
  return path.join(dataRoot, ...parts);
}

export function atlasDataReadPath(...parts: string[]): string {
  const candidate = atlasDataPath(...parts);
  if (fs.existsSync(candidate)) {
    return candidate;
  }
  return atlasInstallPath(...parts);
}

function ensureDir(dirPath: string): void {
  fs.mkdirSync(dirPath, { recursive: true });
}

function copyFileIfMissing(relativePath: string): void {
  const sourcePath = atlasInstallPath(...relativePath.split("/"));
  const targetPath = atlasDataPath(...relativePath.split("/"));

  if (!fs.existsSync(sourcePath) || fs.existsSync(targetPath)) {
    return;
  }

  ensureDir(path.dirname(targetPath));
  fs.copyFileSync(sourcePath, targetPath);
}

function copyDirectoryContentsIfMissing(relativePath: string): void {
  const sourceRoot = atlasInstallPath(...relativePath.split("/"));
  const targetRoot = atlasDataPath(...relativePath.split("/"));

  if (!fs.existsSync(sourceRoot)) {
    return;
  }

  ensureDir(targetRoot);

  const entries = fs.readdirSync(sourceRoot, { withFileTypes: true });
  for (const entry of entries) {
    const childRelativePath = `${relativePath}/${entry.name}`;
    if (entry.isDirectory()) {
      copyDirectoryContentsIfMissing(childRelativePath);
      continue;
    }

    copyFileIfMissing(childRelativePath);
  }
}

export function ensureAtlasDataLayout(): void {
  ensureDir(dataRoot);
  ensureDir(atlasDataPath("logs"));
  ensureDir(atlasDataPath("exports"));
  ensureDir(atlasDataPath("responses"));
  ensureDir(atlasDataPath("src", "config"));
  ensureDir(atlasDataPath("static", "profiles"));
  ensureDir(atlasDataPath("static", "ClientSettings"));
  ensureDir(atlasDataPath("static", "hotfixes"));
  ensureDir(atlasDataPath("public", "items", "custom-groups"));

  if (!isUsingSeparateAtlasDataRoot()) {
    return;
  }

  copyDirectoryContentsIfMissing("static/hotfixes");
  copyDirectoryContentsIfMissing("static/profiles");
  copyDirectoryContentsIfMissing("static/athenaprofiles/Profile Presets");
  copyDirectoryContentsIfMissing("responses");
  copyDirectoryContentsIfMissing("static/ClientSettings/config");
}
