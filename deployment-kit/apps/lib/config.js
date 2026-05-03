'use strict';

const fs = require('fs');

function stripQuotes(value) {
  const trimmed = String(value || '').trim();
  if ((trimmed.startsWith('"') && trimmed.endsWith('"')) || (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
    return trimmed.slice(1, -1);
  }
  return trimmed;
}

function parseKeyValue(text) {
  const result = {};

  for (const rawLine of String(text || '').split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) {
      continue;
    }

    const match = line.match(/^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
    if (match) {
      result[match[1]] = stripQuotes(match[2]);
    }
  }

  return result;
}

function flattenVaultJson(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return {};
  }

  if (value.data && value.data.data && typeof value.data.data === 'object') {
    return value.data.data;
  }

  if (value.data && typeof value.data === 'object' && !Array.isArray(value.data)) {
    return value.data;
  }

  return value;
}

function readVaultConfig(filePath) {
  if (!filePath || !fs.existsSync(filePath)) {
    return {};
  }

  const text = fs.readFileSync(filePath, 'utf8');
  try {
    return flattenVaultJson(JSON.parse(text));
  } catch (_error) {
    return parseKeyValue(text);
  }
}

function loadConfig(defaults = {}) {
  const vaultFile = process.env.VAULT_CONFIG_FILE || '/vault/secrets/config';
  const vaultConfig = readVaultConfig(vaultFile);

  return {
    ...defaults,
    ...vaultConfig,
    ...process.env,
  };
}

module.exports = {
  loadConfig,
  parseKeyValue,
  readVaultConfig,
};

