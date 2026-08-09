#!/usr/bin/env node

/**
 * chunked-upload.mjs
 *
 * Client-side script that:
 *   1. Chunks any file into N-byte pieces (default 4 MB)
 *   2. Starts a chunked upload session on the server
 *   3. Sends chunks ONE BY ONE — waits for 200 OK before sending the next
 *   4. On failure, retries the chunk (up to 3 times)
 *   5. After all chunks are sent, calls "complete" to assemble the blob
 *
 * Usage:
 *   node chunked-upload.mjs <filePath> [options]
 *
 * Options:
 *   --server=http://localhost:8080   Server base URL
 *   --chunk-size=4194304             Chunk size in bytes (default 4 MB)
 *   --blob-name=custom-name.mp4      Override blob name (default: filename)
 *   --content-type=video/mp4          Content type for the final blob
 *   --max-retries=3                   Max retries per chunk
 *
 * Example:
 *   node chunked-upload.mjs ./big-video.mp4 --chunk-size=8388608 --content-type=video/mp4
 *   node chunked-upload.mjs ./10gb.zip --chunk-size=16777216
 *
 * Flow:
 *
 *   ┌─────────┐                    ┌─────────┐                  ┌──────────┐
 *   │  Client  │                    │  Server  │                  │  Azure   │
 *   │ (script) │                    │ (Spring) │                  │  Blob    │
 *   └────┬────┘                    └────┬────┘                  └────┬─────┘
 *        │                              │                             │
 *        │ POST /chunk/start            │                             │
 *        │─────────────────────────────>│                             │
 *        │      uploadId=xxx            │                             │
 *        │<─────────────────────────────│                             │
 *        │                              │                             │
 *        │ Read chunk 1 from file       │                             │
 *        │ POST /chunk/upload (part 1)  │                             │
 *        │─────────────────────────────>│  stageBlock(blockId_1)     │
 *        │                              │────────────────────────────>│
 *        │      200 OK (staged)         │                             │
 *        │<─────────────────────────────│                             │
 *        │                              │                             │
 *        │ Read chunk 2 from file       │                             │
 *        │ POST /chunk/upload (part 2)  │                             │
 *        │─────────────────────────────>│  stageBlock(blockId_2)     │
 *        │                              │────────────────────────────>│
 *        │      200 OK (staged)         │                             │
 *        │<─────────────────────────────│                             │
 *        │         ...                  │         ...                 │
 *        │                              │                             │
 *        │ POST /chunk/complete         │                             │
 *        │─────────────────────────────>│  commitBlockList(all IDs)  │
 *        │                              │────────────────────────────>│
 *        │      200 OK (final blob URL) │     Blob is assembled!     │
 *        │<─────────────────────────────│                             │
 *        │                              │                             │
 */

import { open } from 'node:fs/promises';
import { basename } from 'node:path';
import { fileURLToPath } from 'node:url';

// ── Parse CLI args ──────────────────────────────────────────

const args = process.argv.slice(2);

if (args.length === 0 || args.includes('--help') || args.includes('-h')) {
    console.log(`
Usage: node chunked-upload.mjs <filePath> [options]

Options:
  --server=http://localhost:8080   Server base URL
  --chunk-size=4194304             Chunk size in bytes (default 4 MB)
  --blob-name=custom-name          Override blob name (default: filename)
  --content-type=video/mp4         Content type for the final blob
  --max-retries=3                  Max retries per chunk on failure

Example:
  node chunked-upload.mjs ./big-video.mp4 --chunk-size=8388608 --content-type=video/mp4
`);
    process.exit(0);
}

const filePath = args.find(a => !a.startsWith('--'));

const opts = {
    server: 'http://localhost:8080',
    chunkSize: 4 * 1024 * 1024,  // 4 MB default
    blobName: null,
    contentType: 'application/octet-stream',
    maxRetries: 3,
};

for (const arg of args) {
    if (arg.startsWith('--server=')) opts.server = arg.split('=')[1];
    if (arg.startsWith('--chunk-size=')) opts.chunkSize = parseInt(arg.split('=')[1], 10);
    if (arg.startsWith('--blob-name=')) opts.blobName = arg.split('=')[1];
    if (arg.startsWith('--content-type=')) opts.contentType = arg.split('=')[1];
    if (arg.startsWith('--max-retries=')) opts.maxRetries = parseInt(arg.split('=')[1], 10);
}

if (!opts.blobName) opts.blobName = basename(filePath);

// ── Helpers ─────────────────────────────────────────────────

function formatBytes(bytes) {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(2)} KB`;
    if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
    return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`;
}

function formatTime(ms) {
    if (ms < 1000) return `${ms}ms`;
    return `${(ms / 1000).toFixed(2)}s`;
}

function progressBar(current, total, width = 40) {
    const pct = total > 0 ? current / total : 0;
    const filled = Math.round(pct * width);
    const bar = '█'.repeat(filled) + '░'.repeat(width - filled);
    const pctStr = `${(pct * 100).toFixed(1)}%`;
    process.stdout.write(`\r  ${bar} ${pctStr} (${current}/${total} chunks)`);
    if (current === total) process.stdout.write('\n');
}

// ── HTTP helpers ────────────────────────────────────────────

async function postJson(url) {
    const res = await fetch(url, { method: 'POST' });
    if (!res.ok) {
        const body = await res.text().catch(() => '');
        throw new Error(`POST ${url} → ${res.status}: ${body}`);
    }
    return res.json();
}

async function postChunk(url, chunkBuffer) {
    const res = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/octet-stream' },
        body: chunkBuffer,
    });
    if (!res.ok) {
        const body = await res.text().catch(() => '');
        throw new Error(`POST ${url} → ${res.status}: ${body}`);
    }
    return res.json();
}

// ── Main upload flow ────────────────────────────────────────

async function main() {
    const fileHandle = await open(filePath, 'r');
    const stat = await fileHandle.stat();

    const fileSize = stat.size;
    const totalChunks = Math.ceil(fileSize / opts.chunkSize);

    console.log('═══════════════════════════════════════════════════════════');
    console.log('  Chunked File Upload');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  File:          ${filePath}`);
    console.log(`  Blob name:     ${opts.blobName}`);
    console.log(`  File size:     ${formatBytes(fileSize)}`);
    console.log(`  Chunk size:    ${formatBytes(opts.chunkSize)}`);
    console.log(`  Total chunks:  ${totalChunks}`);
    console.log(`  Server:        ${opts.server}`);
    console.log(`  Content-Type:  ${opts.contentType}`);
    console.log(`  Max retries:   ${opts.maxRetries}`);
    console.log('═══════════════════════════════════════════════════════════\n');

    // ── Step 1: Start chunked upload session ──
    console.log('▶ Step 1: Starting chunked upload session...');

    const startUrl = `${opts.server}/api/files/chunk/start?blobName=${encodeURIComponent(opts.blobName)}`;
    const startResp = await postJson(startUrl);
    const uploadId = startResp.uploadId;

    console.log(`  ✓ uploadId = ${uploadId}\n`);

    // ── Step 2: Send chunks one by one ──
    console.log('▶ Step 2: Sending chunks (sequential, one at a time)...\n');

    const uploadStart = Date.now();
    let uploadedBytes = 0;

    for (let partNumber = 1; partNumber <= totalChunks; partNumber++) {
        const offset = (partNumber - 1) * opts.chunkSize;
        const length = Math.min(opts.chunkSize, fileSize - offset);
        const chunkBuffer = Buffer.alloc(length);

        // Read chunk from file
        await fileHandle.read(chunkBuffer, 0, length, offset);

        const chunkUrl = `${opts.server}/api/files/chunk/upload`
            + `?uploadId=${encodeURIComponent(uploadId)}`
            + `&blobName=${encodeURIComponent(opts.blobName)}`
            + `&partNumber=${partNumber}`;

        // Retry logic for this chunk
        let success = false;
        let attempt = 0;

        while (!success && attempt < opts.maxRetries) {
            attempt++;
            try {
                const chunkStart = Date.now();
                const resp = await postChunk(chunkUrl, chunkBuffer);
                const chunkElapsed = Date.now() - chunkStart;
                const throughput = (length / (1024 * 1024)) / (chunkElapsed / 1000);

                uploadedBytes += length;
                success = true;

                if (partNumber <= 5 || partNumber === totalChunks || partNumber % 10 === 0) {
                    console.log(
                        `  ✓ Chunk ${String(partNumber).padStart(String(totalChunks).length)}/${totalChunks}`
                        + ` — ${formatBytes(length)}`
                        + ` — ${formatTime(chunkElapsed)}`
                        + ` — ${throughput.toFixed(1)} MB/s`
                        + (attempt > 1 ? ` — (retry #${attempt - 1})` : '')
                    );
                }
            } catch (err) {
                if (attempt < opts.maxRetries) {
                    console.log(`  ✗ Chunk ${partNumber} failed (attempt ${attempt}), retrying...`);
                    // Wait before retry (exponential backoff)
                    await new Promise(r => setTimeout(r, 1000 * attempt));
                } else {
                    console.error(`\n  ✗ Chunk ${partNumber} failed after ${opts.maxRetries} attempts: ${err.message}`);
                    console.log('\n  Aborting upload...');
                    await postJson(`${opts.server}/api/files/chunk/abort?uploadId=${encodeURIComponent(uploadId)}`)
                        .catch(() => {});
                    await fileHandle.close();
                    process.exit(1);
                }
            }
        }

        progressBar(partNumber, totalChunks);
    }

    await fileHandle.close();

    const uploadElapsed = Date.now() - uploadStart;
    const avgThroughput = (fileSize / (1024 * 1024)) / (uploadElapsed / 1000);

    console.log(`\n  ✓ All ${totalChunks} chunks uploaded in ${formatTime(uploadElapsed)} (${avgThroughput.toFixed(1)} MB/s avg)\n`);

    // ── Step 3: Commit — assemble the final blob ──
    console.log('▶ Step 3: Committing all chunks (assembling final blob)...');

    const completeUrl = `${opts.server}/api/files/chunk/complete`
        + `?uploadId=${encodeURIComponent(uploadId)}`
        + `&blobName=${encodeURIComponent(opts.blobName)}`
        + `&contentType=${encodeURIComponent(opts.contentType)}`;

    const result = await postJson(completeUrl);

    console.log('═══════════════════════════════════════════════════════════');
    console.log('  ✅ Upload Complete!');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`  Blob name:     ${result.blobName}`);
    console.log(`  Blob URL:      ${result.blobUrl}`);
    console.log(`  Final size:    ${formatBytes(result.sizeBytes)}`);
    console.log(`  Total chunks:  ${totalChunks}`);
    console.log(`  Total time:    ${formatTime(uploadElapsed + result.elapsedMs)}`);
    console.log(`  Avg speed:     ${avgThroughput.toFixed(1)} MB/s`);
    console.log('═══════════════════════════════════════════════════════════');
}

main().catch(err => {
    console.error('\n❌ Fatal error:', err.message);
    process.exit(1);
});