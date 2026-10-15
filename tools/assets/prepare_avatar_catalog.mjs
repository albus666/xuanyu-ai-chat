#!/usr/bin/env node

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import path from 'node:path';

const [, , sourceMapPath, outputRoot, approvalFlag] = process.argv;
if (!sourceMapPath || !outputRoot) {
  throw new Error(
    'usage: node tools/assets/prepare_avatar_catalog.mjs SOURCE_MAP OUTPUT_ROOT [--approved]',
  );
}

const approved = approvalFlag === '--approved';
const items = JSON.parse(await readFile(sourceMapPath, 'utf8'));
if (!Array.isArray(items) || items.length === 0) {
  throw new Error('source map must be a non-empty JSON list');
}

const optimizedRoot = path.join(outputRoot, 'optimized');
const thumbnailRoot = path.join(outputRoot, 'thumbs');
await mkdir(optimizedRoot, { recursive: true });
await mkdir(thumbnailRoot, { recursive: true });

function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ['ignore', 'ignore', 'pipe'] });
    let error = '';
    child.stderr.on('data', (chunk) => {
      if (error.length < 4000) error += chunk;
    });
    child.once('error', reject);
    child.once('close', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${command} failed (${code}): ${error.trim()}`));
    });
  });
}

async function prepare(item) {
  const source = item.sourcePath;
  const asset = path.join(optimizedRoot, `${item.code}.webp`);
  const thumbnail = path.join(thumbnailRoot, `${item.code}.webp`);
  const scale = (pixels) =>
    `scale=${pixels}:${pixels}:force_original_aspect_ratio=increase:flags=lanczos,crop=${pixels}:${pixels}`;
  await run('ffmpeg', [
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-i',
    source,
    '-vf',
    scale(768),
    '-frames:v',
    '1',
    '-c:v',
    'libwebp',
    '-quality',
    '84',
    '-compression_level',
    '6',
    asset,
  ]);
  await run('ffmpeg', [
    '-hide_banner',
    '-loglevel',
    'error',
    '-y',
    '-i',
    source,
    '-vf',
    scale(256),
    '-frames:v',
    '1',
    '-c:v',
    'libwebp',
    '-quality',
    '78',
    '-compression_level',
    '6',
    thumbnail,
  ]);
}

for (let offset = 0; offset < items.length; offset += 4) {
  await Promise.all(items.slice(offset, offset + 4).map(prepare));
  process.stdout.write(`prepared ${Math.min(offset + 4, items.length)}/${items.length}\n`);
}

const priceSteps = [58, 68, 78];
const manifest = items.map((item, position) => ({
  code: item.code,
  name: item.name,
  description: `${item.name} · 玄遇原创星海幻想头像`,
  categoryCode: 'starsea',
  categoryName: '星海幻想',
  presentation: item.presentation,
  price: priceSteps[position % priceSteps.length],
  sortOrder: 2000 + position,
  assetFile: `optimized/${item.code}.webp`,
  thumbnailFile: `thumbs/${item.code}.webp`,
  safeCircleApproved: approved,
  safeCircleInsetPercent: 13,
}));
const prompts = {
  generator: 'built-in image_gen',
  referenceRole:
    'The supplied screenshot was used only as a broad mood/category reference; no character, UI, text, logo, costume, or layout was copied.',
  sharedPrompt:
    'Original premium 星海幻想 portrait; adult East Asian fantasy character; polished painterly 3D Chinese animation style; true circular-crop composition; face, complete hair, ears, and key ornaments kept inside the central 74% safe area; outer 13% primarily background; no text, UI, logo, watermark, border, sexualized clothing, real-person likeness, or recognizable IP.',
  items: items.map(({ index, code, name, presentation, subject, detail, scene, palette }) => ({
    index,
    code,
    name,
    presentation,
    subject,
    detail,
    scene,
    palette,
  })),
};
await writeFile(
  path.join(outputRoot, approved ? 'manifest.json' : 'manifest.review.json'),
  `${JSON.stringify(manifest, null, 2)}\n`,
);
await writeFile(
  path.join(outputRoot, 'prompts.json'),
  `${JSON.stringify(prompts, null, 2)}\n`,
);

console.log(
  `catalog ready: ${items.length} items (${approved ? 'approved' : 'review required'})`,
);
