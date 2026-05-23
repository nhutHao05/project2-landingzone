// Configuration
let API_GATEWAY_URL = ''; // Will be loaded from config.json

// Mock Data
const mockIncidents = [
    {
        id: 'INC-20260523-001',
        severity: 'Critical',
        summary: 'Multiple failed SSH logins followed by successful login from anomalous IP, then suspicious lateral movement via SSM.',
        action: 'isolate_ec2',
        target: 'i-0abcdef1234567890',
        status: 'pending_approval'
    },
    {
        id: 'INC-20260523-002',
        severity: 'High',
        summary: 'IAM User "dev-intern" created 3 new administrator access keys and attempted to disable CloudTrail.',
        action: 'revoke_creds',
        target: 'dev-intern',
        status: 'pending_approval'
    },
    {
        id: 'INC-20260523-003',
        severity: 'High',
        summary: 'SQL Injection pattern detected originating from external IP addressing Web Tier ALB.',
        action: 'block_ip',
        target: '198.51.100.42',
        status: 'pending_approval'
    }
];

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

// Auth Logic (Mock)
loginForm.addEventListener('submit', async (e) => {
    e.preventDefault();
    
    // Load config before entering dashboard
    try {
        const res = await fetch('config.json');
        if (res.ok) {
            const config = await res.json();
            API_GATEWAY_URL = config.API_GATEWAY_URL;
            console.log("Loaded API Config:", API_GATEWAY_URL);
        }
    } catch (err) {
        console.warn("Could not load config.json, using mock API URL");
    }

    const username = document.getElementById('username').value;
    
    // Simulate login
    userDisplay.textContent = username || 'Admin';
    loginContainer.classList.add('hidden');
    dashboardContainer.classList.remove('hidden');
    
    renderTable();
});

logoutBtn.addEventListener('click', () => {
    dashboardContainer.classList.add('hidden');
    loginContainer.classList.remove('hidden');
    document.getElementById('username').value = '';
    document.getElementById('password').value = '';
});

// Rendering Logic
function renderTable() {
    tbody.innerHTML = '';
    mockIncidents.forEach(inc => {
        const tr = document.createElement('tr');
        
        const sevClass = inc.severity.toLowerCase() === 'critical' ? 'critical' : 'high';
        const statusClass = inc.status === 'pending_approval' ? 'pending' : 'resolved';
        const statusText = inc.status === 'pending_approval' ? 'Pending Approval' : 'Resolved';
        
        tr.innerHTML = `
            <td><strong>${inc.id}</strong></td>
            <td><span class="badge ${sevClass}">${inc.severity}</span></td>
            <td>${inc.summary}</td>
            <td><code>${inc.action}</code></td>
            <td>${inc.target}</td>
            <td><span class="badge ${statusClass}">${statusText}</span></td>
            <td>
                ${inc.status === 'pending_approval' 
                    ? `<button class="btn-primary btn-small approve-trigger" data-id="${inc.id}">Approve</button>` 
                    : '<button class="btn-secondary btn-small" disabled>Done</button>'}
            </td>
        `;
        tbody.appendChild(tr);
    });

    // Attach events to newly created buttons
    document.querySelectorAll('.approve-trigger').forEach(btn => {
        btn.addEventListener('click', (e) => {
            const id = e.target.getAttribute('data-id');
            openModal(id);
        });
    });
}

// Modal Logic
function openModal(id) {
    currentIncident = mockIncidents.find(i => i.id === id);
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
            if(!res.ok) throw new Error(data.error || 'API Error');
            showToast(`Success: ${data.message || 'Action executed'}`);
        }
        
        // Update local state
        currentIncident.status = 'resolved';
        renderTable();
        
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

refreshBtn.addEventListener('click', () => {
    showToast('Refreshing incident data...');
    // In a real app, this would fetch from an API
    setTimeout(renderTable, 500);
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
