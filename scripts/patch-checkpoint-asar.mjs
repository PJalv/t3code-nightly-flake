import crypto from "node:crypto";
import fs from "node:fs";
import { createRequire } from "node:module";

const [diskModulePath, archivePath] = process.argv.slice(2);

if (!diskModulePath || !archivePath) {
  throw new Error("Usage: patch-checkpoint-asar.mjs <asar-disk.js> <app.asar>");
}

const require = createRequire(import.meta.url);
const disk = require(diskModulePath);
const archive = fs.readFileSync(archivePath);
const { header, headerSize } = disk.readArchiveHeaderSync(archivePath);
const file =
  header.files?.apps?.files?.server?.files?.dist?.files?.["bin.mjs"];

if (!file || file.unpacked || !file.integrity) {
  throw new Error("Packed desktop server bundle metadata was not found");
}

const fileStart = 8 + headerSize + Number.parseInt(file.offset, 10);
const fileEnd = fileStart + file.size;
const bundle = archive.subarray(fileStart, fileEnd);
const regionStartMarker = Buffer.from(
  "//#region src/orchestration/Layers/CheckpointReactor.ts",
);
const regionEndMarker = Buffer.from(
  "//#region src/orchestration/Layers/ThreadDeletionReactor.ts",
);
const startNeedle = Buffer.from('start: Effect.fn("start")(function* () {');
const endNeedle = Buffer.from("\n\t\t}),\n\t\tdrain: worker.drain");
const regionStart = bundle.indexOf(regionStartMarker);
const regionEnd = bundle.indexOf(regionEndMarker, regionStart);
const functionStart = bundle.indexOf(startNeedle, regionStart);
const functionEnd = bundle.indexOf(endNeedle, functionStart);

if (
  regionStart < 0 ||
  regionEnd < 0 ||
  functionStart < regionStart ||
  functionEnd < functionStart ||
  functionEnd > regionEnd
) {
  throw new Error("T3 Code desktop checkpoint reactor was not found");
}

const replacement = Buffer.from(
  startNeedle.toString() +
    ' if (process.env.T3_DISABLE_CHECKPOINTS === "1") return;',
);
const replaceLength = functionEnd - functionStart;

if (replacement.length > replaceLength) {
  throw new Error("Checkpoint guard does not fit in the existing ASAR entry");
}

bundle.fill(0x20, functionStart, functionEnd);
replacement.copy(bundle, functionStart);

const hash = (data) => crypto.createHash("sha256").update(data).digest("hex");
const newIntegrity = {
  hash: hash(bundle),
  blocks: [],
};

for (let offset = 0; offset < bundle.length; offset += file.integrity.blockSize) {
  newIntegrity.blocks.push(
    hash(bundle.subarray(offset, offset + file.integrity.blockSize)),
  );
}

const replaceHeaderHash = (oldHash, newHash) => {
  const headerEnd = 8 + headerSize;
  const oldBytes = Buffer.from(oldHash);
  const newBytes = Buffer.from(newHash);
  const hashOffset = archive.indexOf(oldBytes, 0);

  if (
    oldBytes.length !== newBytes.length ||
    hashOffset < 0 ||
    hashOffset >= headerEnd ||
    archive.indexOf(oldBytes, hashOffset + oldBytes.length) >= 0
  ) {
    throw new Error("Expected exactly one matching ASAR integrity hash");
  }
  newBytes.copy(archive, hashOffset);
};

replaceHeaderHash(file.integrity.hash, newIntegrity.hash);

if (file.integrity.blocks.length !== newIntegrity.blocks.length) {
  throw new Error("ASAR integrity block count changed unexpectedly");
}

for (let index = 0; index < file.integrity.blocks.length; index += 1) {
  replaceHeaderHash(file.integrity.blocks[index], newIntegrity.blocks[index]);
}

fs.writeFileSync(archivePath, archive);
