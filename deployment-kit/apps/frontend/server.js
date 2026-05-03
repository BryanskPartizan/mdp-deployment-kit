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
  GATEWAY_BASE_URL: 'http://gateway.app.svc.cluster.local:8080',
});

async function proxyJson(req, res, targetPath) {
  const url = `${config.GATEWAY_BASE_URL}${targetPath}${requestSearch(req)}`;
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

function renderPage() {
  return `<!doctype html>
<html lang="ru">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>Deployment Kit CRM</title>
  <style>
    :root { color-scheme: light; --bg: #f4f6f8; --panel: #ffffff; --line: #d8dee8; --text: #172033; --muted: #667085; --accent: #176b5f; --blue: #155eef; --danger: #b42318; }
    * { box-sizing: border-box; }
    body { margin: 0; font-family: Inter, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: var(--bg); color: var(--text); }
    header { background: #ffffff; border-bottom: 1px solid var(--line); }
    .topbar { max-width: 1240px; margin: 0 auto; padding: 16px 20px; display: flex; align-items: center; justify-content: space-between; gap: 16px; }
    h1 { font-size: 22px; margin: 0; letter-spacing: 0; }
    .status { color: var(--muted); font-size: 14px; }
    main { max-width: 1240px; margin: 0 auto; padding: 20px; }
    nav { display: flex; gap: 8px; margin-bottom: 16px; }
    nav button { border: 1px solid var(--line); background: #fff; color: var(--text); border-radius: 6px; padding: 9px 12px; cursor: pointer; }
    nav button.active { background: var(--accent); color: #fff; border-color: var(--accent); }
    .grid { display: grid; grid-template-columns: 360px minmax(0, 1fr); gap: 16px; align-items: start; }
    .panel { background: var(--panel); border: 1px solid var(--line); border-radius: 8px; padding: 16px; }
    .panel h2 { font-size: 16px; margin: 0 0 12px; }
    label { display: block; font-size: 13px; color: #344054; margin: 10px 0 5px; }
    input, textarea, select { width: 100%; border: 1px solid #c8d0dc; border-radius: 6px; padding: 9px 10px; font: inherit; background: #fff; color: var(--text); }
    textarea { min-height: 76px; resize: vertical; }
    .row { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; }
    .actions { display: flex; gap: 8px; margin-top: 12px; }
    button.primary { background: var(--blue); border: 1px solid var(--blue); color: #fff; border-radius: 6px; padding: 9px 12px; cursor: pointer; }
    button.secondary { background: #fff; border: 1px solid var(--line); color: var(--text); border-radius: 6px; padding: 9px 12px; cursor: pointer; }
    .board { display: grid; grid-template-columns: repeat(5, minmax(150px, 1fr)); gap: 10px; }
    .metrics { display: grid; grid-template-columns: repeat(4, minmax(120px, 1fr)); gap: 10px; margin-bottom: 12px; }
    .metric { background: #f8fafc; border: 1px solid var(--line); border-radius: 7px; padding: 10px; }
    .metric strong { display: block; font-size: 18px; margin-top: 4px; }
    .metric span { color: var(--muted); font-size: 12px; }
    .column { min-height: 240px; background: #f8fafc; border: 1px solid var(--line); border-radius: 8px; padding: 10px; }
    .column h3 { margin: 0 0 10px; font-size: 14px; color: #344054; display: flex; justify-content: space-between; }
    .lead { width: 100%; text-align: left; background: #fff; border: 1px solid #d9e0ea; border-radius: 7px; padding: 10px; margin-bottom: 8px; cursor: pointer; }
    .lead strong { display: block; font-size: 14px; margin-bottom: 4px; }
    .lead span { display: block; color: var(--muted); font-size: 12px; line-height: 1.35; }
    .list { margin-top: 14px; overflow: auto; border: 1px solid var(--line); border-radius: 8px; }
    table { width: 100%; border-collapse: collapse; font-size: 14px; }
    th, td { padding: 9px 10px; border-bottom: 1px solid #edf0f5; text-align: left; vertical-align: top; }
    th { background: #f8fafc; color: #475467; font-weight: 600; }
    tr:last-child td { border-bottom: 0; }
    .hidden { display: none; }
    .notice { margin-top: 10px; color: var(--muted); font-size: 13px; min-height: 18px; }
    .test-run { border: 1px solid var(--line); border-radius: 8px; padding: 12px; margin-bottom: 10px; background: #fff; }
    .test-run.ok { border-left: 5px solid #16865a; }
    .test-run.fail { border-left: 5px solid var(--danger); }
    .pill { display: inline-block; border-radius: 999px; padding: 2px 8px; font-size: 12px; background: #eef4ff; color: #1d4ed8; }
    @media (max-width: 980px) { .grid { grid-template-columns: 1fr; } .board { grid-template-columns: repeat(2, minmax(150px, 1fr)); } }
    @media (max-width: 560px) { .board, .row { grid-template-columns: 1fr; } .topbar { align-items: flex-start; flex-direction: column; } }
  </style>
</head>
<body>
  <header>
    <div class="topbar">
      <h1>Deployment Kit CRM</h1>
      <div class="status" id="health">Проверка сервисов...</div>
    </div>
  </header>
  <main>
    <nav>
      <button class="active" data-tab="crm">Лиды</button>
      <button data-tab="admin">Админка</button>
    </nav>

    <section id="crm-tab" class="grid">
      <form id="lead-form" class="panel">
        <h2 id="form-title">Новый лид</h2>
        <input type="hidden" name="id" id="lead-id">
        <label for="name">Контакт</label>
        <input id="name" name="name" required placeholder="Иван Петров">
        <label for="company">Компания</label>
        <input id="company" name="company" placeholder="Example LLC">
        <div class="row">
          <div>
            <label for="email">Email</label>
            <input id="email" name="email" type="email" placeholder="lead@example.com">
          </div>
          <div>
            <label for="phone">Телефон</label>
            <input id="phone" name="phone" placeholder="+7...">
          </div>
        </div>
        <div class="row">
          <div>
            <label for="source">Источник</label>
            <input id="source" name="source" placeholder="website">
          </div>
          <div>
            <label for="budget">Бюджет</label>
            <input id="budget" name="budget" type="number" min="0" step="1000">
          </div>
        </div>
        <div class="row">
          <div>
            <label for="status">Статус</label>
            <select id="status" name="status">
              <option value="new">Новый</option>
              <option value="contacted">Связались</option>
              <option value="qualified">Квалифицирован</option>
              <option value="won">Выигран</option>
              <option value="lost">Потерян</option>
            </select>
          </div>
          <div>
            <label for="owner">Ответственный</label>
            <input id="owner" name="owner" placeholder="manager">
          </div>
        </div>
        <label for="notes">Заметки</label>
        <textarea id="notes" name="notes" placeholder="Что важно знать о лиде"></textarea>
        <div class="actions">
          <button class="primary" type="submit">Сохранить</button>
          <button class="secondary" type="button" id="reset-form">Очистить</button>
        </div>
        <div class="notice" id="form-notice"></div>
      </form>

      <div>
        <section class="panel">
          <h2>Доска лидов</h2>
          <div class="metrics" id="lead-metrics"></div>
          <div class="board" id="board"></div>
        </section>
        <section class="panel list">
          <table>
            <thead>
              <tr>
                <th>Контакт</th>
                <th>Компания</th>
                <th>Статус</th>
                <th>Бюджет</th>
                <th>Обновлён</th>
              </tr>
            </thead>
            <tbody id="lead-table"></tbody>
          </table>
        </section>
      </div>
    </section>

    <section id="admin-tab" class="panel hidden">
      <h2>Результаты тестов</h2>
      <p class="status">Здесь отображаются последние test runs, если тестовые scripts публикуют их через gateway.</p>
      <div id="test-runs"></div>
    </section>
  </main>
  <script>
    const statuses = [
      ['new', 'Новые'],
      ['contacted', 'Связались'],
      ['qualified', 'Квалифицированы'],
      ['won', 'Выиграны'],
      ['lost', 'Потеряны']
    ];
    let leads = [];

    const form = document.querySelector('#lead-form');
    const notice = document.querySelector('#form-notice');

    function escapeHtml(value) {
      return String(value ?? '').replace(/[&<>"']/g, (char) => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;'
      }[char]));
    }

    async function jsonFetch(url, options = {}) {
      const response = await fetch(url, options);
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        throw new Error(data.error || response.statusText);
      }
      return data;
    }

    function formatDate(value) {
      return value ? new Date(value).toLocaleString('ru-RU') : '';
    }

    function leadLabel(lead) {
      return [lead.company, lead.email || lead.phone].filter(Boolean).join(' • ') || 'Без деталей';
    }

    function renderMetrics() {
      const totalBudget = leads.reduce((sum, lead) => sum + Number(lead.budget || 0), 0);
      const active = leads.filter((lead) => !['won', 'lost'].includes(lead.status || 'new')).length;
      const won = leads.filter((lead) => lead.status === 'won').length;
      const qualified = leads.filter((lead) => lead.status === 'qualified').length;
      const metrics = [
        ['Всего лидов', leads.length],
        ['Активные', active],
        ['Квалифицированы', qualified],
        ['Выиграны / бюджет', won + ' / ' + totalBudget.toLocaleString('ru-RU')]
      ];
      document.querySelector('#lead-metrics').innerHTML = metrics.map(([label, value]) => (
        '<div class="metric"><span>' + escapeHtml(label) + '</span><strong>' + escapeHtml(value) + '</strong></div>'
      )).join('');
    }

    function renderBoard() {
      const board = document.querySelector('#board');
      board.innerHTML = '';
      renderMetrics();
      for (const [status, title] of statuses) {
        const items = leads.filter((lead) => (lead.status || 'new') === status);
        const column = document.createElement('div');
        column.className = 'column';
        column.innerHTML = '<h3><span>' + escapeHtml(title) + '</span><span>' + items.length + '</span></h3>';
        for (const lead of items) {
          const card = document.createElement('button');
          card.type = 'button';
          card.className = 'lead';
          card.innerHTML = '<strong>' + escapeHtml(lead.name) + '</strong><span>' + escapeHtml(leadLabel(lead)) + '</span><span>' + escapeHtml(lead.owner || 'без ответственного') + '</span>';
          card.addEventListener('click', () => editLead(lead));
          column.appendChild(card);
        }
        board.appendChild(column);
      }
    }

    function renderTable() {
      const table = document.querySelector('#lead-table');
      table.innerHTML = '';
      for (const lead of leads) {
        const row = document.createElement('tr');
        row.innerHTML = '<td>' + escapeHtml(lead.name) + '</td><td>' + escapeHtml(lead.company || '') + '</td><td><span class="pill">' + escapeHtml(lead.status || 'new') + '</span></td><td>' + escapeHtml(lead.budget || 0) + '</td><td>' + escapeHtml(formatDate(lead.updatedAt || lead.createdAt)) + '</td>';
        row.addEventListener('click', () => editLead(lead));
        table.appendChild(row);
      }
    }

    async function loadLeads() {
      const data = await jsonFetch('/leads');
      leads = data.items || [];
      renderBoard();
      renderTable();
    }

    function editLead(lead) {
      document.querySelector('#form-title').textContent = 'Редактирование лида';
      for (const field of ['id', 'name', 'company', 'email', 'phone', 'source', 'status', 'budget', 'owner', 'notes']) {
        const input = form.elements[field];
        if (input) {
          input.value = lead[field] || '';
        }
      }
      notice.textContent = 'Открыта карточка ' + lead.id;
    }

    function resetForm() {
      form.reset();
      form.elements.id.value = '';
      form.elements.status.value = 'new';
      document.querySelector('#form-title').textContent = 'Новый лид';
      notice.textContent = '';
    }

    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      const payload = Object.fromEntries(new FormData(form));
      const id = payload.id;
      delete payload.id;
      const saved = await jsonFetch(id ? '/leads/' + encodeURIComponent(id) : '/leads', {
        method: id ? 'PATCH' : 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(payload)
      });
      notice.textContent = 'Сохранено: ' + saved.id;
      resetForm();
      await loadLeads();
    });

    document.querySelector('#reset-form').addEventListener('click', resetForm);

    async function loadHealth() {
      try {
        const data = await jsonFetch('/health');
        document.querySelector('#health').textContent = 'frontend: ' + data.status + ' • gateway: ' + data.gatewayBaseUrl;
      } catch (error) {
        document.querySelector('#health').textContent = 'health error: ' + error.message;
      }
    }

    async function loadTestRuns() {
      const target = document.querySelector('#test-runs');
      try {
        const data = await jsonFetch('/test-runs');
        const items = data.items || [];
        target.innerHTML = items.length ? '' : '<p class="status">Результатов пока нет.</p>';
        for (const run of items) {
          const block = document.createElement('div');
          block.className = 'test-run ' + (run.status === 'ok' ? 'ok' : 'fail');
          const checks = (run.checks || []).map((check) => '<li>' + escapeHtml(check.status) + ' — ' + escapeHtml(check.title) + ' (' + escapeHtml(check.durationSeconds) + 's)</li>').join('');
          block.innerHTML = '<strong>' + escapeHtml(run.title) + '</strong> <span class="pill">' + escapeHtml(run.status) + '</span><div class="status">' + escapeHtml(formatDate(run.createdAt)) + ' • ' + escapeHtml(run.durationSeconds) + 's</div><ul>' + checks + '</ul>';
          target.appendChild(block);
        }
      } catch (error) {
        target.innerHTML = '<p class="status">Не удалось получить результаты тестов: ' + escapeHtml(error.message) + '</p>';
      }
    }

    document.querySelectorAll('nav button').forEach((button) => {
      button.addEventListener('click', async () => {
        document.querySelectorAll('nav button').forEach((item) => item.classList.remove('active'));
        button.classList.add('active');
        document.querySelector('#crm-tab').classList.toggle('hidden', button.dataset.tab !== 'crm');
        document.querySelector('#admin-tab').classList.toggle('hidden', button.dataset.tab !== 'admin');
        if (button.dataset.tab === 'admin') {
          await loadTestRuns();
        }
      });
    });

    if (window.location.pathname === '/admin') {
      document.querySelector('nav button[data-tab="admin"]').click();
    }

    loadHealth();
    loadLeads();
  </script>
</body>
</html>`;
}

const server = http.createServer(async (req, res) => {
  try {
    const path = requestPath(req);

    if (req.method === 'GET' && path === '/health') {
      sendJson(res, 200, {
        status: 'ok',
        service: 'frontend',
        environment: config.ENVIRONMENT,
        gatewayBaseUrl: config.GATEWAY_BASE_URL,
      });
      return;
    }

    if (req.method === 'GET' && (path === '/' || path === '/admin')) {
      sendHtml(res, 200, renderPage());
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
  console.log(`frontend stub listens on ${config.HOST}:${config.PORT}`);
});
