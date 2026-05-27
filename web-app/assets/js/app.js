const state = {
  filter: 'all',
  incidents: [],
};

const list = document.querySelector('#incident-list');
const template = document.querySelector('#incident-template');
const createForm = document.querySelector('#incident-form');
const editForm = document.querySelector('#edit-form');
const editModal = document.querySelector('#edit-modal');
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
  state.incidents = incidents;
  list.innerHTML = '';

  if (!incidents.length) {
    list.innerHTML = '<div class="empty-state">No incidents in this queue.</div>';
    return;
  }

  for (const incident of incidents) {
    const node = template.content.cloneNode(true);
    const card = node.querySelector('.incident-card');
    const badge = node.querySelector('.severity-badge');
    const title = node.querySelector('.incident-title');
    const meta = node.querySelector('.incident-meta');
    const select = node.querySelector('.status-select');
    const deleteBtn = node.querySelector('.delete-btn');
    const editBtn = node.querySelector('.edit-btn');

    badge.textContent = incident.severity;
    badge.classList.add(`severity-${incident.severity}`);
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

    deleteBtn.addEventListener('click', async () => {
      if (confirm('Are you sure you want to delete this incident?')) {
        await api('/api/incidents.php', {
          method: 'DELETE',
          body: JSON.stringify({ id: incident.id }),
        });
        await loadIncidents();
      }
    });

    editBtn.addEventListener('click', () => {
      openEditModal(incident);
    });

    list.appendChild(node);
  }
}

function openEditModal(incident) {
  document.querySelector('#edit-id').value = incident.id;
  document.querySelector('#edit-title').value = incident.title;
  document.querySelector('#edit-service').value = incident.service_name;
  document.querySelector('#edit-severity').value = incident.severity;
  document.querySelector('#edit-status').value = incident.status;
  document.querySelector('#edit-owner').value = incident.owner;
  document.querySelector('#edit-description').value = incident.description || '';
  
  editModal.classList.remove('hidden');
}

function closeEditModal() {
  editModal.classList.add('hidden');
  editForm.reset();
}

document.querySelectorAll('.close-modal, .cancel-modal').forEach(btn => {
  btn.addEventListener('click', closeEditModal);
});

editForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  const formData = new FormData(editForm);
  const payload = Object.fromEntries(formData.entries());
  payload.id = parseInt(payload.id, 10);

  await api('/api/incidents.php', {
    method: 'PUT',
    body: JSON.stringify(payload),
  });

  closeEditModal();
  await loadIncidents();
});

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
    document.querySelector('#active-filter').textContent = state.filter.charAt(0).toUpperCase() + state.filter.slice(1);
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

createForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  const formData = new FormData(createForm);
  const payload = Object.fromEntries(formData.entries());

  await api('/api/incidents.php', {
    method: 'POST',
    body: JSON.stringify(payload),
  });

  createForm.reset();
  await loadIncidents();
});

refreshButton.addEventListener('click', loadIncidents);

loadHealth();
loadIncidents();
