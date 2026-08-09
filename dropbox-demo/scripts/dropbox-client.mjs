#!/usr/bin/env node
/**
 * dropbox-client.mjs — Dropbox-like client script
 *
 * Implements the full upload flow from the Dropbox system design article:
 *   1. Compute SHA-256 fingerprint of the entire file
 *   2. POST /files/chunk/init — check for dedup or resumable upload
 *   3. If not dedup'd, split file into chunks and upload each:
 *      - Compute SHA-256 of each chunk
 *      - POST /files/chunk/upload?fileId=...&partNumber=...&chunkHash=...
 *   4. POST /files/chunk/complete — assemble the final blob
 *   5. Listen on SSE endpoint for sync notifications
 *
 * Usage:
 *   node dropbox-client.mjs upload <filePath> [--user-id <uuid>]
 *   node dropbox-client.mjs download <fileId> [--user-id <uuid>]
 *   node dropbox-client.mjs list [--user-id <uuid>]
 *   node dropbox-client.mjs share <fileId> <sharedWithUserId> [--user-id <uuid>]
 *   node dropbox-client.mjs sync [--user-id <uuid>]
 *   node dropbox-client.mjs changes [--since <iso8601>] [--user-id <uuid>]
 *
 * Requires Node.js 18+ (global fetch, crypto, fs/promises)
 */

import { createHash } from 'node:crypto';
import { readFile, open, stat } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { resolve, basename } from 'node:path';
import { parseArgs } from 'node:util';

// ============================================================
// Configuration
// ============================================================

const BASE_URL = process.env.DROPBOX_API_URL || 'http://localhost:8080/api/dropbox';
const CHUNK_SIZE = parseInt(process.env.DROPBOX_CHUNK_SIZE || '4194304', 10); // 4 MB

// ============================================================
// Helper functions
// ============================================================

function sha256(data) {
  return createHash('sha256').update(data).digest('hex');
}

async function sha256File(filePath) {
  return new Promise((resolve, reject) => {
    const hash = createHash('sha256');
    const stream = createReadStream(filePath);
    stream.on('data', chunk => hash.update(chunk));
    stream.on('end', () => resolve(hash.digest('hex')));
    stream.on('error', reject);
  });
}

async function sha256Chunk(filePath, start, length) {
  return new Promise((resolve, reject) => {
    const hash = createHash('sha256');
    const stream = createReadStream(filePath, { start, end: start + length - 1 });
    stream.on('data', chunk => hash.update(chunk));
    stream.on('end', () => resolve(hash.digest('hex')));
    stream.on('error', reject);
  });
}

function log(emoji, msg) {
  console.log(`${emoji}  ${msg}`);
}

function formatBytes(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

function getUserId(args) {
  const userId = args.values['user-id'] || process.env.DROPBOX_USER_ID;
  if (!userId) {
    console.error('❌  No user ID. Use --user-id <uuid> or set DROPBOX_USER_ID env var.');
    process.exit(1);
  }
  return userId;
}

// ============================================================
// 1) UPLOAD (chunked with fingerprinting)
// ============================================================

async function upload(filePath, args) {
  const userId = getUserId(args);
  const absPath = resolve(filePath);
  const fileName = basename(absPath);
  const fileStat = await stat(absPath);
  const fileSize = fileStat.size;

  log('📁', `Uploading: ${fileName} (${formatBytes(fileSize)})`);

  // Step 1: Compute fingerprint
  log('🔐', 'Computing SHA-256 fingerprint...');
  const fingerprint = await sha256File(absPath);
  log('🔐', `Fingerprint: ${fingerprint.substring(0, 32)}...`);

  // Step 2: Init chunked upload
  log('🚀', 'Initializing chunked upload...');
  const initResp = await fetch(`${BASE_URL}/files/chunk/init`, {
    method: 'POST',
    headers: {
      'X-User-Id': userId,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      fingerprint,
      name: fileName,
      size: fileSize,
      mimeType: 'application/octet-stream',
    }),
  });

  if (!initResp.ok) {
    console.error('❌  Init failed:', await initResp.text());
    process.exit(1);
  }

  const initData = await initResp.json();
  const fileId = initData.fileId;
  const totalChunks = initData.totalChunks;
  const uploadedChunks = new Set(initData.uploadedChunks || []);

  // Check dedup
  if (initData.dedup && initData.status === 'UPLOADED') {
    log('✅', `Dedup hit! File already exists. File ID: ${fileId}`);
    return;
  }

  log('📋', `File ID: ${fileId}`);
  log('📋', `Total chunks: ${totalChunks}`);
  log('📋', `Already uploaded: ${uploadedChunks.size} chunks`);

  if (uploadedChunks.size > 0) {
    log('🔄', 'Resuming upload — skipping already uploaded chunks');
  }

  // Step 3: Upload chunks
  const handle = await open(absPath, 'r');
  let uploadedCount = uploadedChunks.size;

  for (let partNumber = 1; partNumber <= totalChunks; partNumber++) {
    if (uploadedChunks.has(partNumber)) {
      continue; // Skip already uploaded chunks
    }

    const start = (partNumber - 1) * CHUNK_SIZE;
    const length = Math.min(CHUNK_SIZE, fileSize - start);
    const buffer = Buffer.alloc(length);
    await handle.read(buffer, 0, length, start);
    const chunkHash = sha256(buffer);

    log('⬆️ ', `Uploading chunk ${partNumber}/${totalChunks} (${formatBytes(length)})...`);

    const chunkResp = await fetch(
      `${BASE_URL}/files/chunk/upload?fileId=${fileId}&partNumber=${partNumber}&chunkHash=${chunkHash}`,
      {
        method: 'POST',
        headers: {
          'X-User-Id': userId,
          'Content-Type': 'application/octet-stream',
        },
        body: buffer,
      },
    );

    if (!chunkResp.ok) {
      console.error(`❌  Chunk ${partNumber} failed:`, await chunkResp.text());
      process.exit(1);
    }

    uploadedCount++;
    const pct = ((uploadedCount / totalChunks) * 100).toFixed(1);
    log('✅', `Chunk ${partNumber}/${totalChunks} uploaded (${pct}%)`);
  }

  await handle.close();

  // Step 4: Complete upload
  log('🔗', 'Completing upload (committing block list)...');
  const completeResp = await fetch(
    `${BASE_URL}/files/chunk/complete?fileId=${fileId}`,
    {
      method: 'POST',
      headers: { 'X-User-Id': userId },
    },
  );

  if (!completeResp.ok) {
    console.error('❌  Complete failed:', await completeResp.text());
    process.exit(1);
  }

  const metadata = await completeResp.json();
  log('🎉', `Upload complete! File ID: ${metadata.id}`);
  log('📊', `   Name: ${metadata.name}`);
  log('📊', `   Size: ${formatBytes(metadata.size)}`);
  log('📊', `   Status: ${metadata.status}`);
}

// ============================================================
// 2) DOWNLOAD
// ============================================================

async function download(fileId, args) {
  const userId = getUserId(args);

  log('⬇️ ', `Downloading file: ${fileId}`);
  const resp = await fetch(`${BASE_URL}/files/${fileId}/download`, {
    headers: { 'X-User-Id': userId },
  });

  if (!resp.ok) {
    console.error('❌  Download failed:', await resp.text());
    process.exit(1);
  }

  const contentDisposition = resp.headers.get('content-disposition');
  let fileName = 'downloaded-file';
  if (contentDisposition) {
    const match = contentDisposition.match(/filename="(.+?)"/);
    if (match) fileName = match[1];
  }

  const buffer = Buffer.from(await resp.arrayBuffer());
  const { writeFile } = await import('node:fs/promises');
  await writeFile(fileName, buffer);

  log('✅', `Downloaded: ${fileName} (${formatBytes(buffer.length)})`);
}

// ============================================================
// 3) LIST FILES
// ============================================================

async function listFiles(args) {
  const userId = getUserId(args);

  log('📋', 'Your files:');
  const resp = await fetch(`${BASE_URL}/files`, {
    headers: { 'X-User-Id': userId },
  });

  if (!resp.ok) {
    console.error('❌  List failed:', await resp.text());
    process.exit(1);
  }

  const files = await resp.json();
  if (files.length === 0) {
    log('📭', 'No files found.');
    return;
  }

  for (const file of files) {
    log('📄', `${file.name}  (${formatBytes(file.size)})  id=${file.id}  status=${file.status}`);
  }

  // Also list shared files
  log('📋', 'Shared with you:');
  const sharedResp = await fetch(`${BASE_URL}/files/shared`, {
    headers: { 'X-User-Id': userId },
  });

  if (sharedResp.ok) {
    const shared = await sharedResp.json();
    if (shared.length === 0) {
      log('📭', 'No shared files.');
    } else {
      for (const file of shared) {
        log('📄', `${file.name}  (${formatBytes(file.size)})  id=${file.id}  status=${file.status}`);
      }
    }
  }
}

// ============================================================
// 4) SHARE
// ============================================================

async function share(fileId, sharedWithUserId, args) {
  const userId = getUserId(args);

  log('🔗', `Sharing file ${fileId} with user ${sharedWithUserId}`);
  const resp = await fetch(`${BASE_URL}/files/${fileId}/share`, {
    method: 'POST',
    headers: {
      'X-User-Id': userId,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ sharedWithUserId }),
  });

  if (!resp.ok) {
    console.error('❌  Share failed:', await resp.text());
    process.exit(1);
  }

  const shareData = await resp.json();
  log('✅', `Shared! Share ID: ${shareData.id}`);
}

// ============================================================
// 5) SYNC (SSE)
// ============================================================

async function sync(args) {
  const userId = getUserId(args);

  log('🔄', `Connecting to SSE endpoint for user ${userId}...`);
  log('🔄', 'Press Ctrl+C to stop.');

  const resp = await fetch(`${BASE_URL}/sync/events`, {
    headers: { 'X-User-Id': userId, Accept: 'text/event-stream' },
  });

  if (!resp.ok) {
    console.error('❌  SSE connection failed:', await resp.text());
    process.exit(1);
  }

  const reader = resp.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) {
      log('🔌', 'SSE connection closed.');
      break;
    }

    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop(); // Keep incomplete line in buffer

    for (const line of lines) {
      if (line.startsWith('event:')) {
        const eventType = line.slice(6).trim();
        log('📡', `Event: ${eventType}`);
      } else if (line.startsWith('data:')) {
        const data = line.slice(5).trim();
        if (data) {
          try {
            const parsed = JSON.parse(data);
            log('📡', `  ${JSON.stringify(parsed, null, 2)}`);
          } catch {
            log('📡', `  ${data}`);
          }
        }
      }
    }
  }
}

// ============================================================
// 6) CHANGES (polling fallback)
// ============================================================

async function changes(args) {
  const userId = getUserId(args);
  const since = args.values.since || '1970-01-01T00:00:00Z';

  log('📋', `Fetching changes since ${since}...`);
  const resp = await fetch(`${BASE_URL}/sync/changes?since=${encodeURIComponent(since)}`, {
    headers: { 'X-User-Id': userId },
  });

  if (!resp.ok) {
    console.error('❌  Changes request failed:', await resp.text());
    process.exit(1);
  }

  const events = await resp.json();
  if (events.length === 0) {
    log('📭', 'No changes found.');
    return;
  }

  for (const event of events) {
    log('📡', `${event.status}  ${event.name}  (${formatBytes(event.size)})  at ${event.updatedAt}`);
  }
}

// ============================================================
// 7) CREATE USER
// ============================================================

async function createUser(args) {
  const email = args.values.email;
  const name = args.values.name;

  if (!email) {
    console.error('❌  --email is required');
    process.exit(1);
  }

  log('👤', `Creating/finding user: ${email}`);
  const resp = await fetch(`${BASE_URL}/users`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, name }),
  });

  if (!resp.ok) {
    console.error('❌  User creation failed:', await resp.text());
    process.exit(1);
  }

  const user = await resp.json();
  log('✅', `User: ${user.name} (${user.email})`);
  log('📊', `   User ID: ${user.id}`);
  log('💡', `   Use --user-id ${user.id} for other commands.`);
}

// ============================================================
// CLI entry point
// ============================================================

const { values, positionals } = parseArgs({
  options: {
    'user-id': { type: 'string' },
    'since': { type: 'string' },
    'email': { type: 'string' },
    'name': { type: 'string' },
  },
  allowPositionals: true,
});

const command = positionals[0];

switch (command) {
  case 'upload':
    await upload(positionals[1], { values });
    break;
  case 'download':
    await download(positionals[1], { values });
    break;
  case 'list':
    await listFiles({ values });
    break;
  case 'share':
    await share(positionals[1], positionals[2], { values });
    break;
  case 'sync':
    await sync({ values });
    break;
  case 'changes':
    await changes({ values });
    break;
  case 'user':
    await createUser({ values });
    break;
  default:
    console.log(`
Dropbox Client — Usage:

  user   --email <email> [--name <name>]          Create or find a user
  upload <filePath> [--user-id <uuid>]             Upload a file (chunked + fingerprinted)
  download <fileId> [--user-id <uuid>]             Download a file
  list [--user-id <uuid>]                          List your files + shared files
  share <fileId> <userId> [--user-id <uuid>]       Share a file with another user
  sync [--user-id <uuid>]                          Listen for SSE sync events
  changes [--since <iso8601>] [--user-id <uuid>]   Poll for changes

Environment variables:
  DROPBOX_API_URL   API base URL (default: http://localhost:8080/api/dropbox)
  DROPBOX_CHUNK_SIZE  Chunk size in bytes (default: 4194304 = 4 MB)
  DROPBOX_USER_ID   Default user ID
`);
    break;
}