'use strict';

const http = require('http');
const crypto = require('crypto');

const { loadConfig } = require('../lib/config');
const { createStore, MemoryStore } = require('../lib/redis');
const {
  normalizeLeadPayload,
  readPayload,
  requestPath,
  sendJson,
} = require('../lib/http');

const config = loadConfig({
  ENVIRONMENT: 'dev',
  HOST: '0.0.0.0',
  PORT: '8081',
  REDIS_URL: 'redis://redis-master.app.svc.cluster.local:6379',
});

let leadStore = createStore(config.REDIS_URL, 'deployment-kit:lead');
let testRunStore = createStore(config.REDIS_URL, 'deployment-kit:test-run');

function buildLead(payload) {
  const now = new Date().toISOString();
  return {
    id: crypto.randomUUID(),
    ...normalizeLeadPayload(payload),
    createdAt: now,
    updatedAt: now,
    service: 'api',
    environment: config.ENVIRONMENT,
  };
}

function buildTestRun(payload) {
  const checks = Array.isArray(payload.checks) ? payload.checks : [];
  return {
    id: payload.id || crypto.randomUUID(),
    suite: String(payload.suite || 'manual'),
    title: String(payload.title || payload.suite || 'Manual test run'),
    status: String(payload.status || 'unknown'),
    durationSeconds: Number(payload.durationSeconds || 0),
    checks,
    summary: String(payload.summary || ''),
    createdAt: payload.createdAt || new Date().toISOString(),
    service: 'api',
    environment: config.ENVIRONMENT,
  };
}

async function useStore(storeName, operation) {
  const currentStore = storeName === 'test-runs' ? testRunStore : leadStore;
  try {
    return await operation(currentStore);
  } catch (error) {
    if (!(currentStore instanceof MemoryStore)) {
      console.error(`Redis недоступен, API временно переключается на in-memory store: ${error.message}`);
      if (storeName === 'test-runs') {
        testRunStore = new MemoryStore();
        return operation(testRunStore);
      }
      leadStore = new MemoryStore();
      return operation(leadStore);
    }
    throw error;
  }
}

function isLeadCollection(path) {
  return path === '/leads' || path === '/api/leads' || path === '/entities' || path === '/api/entities';
}

function leadIdFromPath(path) {
  const match = path.match(/^\/(?:api\/)?(?:leads|entities)\/([^/]+)$/);
  return match ? decodeURIComponent(match[1]) : '';
}

async function handleLeads(req, res, path) {
  if (req.method === 'GET' && isLeadCollection(path)) {
    const items = await useStore('leads', (store) => store.list(100));
    sendJson(res, 200, { items });
    return true;
  }

  if (req.method === 'POST' && isLeadCollection(path)) {
    const payload = await readPayload(req);
    const lead = buildLead(payload);
    await useStore('leads', (store) => store.put(lead));
    sendJson(res, 201, lead);
    return true;
  }

  const id = leadIdFromPath(path);
  if (!id) {
    return false;
  }

  if (req.method === 'GET') {
    const lead = await useStore('leads', (store) => store.get(id));
    if (!lead) {
      sendJson(res, 404, { error: 'lead not found' });
      return true;
    }
    sendJson(res, 200, lead);
    return true;
  }

  if (req.method === 'PUT' || req.method === 'PATCH') {
    const payload = await readPayload(req);
    const patch = normalizeLeadPayload(payload, { partial: true });
    const lead = await useStore('leads', (store) => store.update(id, patch));
    if (!lead) {
      sendJson(res, 404, { error: 'lead not found' });
      return true;
    }
    sendJson(res, 200, lead);
    return true;
  }

  return false;
}

function isTestRunCollection(path) {
  return path === '/test-runs' || path === '/api/test-runs';
}

function testRunIdFromPath(path) {
  const match = path.match(/^\/(?:api\/)?test-runs\/([^/]+)$/);
  return match ? decodeURIComponent(match[1]) : '';
}

async function handleTestRuns(req, res, path) {
  if (req.method === 'GET' && isTestRunCollection(path)) {
    const items = await useStore('test-runs', (store) => store.list(50));
    sendJson(res, 200, { items });
    return true;
  }

  if (req.method === 'POST' && isTestRunCollection(path)) {
    const payload = await readPayload(req);
    const testRun = buildTestRun(payload);
    await useStore('test-runs', (store) => store.put(testRun));
    sendJson(res, 201, testRun);
    return true;
  }

  const id = testRunIdFromPath(path);
  if (!id || req.method !== 'GET') {
    return false;
  }

  const testRun = await useStore('test-runs', (store) => store.get(id));
  if (!testRun) {
    sendJson(res, 404, { error: 'test run not found' });
    return true;
  }
  sendJson(res, 200, testRun);
  return true;
}

const server = http.createServer(async (req, res) => {
  try {
    const path = requestPath(req);

    if (req.method === 'GET' && path === '/health') {
      sendJson(res, 200, {
        status: 'ok',
        service: 'api',
        environment: config.ENVIRONMENT,
        storage: leadStore instanceof MemoryStore ? 'memory' : 'redis',
      });
      return;
    }

    if (await handleLeads(req, res, path)) {
      return;
    }

    if (await handleTestRuns(req, res, path)) {
      return;
    }

    sendJson(res, 404, { error: 'route not found' });
  } catch (error) {
    const statusCode = error.statusCode || 500;
    sendJson(res, statusCode, { error: error.message });
  }
});

server.listen(Number(config.PORT), config.HOST, () => {
  console.log(`api stub listens on ${config.HOST}:${config.PORT}`);
});
