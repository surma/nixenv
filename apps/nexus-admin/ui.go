package main

const indexHTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Nexus Admin</title>
<style>
  *, *::before, *::after { box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, monospace;
    background: #0d1117; color: #c9d1d9;
    margin: 0; padding: 1.5rem;
    max-width: 960px; margin: 0 auto;
  }
  h1 { color: #58a6ff; margin-bottom: 0.25rem; font-size: 1.4rem; }
  h1 small { color: #8b949e; font-weight: normal; font-size: 0.8rem; }

  /* Tabs */
  .tabs {
    display: flex; gap: 0; margin-bottom: 1rem; border-bottom: 1px solid #30363d;
  }
  .tab-btn {
    padding: 0.5rem 1.25rem; border: none; background: none;
    color: #8b949e; font-size: 0.9rem; font-weight: 600; cursor: pointer;
    border-bottom: 2px solid transparent; margin-bottom: -1px;
    transition: color 0.15s, border-color 0.15s;
  }
  .tab-btn:hover { color: #c9d1d9; }
  .tab-btn.active { color: #58a6ff; border-bottom-color: #58a6ff; }
  .tab-content { display: none; }
  .tab-content.active { display: block; }

  /* Shared controls */
  .deploy-controls {
    display: flex; gap: 0.5rem; margin-bottom: 1rem; align-items: stretch;
  }
  input, select {
    padding: 0.5rem 0.75rem;
    background: #161b22; border: 1px solid #30363d; color: #c9d1d9;
    border-radius: 6px; font-family: monospace; font-size: 0.9rem;
  }
  input:focus, select:focus { outline: none; border-color: #58a6ff; }
  .deploy-controls input { flex: 1; }
  button {
    padding: 0.5rem 1.25rem; border: none; border-radius: 6px;
    font-weight: 600; cursor: pointer; font-size: 0.9rem;
    transition: opacity 0.15s;
  }
  button:disabled { opacity: 0.5; cursor: not-allowed; }
  .btn-deploy { background: #238636; color: #fff; }
  .btn-deploy:hover:not(:disabled) { background: #2ea043; }
  .btn-cancel { background: #da3633; color: #fff; display: none; }
  .btn-cancel:hover:not(:disabled) { background: #f85149; }
  .btn-fetch { background: #1f6feb; color: #fff; }
  .btn-fetch:hover:not(:disabled) { background: #388bfd; }

  /* Logs form */
  .logs-form { margin-bottom: 1rem; }
  .logs-form .field { display: flex; flex-direction: column; gap: 0.25rem; }
  .logs-form .field label {
    font-size: 0.75rem; font-weight: 600; color: #8b949e;
    text-transform: uppercase; letter-spacing: 0.04em;
  }
  .logs-form select, .logs-form input { width: 100%; }
  .logs-primary {
    display: grid; grid-template-columns: 1fr 2fr; gap: 0.5rem;
    margin-bottom: 0.5rem;
  }
  .logs-secondary {
    display: grid; grid-template-columns: auto 1fr 1fr; gap: 0.5rem;
    align-items: end;
  }
  .logs-secondary .lines-boot {
    display: flex; gap: 0.5rem; align-items: end;
  }
  .logs-secondary .lines-boot .field-lines { width: 5rem; }
  .logs-secondary .field-boot {
    display: flex; align-items: center; gap: 0.35rem;
    padding-bottom: 0.5rem;
  }
  .logs-secondary .field-boot input[type="checkbox"] { margin: 0; }
  .logs-secondary .field-boot label {
    font-size: 0.85rem; color: #8b949e; white-space: nowrap;
    text-transform: none; letter-spacing: normal;
  }
  .logs-actions {
    display: flex; justify-content: flex-end; margin-top: 0.75rem;
  }
  @media (max-width: 600px) {
    .logs-primary { grid-template-columns: 1fr; }
    .logs-secondary { grid-template-columns: 1fr; }
    .logs-secondary .lines-boot { flex-wrap: wrap; }
  }

  .log-area {
    background: #010409; border: 1px solid #30363d; border-radius: 6px;
    padding: 0.75rem; height: 400px; overflow-y: auto;
    font-family: "SF Mono", "Fira Code", monospace; font-size: 0.8rem;
    line-height: 1.5; white-space: pre-wrap; word-break: break-all;
    margin-bottom: 1rem;
  }
  #deploy-log-area:empty::before {
    content: "No active deploy. Press Deploy to start.";
    color: #484f58;
  }
  #logs-output:empty::before {
    content: "Select a unit and press Fetch to view logs.";
    color: #484f58;
  }
  .log-line { color: #c9d1d9; }
  .log-line.deploy-msg { color: #58a6ff; font-weight: 600; }
  .log-line.error-msg { color: #f85149; }
  .log-line.done-success { color: #3fb950; font-weight: 700; }
  .log-line.done-fail { color: #f85149; font-weight: 700; }

  h2 { font-size: 1.1rem; color: #58a6ff; margin-top: 1.5rem; }
  .history { list-style: none; padding: 0; }
  .history li {
    padding: 0.5rem 0.75rem; border-bottom: 1px solid #21262d;
    display: flex; justify-content: space-between; align-items: center;
    font-size: 0.85rem;
  }
  .history li:hover { background: #161b22; }
  .history .meta { color: #8b949e; }
  .history a { color: #58a6ff; text-decoration: none; }
  .history a:hover { text-decoration: underline; }
  .badge {
    display: inline-block; padding: 0.15rem 0.5rem; border-radius: 999px;
    font-size: 0.75rem; font-weight: 600;
  }
  .badge-success { background: #238636; color: #fff; }
  .badge-running { background: #1f6feb; color: #fff; }
  .badge-failed { background: #da3633; color: #fff; }
  .badge-cancelled { background: #8b949e; color: #fff; }
</style>
</head>
<body>
<h1>Nexus Admin <small>deploy &amp; inspect</small></h1>

<div class="tabs">
  <button class="tab-btn active" onclick="switchTab('deploy')">Deploy</button>
  <button class="tab-btn" onclick="switchTab('logs')">Logs</button>
</div>

<!-- ===== Deploy Tab ===== -->
<div id="tab-deploy" class="tab-content active">

<div class="deploy-controls">
  <input type="text" id="flake-url" placeholder="Flake URL (leave empty for default)">
  <button class="btn-deploy" id="deploy-btn" onclick="startDeploy()">Deploy</button>
  <button class="btn-cancel" id="cancel-btn" onclick="cancelDeploy()">Cancel</button>
</div>

<div class="log-area" id="deploy-log-area"></div>

<h2>Deploy History</h2>
<ul class="history" id="history-list">
  <li class="meta">Loading...</li>
</ul>

</div>

<!-- ===== Logs Tab ===== -->
<div id="tab-logs" class="tab-content">

<div class="logs-form">
  <div class="logs-primary">
    <div class="field">
      <label for="logs-container">Container</label>
      <select id="logs-container">
        <option value="">host</option>
      </select>
    </div>
    <div class="field">
      <label for="logs-unit">Unit</label>
      <select id="logs-unit">
        <option value="">-- select unit --</option>
      </select>
    </div>
  </div>
  <div class="logs-secondary">
    <div class="lines-boot">
      <div class="field field-lines">
        <label for="logs-lines">Lines</label>
        <input type="number" id="logs-lines" value="100" min="1" max="10000">
      </div>
      <div class="field-boot">
        <input type="checkbox" id="logs-boot">
        <label for="logs-boot">current boot</label>
      </div>
    </div>
    <div class="field">
      <label for="logs-since">Since</label>
      <input type="text" id="logs-since" placeholder="e.g. -1h, 2026-01-01">
    </div>
    <div class="field">
      <label for="logs-until">Until</label>
      <input type="text" id="logs-until" placeholder="e.g. -30min, 2026-01-02">
    </div>
  </div>
  <div class="logs-actions">
    <button class="btn-fetch" id="logs-fetch-btn" onclick="fetchLogs()">Fetch Logs</button>
  </div>
</div>

<div class="log-area" id="logs-output"></div>

</div>

<script>
/* ===== Tab switching ===== */
function switchTab(name) {
  document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
  document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
  document.getElementById('tab-' + name).classList.add('active');
  document.querySelector('.tab-btn[onclick*="' + name + '"]').classList.add('active');
  if (name === 'logs') loadContainers();
}

/* ===== Deploy Tab ===== */
const deployLogArea = document.getElementById('deploy-log-area');
const deployBtn = document.getElementById('deploy-btn');
const cancelBtn = document.getElementById('cancel-btn');
const flakeInput = document.getElementById('flake-url');
const historyList = document.getElementById('history-list');
let evtSource = null;
let activeDeployId = null;

function appendDeployLog(text) {
  const div = document.createElement('div');
  div.className = 'log-line';
  if (text.startsWith('[deploy]')) {
    if (text.includes('SUCCEEDED') || text.startsWith('[deploy] DONE:success')) {
      div.className += ' done-success';
    } else if (text.includes('FAILED') || text.includes('cancelled') || (text.startsWith('[deploy] DONE:') && !text.includes('success'))) {
      div.className += ' done-fail';
    } else {
      div.className += ' deploy-msg';
    }
  } else if (text.startsWith('[error]')) {
    div.className += ' error-msg';
  }
  div.textContent = text;
  deployLogArea.appendChild(div);
  deployLogArea.scrollTop = deployLogArea.scrollHeight;
}

function setDeploying(id) {
  activeDeployId = id;
  deployBtn.disabled = true;
  cancelBtn.style.display = 'inline-block';
  cancelBtn.disabled = false;
}

function setIdle() {
  activeDeployId = null;
  deployBtn.disabled = false;
  cancelBtn.style.display = 'none';
}

function startDeploy() {
  deployBtn.disabled = true;
  deployLogArea.innerHTML = '';

  const body = {};
  if (flakeInput.value.trim()) {
    body.flake_url = flakeInput.value.trim();
  }

  fetch('/api/deploy', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify(body),
  })
  .then(r => {
    if (!r.ok) return r.json().then(e => { throw new Error(e.error || r.statusText); });
    return r.json();
  })
  .then(meta => {
    setDeploying(meta.id);
    appendDeployLog('[deploy] started: ' + meta.id);
    subscribeToStream(meta.id);
  })
  .catch(err => {
    appendDeployLog('[error] ' + err.message);
    setIdle();
  });
}

function cancelDeploy() {
  if (!activeDeployId) return;
  cancelBtn.disabled = true;
  fetch('/api/deploy/' + activeDeployId + '/cancel', { method: 'POST' })
    .then(r => {
      if (!r.ok) return r.json().then(e => { throw new Error(e.error || r.statusText); });
      appendDeployLog('[deploy] cancel requested...');
    })
    .catch(err => {
      appendDeployLog('[error] cancel failed: ' + err.message);
      cancelBtn.disabled = false;
    });
}

function subscribeToStream(id) {
  if (evtSource) evtSource.close();
  evtSource = new EventSource('/api/deploy/' + id + '/stream');
  evtSource.onmessage = function(e) {
    appendDeployLog(e.data);
    if (e.data.startsWith('[deploy] DONE:')) {
      evtSource.close();
      evtSource = null;
      setIdle();
      loadHistory();
    }
  };
  evtSource.onerror = function() {
    evtSource.close();
    evtSource = null;
    appendDeployLog('[deploy] connection lost, reconnecting...');
    setTimeout(function() {
      fetch('/api/deploys')
        .then(r => r.json())
        .then(data => {
          if (data.active_id === id) {
            subscribeToStream(id);
          } else {
            setIdle();
            loadHistory();
          }
        })
        .catch(() => {
          setTimeout(function() { subscribeToStream(id); }, 3000);
        });
    }, 2000);
  };
}

function loadHistory() {
  fetch('/api/deploys')
    .then(r => r.json())
    .then(data => {
      const deploys = data.deploys || [];
      const activeId = data.active_id || null;

      if (activeId && !activeDeployId) {
        setDeploying(activeId);
        deployLogArea.innerHTML = '';
        subscribeToStream(activeId);
      }

      historyList.innerHTML = '';
      if (deploys.length === 0) {
        historyList.innerHTML = '<li class="meta">No deploys yet.</li>';
        return;
      }
      deploys.forEach(d => {
        const li = document.createElement('li');
        const started = new Date(d.started_at).toLocaleString();
        const badgeClass = d.status === 'success' ? 'badge-success' :
                           d.status === 'running' ? 'badge-running' :
                           d.status === 'cancelled' ? 'badge-cancelled' : 'badge-failed';
        li.innerHTML =
          '<span>' +
            '<span class="badge ' + badgeClass + '">' + escapeHtml(d.status) + '</span> ' +
            '<span class="meta">' + started + '</span> ' +
            '<span class="meta">' + escapeHtml(d.flake_url) + '</span>' +
          '</span>' +
          '<span>' +
            '<a href="#" onclick="viewDeploy(\'' + d.id + '\', \'' + escapeHtml(d.status) + '\'); return false;">view</a>' +
          '</span>';
        historyList.appendChild(li);
      });
    })
    .catch(() => {
      historyList.innerHTML = '<li class="meta">Failed to load history.</li>';
    });
}

function viewDeploy(id, status) {
  deployLogArea.innerHTML = '';
  if (status === 'running') {
    subscribeToStream(id);
  } else {
    fetch('/api/deploys/' + id + '/log')
      .then(r => {
        if (!r.ok) throw new Error('not found');
        return r.text();
      })
      .then(text => {
        deployLogArea.innerHTML = '';
        text.split('\n').forEach(line => { if (line) appendDeployLog(line); });
      })
      .catch(err => {
        deployLogArea.innerHTML = '';
        appendDeployLog('[error] ' + err.message);
      });
  }
}

/* ===== Logs Tab ===== */
const logsContainerSel = document.getElementById('logs-container');
const logsUnitSel = document.getElementById('logs-unit');
const logsOutput = document.getElementById('logs-output');
let containersLoaded = false;

function loadContainers() {
  if (containersLoaded) return;
  fetch('/api/containers')
    .then(r => r.json())
    .then(data => {
      containersLoaded = true;
      // Keep the "host" option, add containers
      (data.containers || []).forEach(c => {
        const opt = document.createElement('option');
        opt.value = c;
        opt.textContent = c;
        logsContainerSel.appendChild(opt);
      });
      // Auto-load units for host
      loadUnits();
    })
    .catch(() => {});
}

logsContainerSel.addEventListener('change', function() {
  loadUnits();
});

function loadUnits() {
  const container = logsContainerSel.value;
  const url = container ? '/api/units?container=' + encodeURIComponent(container) : '/api/units';

  logsUnitSel.innerHTML = '<option value="">loading...</option>';
  fetch(url)
    .then(r => r.json())
    .then(data => {
      logsUnitSel.innerHTML = '<option value="">-- select unit --</option>';
      (data.units || []).forEach(u => {
        const opt = document.createElement('option');
        opt.value = u.unit;
        opt.textContent = u.unit + ' (' + u.sub + ')';
        logsUnitSel.appendChild(opt);
      });
    })
    .catch(() => {
      logsUnitSel.innerHTML = '<option value="">failed to load units</option>';
    });
}

function fetchLogs() {
  const unit = logsUnitSel.value;
  if (!unit) {
    logsOutput.textContent = 'Please select a unit first.';
    return;
  }

  const container = logsContainerSel.value;
  const lines = document.getElementById('logs-lines').value || '100';
  const boot = document.getElementById('logs-boot').checked;
  const since = document.getElementById('logs-since').value.trim();
  const until = document.getElementById('logs-until').value.trim();

  const params = new URLSearchParams();
  params.set('unit', unit);
  if (container) params.set('container', container);
  params.set('lines', lines);
  if (boot) params.set('boot', 'true');
  if (since) params.set('since', since);
  if (until) params.set('until', until);

  const btn = document.getElementById('logs-fetch-btn');
  btn.disabled = true;
  logsOutput.textContent = 'Fetching...';

  fetch('/api/logs?' + params.toString())
    .then(r => {
      if (!r.ok) throw new Error('HTTP ' + r.status);
      return r.text();
    })
    .then(text => {
      logsOutput.textContent = text || '(no log entries)';
      logsOutput.scrollTop = logsOutput.scrollHeight;
    })
    .catch(err => {
      logsOutput.textContent = 'Error: ' + err.message;
    })
    .finally(() => {
      btn.disabled = false;
    });
}

/* ===== Shared ===== */
function escapeHtml(s) {
  const div = document.createElement('div');
  div.textContent = s;
  return div.innerHTML;
}

// Load deploy history on page load
loadHistory();
</script>
</body>
</html>
`
