'use strict';

const http = require('http');

const { loadConfig } = require('../lib/config');
const {
  readPayload,
  requestPath,
  requestSearch,
  sendHtml,
  sendJson,
} = require('../lib/http');

const config = loadConfig({
  ENVIRONMENT: 'dev',
  HOST: '0.0.0.0',
  PORT: '8080',
  API_BASE_URL: 'http://api.app.svc.cluster.local:8081',
});

async function proxyJson(req, res, targetPath) {
  const url = `${config.API_BASE_URL}${targetPath}${requestSearch(req)}`;
  const headers = { accept: 'application/json' };
  let body;

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    body = JSON.stringify(await readPayload(req));
    headers['content-type'] = 'application/json';
  }

  const response = await fetch(url, {
    method: req.method,
    headers,
    body,
  });

  const text = await response.text();
  res.writeHead(response.status, {
    'content-type': response.headers.get('content-type') || 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  });
  res.end(text);
}

function renderGatewayPage() {
  return `<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Deployment Kit Gateway</title>
  <style>
    body { margin: 0; font-family: system-ui, sans-serif; background: #f6f7f9; color: #1f2937; }
    main { max-width: 760px; margin: 48px auto; padding: 0 20px; }
    section { background: white; border: 1px solid #d7dce3; border-radius: 8px; padding: 20px; }
    code { background: #eef2f7; border-radius: 4px; padding: 2px 6px; }
  </style>
</head>
<body>
  <main>
    <section>
      <h1>Gateway</h1>
      <p>Сервис проксирует маршруты <code>/leads</code>, <code>/entities</code> и <code>/test-runs</code> в API.</p>
      <p>API endpoint: <code>${config.API_BASE_URL}</code></p>
    </section>
  </main>
</body>
</html>`;
}

const server = http.createServer(async (req, res) => {
  try {
    const path = requestPath(req);

    if (req.method === 'GET' && path === '/health') {
      sendJson(res, 200, {
        status: 'ok',
        service: 'gateway',
        environment: config.ENVIRONMENT,
        apiBaseUrl: config.API_BASE_URL,
      });
      return;
    }

    if (req.method === 'GET' && path === '/') {
      sendHtml(res, 200, renderGatewayPage());
      return;
    }

    if (
      path === '/entities' || path.startsWith('/entities/') ||
      path === '/leads' || path.startsWith('/leads/') ||
      path === '/test-runs' || path.startsWith('/test-runs/')
    ) {
      await proxyJson(req, res, path);
      return;
    }

    sendJson(res, 404, { error: 'route not found' });
  } catch (error) {
    sendJson(res, 502, { error: error.message });
  }
});

server.listen(Number(config.PORT), config.HOST, () => {
  console.log(`gateway stub listens on ${config.HOST}:${config.PORT}`);
});
