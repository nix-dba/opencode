#!/usr/bin/env bun
import { readFileSync, writeFileSync } from 'fs';

function stripComments(str) {
  let inString = false;
  let inBlock = false;
  let inLine = false;
  let out = '';
  for (let i = 0; i < str.length; i++) {
    if (inBlock) {
      if (str[i] === '*' && str[i+1] === '/') { inBlock = false; i++; }
      continue;
    }
    if (inLine) {
      if (str[i] === '\n') { inLine = false; out += '\n'; }
      continue;
    }
    if (inString) {
      if (str[i] === '\\') { out += str[i] + str[i+1]; i++; continue; }
      if (str[i] === inString) inString = false;
      out += str[i];
      continue;
    }
    if (str[i] === '"' || str[i] === "'") { inString = str[i]; out += str[i]; continue; }
    if (str[i] === '/' && str[i+1] === '/') { inLine = true; i++; continue; }
    if (str[i] === '/' && str[i+1] === '*') { inBlock = true; i++; continue; }
    out += str[i];
  }
  return out;
}

function deepMerge(a, b) {
  const result = { ...a };
  for (const [k, v] of Object.entries(b)) {
    if (Array.isArray(v) && Array.isArray(result[k])) {
      result[k] = [...result[k], ...v];
    } else if (v && typeof v === 'object' && !Array.isArray(v) && result[k] && typeof result[k] === 'object' && !Array.isArray(result[k])) {
      result[k] = deepMerge(result[k], v);
    } else {
      result[k] = v;
    }
  }
  return result;
}

const [baseFile, overlayFile, outFile] = process.argv.slice(2);
const base = JSON.parse(stripComments(readFileSync(baseFile, 'utf8')));
const overlay = JSON.parse(stripComments(readFileSync(overlayFile, 'utf8')));
const merged = deepMerge(base, overlay);
writeFileSync(outFile, JSON.stringify(merged, null, 2) + '\n');
