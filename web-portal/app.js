// Configuration
let API_GATEWAY_URL = ''; // Will be loaded from config.json
let INCIDENTS_API_URL = '';

let incidents = [];
let refreshTimer = null;

// DOM Elements
const loginContainer = document.getElementById('login-container');
const dashboardContainer = document.getElementById('dashboard-container');
const loginForm = document.getElementById('login-form');
const logoutBtn = document.getElementById('logout-btn');
const userDisplay = document.getElementById('user-display');
const tbody = document.getElementById('incidents-body');
const approveModal = document.getElementById('approve-modal');
const modalDescription = document.getElementById('modal-description');
const modalDetails = document.getElementById('modal-details');
const cancelBtn = document.getElementById('cancel-btn');
const confirmBtn = document.getElementById('confirm-btn');
const toast = document.getElementById('toast');
const refreshBtn = document.getElementById('refresh-btn');

let currentIncident = null;

async function loadConfig() {
    const res = await fetch('config.json', { cache: 'no-store' });
    if (!res.ok) throw new Error('Unable to load config.json');

    const config = await res.json();
    API_GATEWAY_URL = config.API_GATEWAY_URL || '';
    INCIDENTS_API_URL = config.INCIDENTS_API_URL || API_GATEWAY_URL.replace(/\/remediate\/?$/, '/incidents');
    console.log('Loaded API Config:', { API_GATEWAY_URL, INCIDENTS_API_URL });
}

// Auth Logic (Mock)
loginForm.addEventListener('submit', async (e) => {
    e.preventDefault();

    // Load config before entering dashboard
    try {
        await loadConfig();
    } catch (err) {
        console.warn('Could not load config.json:', err);
    }

    const username = document.getElementById('username').value;

    // Simulate login
    userDisplay.textContent = username || 'Admin';
    loginContainer.classList.add('hidden');
    dashboardContainer.classList.remove('hidden');

    await fetchIncidents();
    startAutoRefresh();
});

logoutBtn.addEventListener('click', () => {
    stopAutoRefresh();
    dashboardContainer.classList.add('hidden');
    loginContainer.classList.remove('hidden');
    document.getElementById('username').value = '';
    document.getElementById('password').value = '';
});

async function fetchIncidents({ silent = false } = {}) {
    if (!INCIDENTS_API_URL) {
        incidents = [];
        renderTable();
        if (!silent) showToast('Incidents API is not configured. Run Terraform to refresh config.json.', true);
        return;
    }

    try {
        const res = await fetch(INCIDENTS_API_URL, { cache: 'no-store' });
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Could not fetch incidents');

        incidents = Array.isArray(data.incidents) ? data.incidents.map(normalizeIncident) : [];
        renderTable();
        if (!silent) showToast(`Loaded ${incidents.length} live incident(s).`);
    } catch (err) {
        if (!silent) showToast(`Error: ${err.message}`, true);
    }
}

function startAutoRefresh() {
    stopAutoRefresh();
    refreshTimer = setInterval(() => fetchIncidents({ silent: true }), 30000);
}

function stopAutoRefresh() {
    if (refreshTimer) clearInterval(refreshTimer);
    refreshTimer = null;
}

function normalizeIncident(inc) {
    const status = inc.incident_status || inc.status || 'Pending Approval';
    const action = inc.action_type || inc.remediation_action || inc.recommended_action || 'block_ip';

    return {
        id: inc.incident_id || inc.id || 'unknown',
        severity: inc.severity || 'High',
        summary: inc.summary || inc.message || 'Elastic SIEM alert received',
        action,
        target: inc.target || inc.source_ip || inc.destination_ip || 'unknown',
        status: status.toLowerCase().replace(/\s+/g, '_'),
        timestamp: inc.timestamp || inc.updated_at || ''
    };
}

function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>"']/g, (char) => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#039;'
    }[char]));
}

// Rendering Logic
function renderTable() {
    tbody.innerHTML = '';
    const tableElement = document.getElementById('incidents-table');
    const emptyState = document.getElementById('empty-state');
    const pendingBadge = document.getElementById('pending-actions-badge');
    const metricTotal = document.getElementById('metric-total');
    const metricCritical = document.getElementById('metric-critical');
    const metricMitigations = document.getElementById('metric-mitigations');

    const criticalCount = incidents.filter(inc => inc.severity.toLowerCase() === 'critical').length;
    const resolvedCount = incidents.filter(inc => inc.status === 'resolved').length;

    metricTotal.textContent = incidents.length;
    metricCritical.textContent = criticalCount;
    metricMitigations.textContent = resolvedCount;

    if (incidents.length === 0) {
        tableElement.classList.add('hidden');
        emptyState.classList.remove('hidden');
        pendingBadge.textContent = '0 Pending Actions';
        pendingBadge.classList.remove('pulse-red');
        pendingBadge.style.background = 'var(--success)';
        return;
    }

    tableElement.classList.remove('hidden');
    emptyState.classList.add('hidden');

    let pendingCount = 0;

    incidents.forEach(inc => {
        const tr = document.createElement('tr');

        const sevClass = inc.severity.toLowerCase() === 'critical' ? 'critical' : 'high';
        
        let statusClass = 'pending';
        let statusText = 'Pending Approval';
        if (inc.status === 'resolved') {
            statusClass = 'resolved';
            statusText = 'Resolved';
        } else if (inc.status === 'rejected') {
            statusClass = 'rejected';
            statusText = 'Rejected';
        }

        if (inc.status === 'pending_approval') pendingCount++;

        tr.innerHTML = `
            <td><strong>${escapeHtml(inc.id)}</strong></td>
            <td><span class="badge ${sevClass}">${escapeHtml(inc.severity)}</span></td>
            <td>${escapeHtml(inc.summary)}</td>
            <td><code>${escapeHtml(inc.action)}</code></td>
            <td>${escapeHtml(inc.target)}</td>
            <td><span class="badge ${statusClass}">${statusText}</span></td>
            <td>
                ${inc.status === 'pending_approval'
                    ? `<div style="display: flex; gap: 8px;">
                         <button class="btn-primary btn-small approve-trigger" data-id="${escapeHtml(inc.id)}">Approve</button>
                         <button class="btn-danger btn-small reject-trigger" data-id="${escapeHtml(inc.id)}">Reject</button>
                       </div>`
                    : inc.status === 'rejected'
                        ? '<button class="btn-secondary btn-small" disabled style="color: var(--danger); opacity: 0.6;">Rejected</button>'
                        : '<button class="btn-secondary btn-small" disabled>Done</button>'}
            </td>
        `;
        tbody.appendChild(tr);
    });

    if (pendingCount > 0) {
        pendingBadge.textContent = `${pendingCount} Pending Actions`;
        pendingBadge.classList.add('pulse-red');
        pendingBadge.style.background = 'var(--danger)';
    } else {
        pendingBadge.textContent = '0 Pending Actions';
        pendingBadge.classList.remove('pulse-red');
        pendingBadge.style.background = 'var(--success)';
    }

    // Attach events to newly created buttons
    document.querySelectorAll('.approve-trigger').forEach(btn => {
        btn.addEventListener('click', (e) => {
            const id = e.target.getAttribute('data-id');
            openModal(id, 'approve');
        });
    });

    document.querySelectorAll('.reject-trigger').forEach(btn => {
        btn.addEventListener('click', (e) => {
            const id = e.target.getAttribute('data-id');
            openModal(id, 'reject');
        });
    });
}

// Tab Switching Logic
document.querySelectorAll('#sidebar-nav a').forEach(link => {
    link.addEventListener('click', (e) => {
        e.preventDefault();

        // Remove active class from all links
        document.querySelectorAll('#sidebar-nav a').forEach(l => l.classList.remove('active'));
        // Add active class to clicked link
        e.target.classList.add('active');

        // Hide all views
        document.querySelectorAll('.view-section').forEach(view => {
            view.classList.add('hidden');
            view.classList.remove('active');
        });

        // Show target view
        const targetId = e.target.getAttribute('data-target');
        const targetView = document.getElementById(targetId);
        if (targetView) {
            targetView.classList.remove('hidden');
            targetView.classList.add('active');
        }
    });
});

// Modal Logic
function openModal(id) {
    currentIncident = incidents.find(i => i.id === id);
    if (!currentIncident) return;

    modalDescription.textContent = `Are you sure you want to execute "${currentIncident.action}" on target "${currentIncident.target}" to remediate incident ${currentIncident.id}?`;

    modalDetails.textContent = JSON.stringify({
        incident_id: currentIncident.id,
        action_type: currentIncident.action,
        target: currentIncident.target
    }, null, 2);

    approveModal.classList.remove('hidden');
}

cancelBtn.addEventListener('click', () => {
    approveModal.classList.add('hidden');
    currentIncident = null;
});

confirmBtn.addEventListener('click', async () => {
    if (!currentIncident) return;

    const payload = {
        incident_id: currentIncident.id,
        action_type: currentIncident.action,
        target: currentIncident.target
    };

    // Change button state
    confirmBtn.textContent = 'Executing...';
    confirmBtn.disabled = true;

    try {
        if (!API_GATEWAY_URL || API_GATEWAY_URL === '') {
            // Mock delay if URL is not configured
            await new Promise(r => setTimeout(r, 1500));
            showToast('Simulated success. Deploy Terraform to generate config.json for real integration.');
        } else {
            // Real API call
            const res = await fetch(API_GATEWAY_URL, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload)
            });
            const data = await res.json();
            if (!res.ok) throw new Error(data.error || 'API Error');
            showToast(`Success: ${data.message || 'Action executed'}`);
        }

        // Update local state
        currentIncident.status = 'resolved';
        renderTable();
        await fetchIncidents({ silent: true });

    } catch (err) {
        showToast(`Error: ${err.message}`, true);
    } finally {
        // Reset and close
        confirmBtn.textContent = 'Execute Action';
        confirmBtn.disabled = false;
        approveModal.classList.add('hidden');
        currentIncident = null;
    }
});

refreshBtn.addEventListener('click', async () => {
    showToast('Refreshing incident data...');
    await fetchIncidents();
});

// Toast Logic
function showToast(message, isError = false) {
    toast.textContent = message;
    toast.style.borderColor = isError ? 'var(--danger)' : 'var(--accent)';
    toast.classList.remove('hidden');

    setTimeout(() => {
        toast.classList.add('hidden');
    }, 4000);
}
