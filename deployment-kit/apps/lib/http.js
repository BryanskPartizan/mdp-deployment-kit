'use strict';

const { URL } = require('url');

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(statusCode, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store',
  });
  res.end(body);
}

function sendHtml(res, statusCode, body) {
  res.writeHead(statusCode, {
    'content-type': 'text/html; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store',
  });
  res.end(body);
}

function sendText(res, statusCode, body) {
  res.writeHead(statusCode, {
    'content-type': 'text/plain; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store',
  });
  res.end(body);
}

function readBody(req, limitBytes = 64 * 1024) {
  return new Promise((resolve, reject) => {
    let body = '';

    req.setEncoding('utf8');
    req.on('data', (chunk) => {
      body += chunk;
      if (Buffer.byteLength(body) > limitBytes) {
        reject(new Error('request body is too large'));
        req.destroy();
      }
    });
    req.on('end', () => resolve(body));
    req.on('error', reject);
  });
}

async function readPayload(req) {
  const body = await readBody(req);
  const contentType = req.headers['content-type'] || '';

  if (!body) {
    return {};
  }

  if (contentType.includes('application/json')) {
    return JSON.parse(body);
  }

  if (contentType.includes('application/x-www-form-urlencoded')) {
    return Object.fromEntries(new URLSearchParams(body));
  }

  return { text: body };
}

function requestPath(req) {
  return new URL(req.url, 'http://127.0.0.1').pathname;
}

function requestSearch(req) {
  return new URL(req.url, 'http://127.0.0.1').search;
}

const LEAD_STATUSES = new Set(['new', 'contacted', 'qualified', 'won', 'lost']);

function normalizeLeadPayload(payload, options = {}) {
  const partial = Boolean(options.partial);
  const name = String(payload.name || '').trim();
  const company = String(payload.company || '').trim();
  const email = String(payload.email || '').trim();
  const phone = String(payload.phone || '').trim();
  const source = String(payload.source || '').trim() || (partial ? '' : 'manual');
  const status = String(payload.status || '').trim() || (partial ? '' : 'new');
  const owner = String(payload.owner || '').trim();
  const notes = String(payload.notes || payload.description || '').trim();
  const budgetRaw = String(payload.budget || '').trim();

  if (!partial && !name) {
    const error = new Error('field "name" is required');
    error.statusCode = 400;
    throw error;
  }

  if (status && !LEAD_STATUSES.has(status)) {
    const error = new Error(`field "status" must be one of: ${Array.from(LEAD_STATUSES).join(', ')}`);
    error.statusCode = 400;
    throw error;
  }

  if (budgetRaw) {
    const budget = Number(budgetRaw);
    if (!Number.isFinite(budget) || budget < 0) {
      const error = new Error('field "budget" must be a non-negative number');
      error.statusCode = 400;
      throw error;
    }
  }

  const result = {};
  for (const [key, value] of Object.entries({ name, company, email, phone, source, status, owner, notes })) {
    if (!partial || value) {
      result[key] = value;
    }
  }
  if (budgetRaw || !partial) {
    result.budget = budgetRaw ? Number(budgetRaw) : 0;
  }

  return result;
}

module.exports = {
  normalizeEntityPayload: normalizeLeadPayload,
  normalizeLeadPayload,
  readPayload,
  requestPath,
  requestSearch,
  sendHtml,
  sendJson,
  sendText,
};
