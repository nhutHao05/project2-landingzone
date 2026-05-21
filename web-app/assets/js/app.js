const state = {
  filter: 'all',
};

const list = document.querySelector('#incident-list');
const template = document.querySelector('#incident-template');
const form = document.querySelector('#incident-form');
const refreshButton = document.querySelector('#refresh-btn');

const metrics = {
  total: document.querySelector('#metric-total'),
  critical: document.querySelector('#metric-critical'),
  open: document.querySelector('#metric-open'),
  investigating: document.querySelector('#metric-investigating'),
};

function setHealth(ok, text) {
  const dot = document.querySelector('#health-dot');
  const label = document.querySelector('#health-text');
  dot.className = `dot ${ok ? 'ok' : 'bad'}`;
  label.textContent = text;
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  });

  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data.error || 'Request failed');
  }
  return data;
}

function renderMetrics(summary) {
  metrics.total.textContent = Number(summary.total || 0);
  metrics.critical.textContent = Number(summary.critical_open || 0);
  metrics.open.textContent = Number(summary.open_count || 0);
  metrics.investigating.textContent = Number(summary.investigating_count || 0);
}

function renderIncidents(incidents) {
  list.innerHTML = '';

  if (!incidents.length) {
    list.innerHTML = '<div class="empty-state">No incidents in this queue.</div>';
    return;
  }

  for (const incident of incidents) {
    const node = template.content.cloneNode(true);
    const card = node.querySelector('.incident-card');
    const severity = node.querySelector('.severity');
    const title = node.querySelector('h3');
    const meta = node.querySelector('p');
    const select = node.querySelector('.status-select');

    severity.textContent = incident.severity;
    severity.classList.add(incident.severity);
    title.textContent = incident.title;
    meta.textContent = `${incident.service_name} / ${incident.owner} / updated ${incident.updated_at}`;
    select.value = incident.status;
    card.dataset.id = incident.id;

    select.addEventListener('change', async () => {
      await api('/api/incidents.php', {
        method: 'PATCH',
        body: JSON.stringify({ id: incident.id, status: select.value }),
      });
      await loadIncidents();
    });

    list.appendChild(node);
  }
}

async function loadHealth() {
  try {
    await api('/api/health.php');
    setHealth(true, 'Layer 3 database connected');
  } catch (error) {
    setHealth(false, 'Database unavailable');
  }
}

async function loadIncidents() {
  try {
    document.querySelector('#active-filter').textContent = state.filter;
    const data = await api(`/api/incidents.php?status=${encodeURIComponent(state.filter)}`);
    renderMetrics(data.summary || {});
    renderIncidents(data.incidents || []);
  } catch (error) {
    list.innerHTML = `<div class="error-state">${error.message}</div>`;
  }
}

document.querySelectorAll('.nav-item').forEach((button) => {
  button.addEventListener('click', async () => {
    document.querySelectorAll('.nav-item').forEach((item) => item.classList.remove('active'));
    button.classList.add('active');
    state.filter = button.dataset.status;
    await loadIncidents();
  });
});

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  const formData = new FormData(form);
  const payload = Object.fromEntries(formData.entries());

  await api('/api/incidents.php', {
    method: 'POST',
    body: JSON.stringify(payload),
  });

  form.reset();
  await loadIncidents();
});

refreshButton.addEventListener('click', loadIncidents);

loadHealth();
loadIncidents();
