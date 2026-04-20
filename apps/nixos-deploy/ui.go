package main

const indexHTML = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>NixOS Deploy</title>
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
  .controls {
    display: flex; gap: 0.5rem; margin-bottom: 1rem; align-items: stretch;
  }
  .controls input {
    flex: 1; padding: 0.5rem 0.75rem;
    background: #161b22; border: 1px solid #30363d; color: #c9d1d9;
    border-radius: 6px; font-family: monospace; font-size: 0.9rem;
  }
  .controls input:focus { outline: none; border-color: #58a6ff; }
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

  #log-area {
    background: #010409; border: 1px solid #30363d; border-radius: 6px;
    padding: 0.75rem; height: 400px; overflow-y: auto;
    font-family: "SF Mono", "Fira Code", monospace; font-size: 0.8rem;
    line-height: 1.5; white-space: pre-wrap; word-break: break-all;
    margin-bottom: 1rem;
  }
  #log-area:empty::before {
    content: "No active deploy. Press Deploy to start.";
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
<h1>NixOS Deploy <small>rebuild &amp; switch</small></h1>

<div class="controls">
  <input type="text" id="flake-url" placeholder="Flake URL (leave empty for default)">
  <button class="btn-deploy" id="deploy-btn" onclick="startDeploy()">Deploy</button>
  <button class="btn-cancel" id="cancel-btn" onclick="cancelDeploy()">Cancel</button>
</div>

<div id="log-area"></div>

<h2>Deploy History</h2>
<ul class="history" id="history-list">
  <li class="meta">Loading...</li>
</ul>

<script>
const logArea = document.getElementById('log-area');
const deployBtn = document.getElementById('deploy-btn');
const cancelBtn = document.getElementById('cancel-btn');
const flakeInput = document.getElementById('flake-url');
const historyList = document.getElementById('history-list');
let evtSource = null;
let activeDeployId = null;

function appendLog(text) {
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
  logArea.appendChild(div);
  logArea.scrollTop = logArea.scrollHeight;
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
  logArea.innerHTML = '';

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
    appendLog('[deploy] started: ' + meta.id);
    subscribeToStream(meta.id);
  })
  .catch(err => {
    appendLog('[error] ' + err.message);
    setIdle();
  });
}

function cancelDeploy() {
  if (!activeDeployId) return;
  cancelBtn.disabled = true;
  fetch('/api/deploy/' + activeDeployId + '/cancel', { method: 'POST' })
    .then(r => {
      if (!r.ok) return r.json().then(e => { throw new Error(e.error || r.statusText); });
      appendLog('[deploy] cancel requested...');
    })
    .catch(err => {
      appendLog('[error] cancel failed: ' + err.message);
      cancelBtn.disabled = false;
    });
}

function subscribeToStream(id) {
  if (evtSource) evtSource.close();
  evtSource = new EventSource('/api/deploy/' + id + '/stream');
  evtSource.onmessage = function(e) {
    appendLog(e.data);
    if (e.data.startsWith('[deploy] DONE:')) {
      evtSource.close();
      evtSource = null;
      setIdle();
      loadHistory();
    }
  };
  evtSource.onerror = function() {
    // Server may have restarted. Try reconnecting after a delay.
    evtSource.close();
    evtSource = null;
    appendLog('[deploy] connection lost, reconnecting...');
    setTimeout(function() {
      // Check if deploy is still active
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
          // Server still down, retry later
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

      // If there's an active deploy and we're not tracking it, pick it up
      if (activeId && !activeDeployId) {
        setDeploying(activeId);
        logArea.innerHTML = '';
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
  logArea.innerHTML = '';
  if (status === 'running') {
    subscribeToStream(id);
  } else {
    fetch('/api/deploys/' + id + '/log')
      .then(r => {
        if (!r.ok) throw new Error('not found');
        return r.text();
      })
      .then(text => {
        logArea.innerHTML = '';
        text.split('\n').forEach(line => { if (line) appendLog(line); });
      })
      .catch(err => {
        logArea.innerHTML = '';
        appendLog('[error] ' + err.message);
      });
  }
}

function escapeHtml(s) {
  const div = document.createElement('div');
  div.textContent = s;
  return div.innerHTML;
}

// Load history on page load (also picks up active deploys after server restart)
loadHistory();
</script>
</body>
</html>
`
