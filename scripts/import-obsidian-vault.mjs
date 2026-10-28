#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import LZString from "lz-string";

const PAGE_SIZE = 200;
const NAME_MAX = 255;

const USAGE = `Import Excalidraw files from an Obsidian vault into ExcaliDash.

Usage:
  EXCALIDASH_URL=https://draw.example.com \\
  EXCALIDASH_API_KEY=exd_... \\
  node scripts/import-obsidian-vault.mjs --vault <path> [--dry-run]

Options:
  --vault <path>  Obsidian vault root. Required.
  --dry-run       Parse and report without uploading.
  --help          Show this message.

Reads .excalidraw files and Obsidian .excalidraw.md scenes (compressed-json or
json blocks). Drawings whose name already exists are skipped, so reruns are safe.
`;

const fail = (message) => {
  process.stderr.write(`error: ${message}\n`);
  process.exit(1);
};

const parseArgs = (argv) => {
  const args = { vault: null, dryRun: false, help: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--help") args.help = true;
    else if (arg === "--dry-run") args.dryRun = true;
    else if (arg === "--vault") {
      args.vault = argv[i + 1];
      i += 1;
    } else fail(`unknown argument: ${arg}`);
  }
  return args;
};

const walk = (dir, out = []) => {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === ".git" || entry.name === "node_modules") continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (/\.excalidraw(\.md)?$/i.test(entry.name)) out.push(full);
  }
  return out;
};

const extractBlock = (text, tag) => {
  const match = text.match(
    new RegExp("```" + tag + "\\s*\\n([\\s\\S]*?)\\n```"),
  );
  return match ? match[1] : null;
};

const readScene = (file) => {
  const text = fs.readFileSync(file, "utf8");
  if (file.toLowerCase().endsWith(".excalidraw")) return JSON.parse(text);

  const compressed = extractBlock(text, "compressed-json");
  if (compressed) {
    const json = LZString.decompressFromBase64(compressed.replace(/\s+/g, ""));
    if (!json) throw new Error("compressed-json block did not decompress");
    return JSON.parse(json);
  }

  const plain = extractBlock(text, "json");
  if (plain) return JSON.parse(plain);
  throw new Error("no compressed-json or json block");
};

const sceneName = (root, file) =>
  path
    .relative(root, file)
    .replace(/\.excalidraw(\.md)?$/i, "")
    .slice(0, NAME_MAX);

const toPayload = (root, file) => {
  const scene = readScene(file);
  const files = scene.files;
  return {
    name: sceneName(root, file),
    elements: Array.isArray(scene.elements) ? scene.elements : [],
    appState:
      scene.appState && typeof scene.appState === "object"
        ? scene.appState
        : {},
    ...(files && Object.keys(files).length ? { files } : {}),
  };
};

const api = async (config, pathname, init = {}) => {
  const res = await fetch(`${config.url}/api${pathname}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${config.apiKey}`,
      ...(init.headers || {}),
    },
  });
  if (!res.ok) {
    const detail = (await res.text()).slice(0, 300);
    throw new Error(
      `${init.method || "GET"} ${pathname} -> ${res.status}: ${detail}`,
    );
  }
  return res;
};

const listExisting = async (config) => {
  const names = new Set();
  let offset = 0;
  for (;;) {
    const res = await api(
      config,
      `/drawings?limit=${PAGE_SIZE}&offset=${offset}`,
    );
    const page = await res.json();
    for (const drawing of page.drawings ?? []) names.add(drawing.name);
    offset += (page.drawings ?? []).length;
    if (offset >= (page.totalCount ?? offset) || !(page.drawings ?? []).length)
      break;
  }
  return names;
};

const main = async () => {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    process.stdout.write(USAGE);
    return;
  }
  if (!args.vault) fail("--vault is required");

  const vault = path.resolve(args.vault);
  if (!fs.existsSync(vault)) fail(`vault not found: ${vault}`);

  const files = walk(vault).sort();
  const scenes = [];
  for (const file of files) {
    try {
      scenes.push({ file, payload: toPayload(vault, file) });
    } catch (error) {
      process.stderr.write(
        `skip ${path.relative(vault, file)}: ${error.message}\n`,
      );
    }
  }
  process.stdout.write(
    `found ${files.length} excalidraw files, parsed ${scenes.length}\n`,
  );

  if (args.dryRun) return;

  const url = (process.env.EXCALIDASH_URL ?? "").replace(/\/+$/, "");
  const apiKey = process.env.EXCALIDASH_API_KEY ?? "";
  if (!url) fail("EXCALIDASH_URL is required");
  if (!apiKey) fail("EXCALIDASH_API_KEY is required");

  const config = { url, apiKey };
  const existing = await listExisting(config);
  process.stdout.write(`existing drawings: ${existing.size}\n`);

  let created = 0;
  let skipped = 0;
  let failed = 0;
  for (const { payload } of scenes) {
    if (existing.has(payload.name)) {
      skipped += 1;
      process.stdout.write(`skip ${payload.name}\n`);
      continue;
    }
    try {
      await api(config, "/drawings", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(payload),
      });
      created += 1;
      process.stdout.write(
        `create ${payload.name} (${payload.elements.length} elements)\n`,
      );
    } catch (error) {
      failed += 1;
      process.stderr.write(`failed ${payload.name}: ${error.message}\n`);
    }
  }

  process.stdout.write(
    `done created=${created} skipped=${skipped} failed=${failed}\n`,
  );
  if (failed > 0) process.exitCode = 1;
};

main().catch((error) => fail(error.message));
