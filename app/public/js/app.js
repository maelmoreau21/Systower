// ============================================================================
// Systower Web UI — Frontend SPA Controller
// ============================================================================

let currentTab = 'containers';
let containersData = [];
let activeFilter = 'all';
let currentLogSource = 'systower';
let ws = null;

// Initialize on DOM ready
document.addEventListener('DOMContentLoaded', () => {
    initNavigation();
    initUserProfile();
    loadContainers();
    loadHostSystem();
    loadConfig();
    initLogStream();
    initTopActions();
});

// Helper for safe JSON fetching with auth redirect
async function safeFetch(url, options = {}) {
    const res = await fetch(url, options);
    if (res.status === 401) {
        window.location.href = '/login.html';
        throw new Error('Unauthorized');
    }
    return res;
}

// Toast notifications
function showToast(message, type = 'info') {
    const container = document.getElementById('toast-container');
    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    toast.innerHTML = `<span>${message}</span>`;
    container.appendChild(toast);

    setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transform = 'translateY(10px)';
        toast.style.transition = 'all 0.3s ease';
        setTimeout(() => toast.remove(), 300);
    }, 4000);
}

// User Profile & OIDC / Password Auth
async function initUserProfile() {
    try {
        const res = await fetch('/auth/user');
        const data = await res.json();

        const nameEl = document.getElementById('user-display-name');
        const emailEl = document.getElementById('user-display-email');
        const avatarEl = document.getElementById('user-avatar');
        const logoutBtn = document.getElementById('btn-logout');

        if (data.authenticated && data.user) {
            nameEl.textContent = data.user.name || 'Admin';
            emailEl.textContent = data.user.email || '';
            avatarEl.textContent = (data.user.name || 'A').charAt(0).toUpperCase();

            if (data.authRequired || data.oidcEnabled || data.basicAuthEnabled) {
                logoutBtn.style.display = 'flex';
            }
        }
    } catch (e) {
        console.error('Failed to load user info', e);
    }
}

// Navigation
function initNavigation() {
    const navItems = document.querySelectorAll('.nav-item');
    navItems.forEach(item => {
        item.addEventListener('click', () => {
            const targetTab = item.dataset.tab;
            switchTab(targetTab);
        });
    });
}

function switchTab(tabId) {
    currentTab = tabId;

    // Update Nav
    document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
    const targetNav = document.getElementById(`nav-${tabId}`);
    if (targetNav) targetNav.classList.add('active');

    // Update Panes
    document.querySelectorAll('.tab-pane').forEach(el => el.classList.remove('active'));
    const targetPane = document.getElementById(`tab-${tabId}`);
    if (targetPane) targetPane.classList.add('active');

    // Update Title
    const titleMap = {
        containers: { title: 'Docker Containers', subtitle: 'Monitor and update containers running on this Docker engine' },
        system: { title: 'Host System', subtitle: 'Manage updates for the local host operating system' },
        settings: { title: 'Configuration', subtitle: 'Configure automated scheduling, Docker filters, and update policies' },
        notifications: { title: 'Notifications', subtitle: 'Receive alerts when container or system updates occur' },
        logs: { title: 'Live Logs', subtitle: 'Real-time engine and web service logs' }
    };

    if (titleMap[tabId]) {
        document.getElementById('page-title').textContent = titleMap[tabId].title;
        document.getElementById('page-subtitle').textContent = titleMap[tabId].subtitle;
    }

    // Refresh active tab data
    if (tabId === 'containers') loadContainers();
    if (tabId === 'system') loadHostSystem();
    if (tabId === 'settings') loadConfig();
}

// Topbar Actions
function initTopActions() {
    const triggerBtn = document.getElementById('btn-trigger-all');
    triggerBtn.addEventListener('click', async () => {
        triggerBtn.disabled = true;
        triggerBtn.classList.add('loading');
        showToast('Triggering full Systower update cycle...', 'info');

        try {
            const res = await safeFetch('/api/config/trigger-run', { method: 'POST' });
            const data = await res.json();
            if (data.success) {
                showToast('Update cycle completed successfully!', 'success');
                loadContainers();
                loadHostSystem();
            } else {
                showToast(`Run completed with errors: ${data.error || 'Check logs'}`, 'error');
            }
        } catch (err) {
            showToast(`Failed to trigger run: ${err.message}`, 'error');
        } finally {
            triggerBtn.disabled = false;
            triggerBtn.classList.remove('loading');
        }
    });

    // Refresh containers button
    document.getElementById('btn-refresh-containers').addEventListener('click', () => loadContainers());

    // Search filter
    document.getElementById('container-search').addEventListener('input', (e) => {
        renderContainers(e.target.value);
    });

    // Filter buttons
    document.querySelectorAll('.filter-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            document.querySelectorAll('.filter-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            activeFilter = btn.dataset.filter;
            renderContainers(document.getElementById('container-search').value);
        });
    });

    // Host system update button
    document.getElementById('btn-update-host-system')?.addEventListener('click', async () => {
        showToast('Starting system update on host machine...', 'info');
        try {
            const res = await safeFetch('/api/system/update', { method: 'POST' });
            const data = await res.json();
            if (data.success) {
                showToast('Host system update finished successfully!', 'success');
                loadHostSystem();
            } else {
                showToast(`Host update error: ${data.error}`, 'error');
            }
        } catch (e) {
            showToast(`Host update failed: ${e.message}`, 'error');
        }
    });
}

// ============================================================================
// 1. CONTAINERS
// ============================================================================

async function loadContainers() {
    const listEl = document.getElementById('containers-list');
    try {
        const res = await safeFetch('/api/containers');
        const data = await res.json();
        containersData = data.containers || [];

        document.getElementById('container-count-badge').textContent = containersData.length;
        renderContainers(document.getElementById('container-search').value);
    } catch (err) {
        listEl.innerHTML = `<div class="card error-card">Failed to load containers: ${err.message}</div>`;
    }
}

function renderContainers(searchQuery = '') {
    const listEl = document.getElementById('containers-list');
    const query = searchQuery.toLowerCase().trim();

    let filtered = containersData.filter(c => {
        const matchesQuery = c.name.toLowerCase().includes(query) ||
                             c.image.toLowerCase().includes(query) ||
                             (c.composeProject && c.composeProject.toLowerCase().includes(query));

        if (!matchesQuery) return false;

        if (activeFilter === 'active') return c.running && !c.isExcluded;
        if (activeFilter === 'excluded') return c.isExcluded;
        if (activeFilter === 'compose') return c.isCompose;
        return true;
    });

    if (filtered.length === 0) {
        listEl.innerHTML = `<div class="empty-state">No containers match the current filter.</div>`;
        return;
    }

    listEl.innerHTML = filtered.map(c => {
        const healthClass = c.health === 'healthy' || c.health === 'running' ? 'healthy' : (c.health === 'unhealthy' ? 'unhealthy' : 'starting');
        const excludeBtnText = c.isExcluded ? 'Include' : 'Exclude';
        const excludeClass = c.isExcluded ? 'btn-secondary' : 'btn-secondary';

        return `
            <div class="container-card ${c.isExcluded ? 'excluded' : ''}" id="card-${c.id}">
                <div class="card-top">
                    <div class="container-title-group">
                        <div class="container-name">${c.name}</div>
                        <div class="container-image" title="${c.image}">${c.image}</div>
                    </div>
                    <span class="status-badge ${healthClass}">${c.health}</span>
                </div>

                <div class="tag-list">
                    ${c.isCompose ? `<span class="tag compose">📦 ${c.composeProject}:${c.composeService}</span>` : ''}
                    ${c.customSchedule ? `<span class="tag schedule">📅 ${c.customSchedule}</span>` : ''}
                    ${c.stopTimeout ? `<span class="tag">⏱ ${c.stopTimeout}s</span>` : ''}
                    ${c.isExcluded ? `<span class="tag excluded-tag">🚫 Excluded (${c.excludeReason})</span>` : ''}
                </div>

                <div class="card-actions">
                    <button class="btn btn-primary btn-sm" onclick="updateContainer('${c.id}', '${c.name}')">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <polyline points="23 4 23 10 17 10"></polyline>
                            <path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"></path>
                        </svg>
                        <span>Update</span>
                    </button>
                    <button class="btn ${excludeClass} btn-sm" onclick="toggleContainerExclude('${c.name}')">
                        ${excludeBtnText}
                    </button>
                    <button class="btn btn-secondary btn-sm btn-icon" onclick="inspectContainer('${c.id}', '${c.name}')" title="Inspect JSON">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <circle cx="12" cy="12" r="10"></circle>
                            <line x1="12" y1="16" x2="12" y2="12"></line>
                            <line x1="12" y1="8" x2="12.01" y2="8"></line>
                        </svg>
                    </button>
                </div>
            </div>
        `;
    }).join('');
}

async function updateContainer(id, name) {
    showToast(`Starting update for container '${name}'...`, 'info');
    try {
        const res = await safeFetch(`/api/containers/${id}/update`, { method: 'POST' });
        const data = await res.json();
        if (data.success) {
            showToast(`Container '${name}' updated successfully!`, 'success');
            loadContainers();
        } else {
            showToast(`Update failed for '${name}': ${data.error}`, 'error');
        }
    } catch (err) {
        showToast(`Failed to update '${name}': ${err.message}`, 'error');
    }
}

async function toggleContainerExclude(name) {
    try {
        const res = await safeFetch(`/api/containers/${encodeURIComponent(name)}/toggle-exclude`, { method: 'POST' });
        const data = await res.json();
        if (data.success) {
            showToast(`Container '${name}' ${data.isExcluded ? 'excluded' : 'included'} in update list`, 'info');
            loadContainers();
        }
    } catch (err) {
        showToast(`Error toggling exclusion: ${err.message}`, 'error');
    }
}

async function inspectContainer(id, name) {
    const modal = document.getElementById('inspect-modal');
    const content = document.getElementById('inspect-json-content');
    document.getElementById('inspect-modal-title').textContent = `Inspection: ${name}`;
    content.textContent = 'Loading container metadata...';
    modal.classList.add('active');

    try {
        const res = await safeFetch(`/api/containers/${id}/inspect`);
        const json = await res.json();
        content.textContent = JSON.stringify(json, null, 2);
    } catch (err) {
        content.textContent = `Error inspecting container: ${err.message}`;
    }
}

function closeInspectModal() {
    document.getElementById('inspect-modal').classList.remove('active');
}

// ============================================================================
// 2. HOST SYSTEM
// ============================================================================

async function loadHostSystem() {
    try {
        const res = await safeFetch('/api/system/status');
        const data = await res.json();
        if (data.success && data.host) {
            document.getElementById('host-os-name').textContent = data.host.os;
            document.getElementById('host-kernel').textContent = data.host.kernel;
            document.getElementById('host-uptime').textContent = data.host.uptime;
            const badge = document.getElementById('host-status-badge');
            if (data.host.rebootRequired) {
                badge.innerHTML = `<span class="status-badge starting">Reboot Required</span>`;
            } else {
                badge.innerHTML = `<span class="status-badge healthy">Online</span>`;
            }
        }
    } catch (e) {
        console.error('Failed to load host status', e);
    }
}

// ============================================================================
// 3. CONFIGURATION
// ============================================================================

async function loadConfig() {
    try {
        const res = await safeFetch('/api/config');
        const cfg = await res.json();

        // Populate general
        if (cfg.general) {
            document.getElementById('cfg-cron').value = cfg.general.cron || '0 4 * * *';
            document.getElementById('cfg-logLevel').value = cfg.general.logLevel || 'info';
            document.getElementById('cfg-runOnStart').checked = !!cfg.general.runOnStart;
            document.getElementById('cfg-dryRun').checked = !!cfg.general.dryRun;
        }

        // Populate docker
        if (cfg.docker) {
            document.getElementById('cfg-dockerEnabled').checked = cfg.docker.enabled !== false;
            document.getElementById('cfg-dockerCleanup').checked = cfg.docker.cleanup !== false;
            document.getElementById('cfg-dockerMonitorOnly').checked = !!cfg.docker.monitorOnly;
            document.getElementById('cfg-stopTimeout').value = cfg.docker.stopTimeout || 30;
            document.getElementById('cfg-healthcheckTimeout').value = cfg.docker.healthcheckTimeout || 30;
        }

        // Populate system
        if (cfg.system) {
            document.getElementById('cfg-systemEnabled').checked = !!cfg.system.enabled;
            document.getElementById('cfg-systemReboot').checked = !!cfg.system.reboot;
        }

        // Populate notifications
        if (cfg.notifications) {
            document.getElementById('notif-discord-url').value = cfg.notifications.discord?.webhookUrl || '';
            document.getElementById('notif-slack-url').value = cfg.notifications.slack?.webhookUrl || '';
            document.getElementById('notif-telegram-token').value = cfg.notifications.telegram?.botToken || '';
            document.getElementById('notif-telegram-chat').value = cfg.notifications.telegram?.chatId || '';
            document.getElementById('notif-webhook-url').value = cfg.notifications.webhook?.url || '';
        }
    } catch (err) {
        showToast(`Failed to load configuration: ${err.message}`, 'error');
    }
}

document.getElementById('config-form').addEventListener('submit', async (e) => {
    e.preventDefault();

    const config = {
        general: {
            cron: document.getElementById('cfg-cron').value.trim(),
            logLevel: document.getElementById('cfg-logLevel').value,
            runOnStart: document.getElementById('cfg-runOnStart').checked,
            dryRun: document.getElementById('cfg-dryRun').checked
        },
        docker: {
            enabled: document.getElementById('cfg-dockerEnabled').checked,
            cleanup: document.getElementById('cfg-dockerCleanup').checked,
            monitorOnly: document.getElementById('cfg-dockerMonitorOnly').checked,
            stopTimeout: parseInt(document.getElementById('cfg-stopTimeout').value, 10),
            healthcheckTimeout: parseInt(document.getElementById('cfg-healthcheckTimeout').value, 10),
            exclude: [],
            includeOnly: []
        },
        system: {
            enabled: document.getElementById('cfg-systemEnabled').checked,
            reboot: document.getElementById('cfg-systemReboot').checked
        }
    };

    // Preserve existing exclusions
    try {
        const curRes = await safeFetch('/api/config');
        const cur = await curRes.json();
        config.docker.exclude = cur.docker?.exclude || [];
        config.docker.includeOnly = cur.docker?.includeOnly || [];
        config.notifications = cur.notifications || {};
    } catch (e) {}

    try {
        const res = await safeFetch('/api/config', {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(config)
        });
        const data = await res.json();
        if (data.success) {
            showToast('Configuration saved successfully!', 'success');
        } else {
            showToast(`Failed to save: ${data.error}`, 'error');
        }
    } catch (err) {
        showToast(`Error saving configuration: ${err.message}`, 'error');
    }
});

// ============================================================================
// 4. NOTIFICATIONS
// ============================================================================

async function testNotification(type) {
    showToast(`Sending test message to ${type}...`, 'info');

    const payload = { type };
    if (type === 'discord') payload.webhookUrl = document.getElementById('notif-discord-url').value.trim();
    if (type === 'slack') payload.webhookUrl = document.getElementById('notif-slack-url').value.trim();
    if (type === 'telegram') {
        payload.botToken = document.getElementById('notif-telegram-token').value.trim();
        payload.chatId = document.getElementById('notif-telegram-chat').value.trim();
    }
    if (type === 'webhook') payload.webhookUrl = document.getElementById('notif-webhook-url').value.trim();

    try {
        const res = await safeFetch('/api/notifications/test', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(payload)
        });
        const data = await res.json();
        if (data.success) {
            showToast(`Test message to ${type} sent successfully!`, 'success');
        } else {
            showToast(`Test failed: ${data.error}`, 'error');
        }
    } catch (err) {
        showToast(`Error testing notification: ${err.message}`, 'error');
    }
}

document.getElementById('btn-save-notifications').addEventListener('click', async () => {
    try {
        const curRes = await safeFetch('/api/config');
        const config = await curRes.json();

        config.notifications = {
            enabled: true,
            discord: { enabled: !!document.getElementById('notif-discord-url').value, webhookUrl: document.getElementById('notif-discord-url').value.trim() },
            slack: { enabled: !!document.getElementById('notif-slack-url').value, webhookUrl: document.getElementById('notif-slack-url').value.trim() },
            telegram: { enabled: !!document.getElementById('notif-telegram-token').value, botToken: document.getElementById('notif-telegram-token').value.trim(), chatId: document.getElementById('notif-telegram-chat').value.trim() },
            webhook: { enabled: !!document.getElementById('notif-webhook-url').value, url: document.getElementById('notif-webhook-url').value.trim() }
        };

        const res = await safeFetch('/api/config', {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(config)
        });
        const data = await res.json();
        if (data.success) {
            showToast('Notification settings saved!', 'success');
        } else {
            showToast(`Failed to save notifications: ${data.error}`, 'error');
        }
    } catch (err) {
        showToast(`Error saving notifications: ${err.message}`, 'error');
    }
});

// ============================================================================
// 5. LIVE LOGS
// ============================================================================

function initLogStream() {
    const logOutput = document.getElementById('log-output');
    const terminalWindow = document.getElementById('terminal-window');

    // Connect WebSocket
    const proto = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${proto}//${window.location.host}/ws/logs`;

    try {
        ws = new WebSocket(wsUrl);

        ws.onopen = () => {
            console.log('[WebSocket] Connected to log stream');
        };

        ws.onmessage = (event) => {
            const msg = JSON.parse(event.data);
            if (msg.type === 'init') {
                logOutput.textContent = msg.data || 'No logs yet.';
            } else if (msg.type === 'append') {
                logOutput.textContent += msg.data;
            }

            if (document.getElementById('log-auto-scroll').checked) {
                terminalWindow.scrollTop = terminalWindow.scrollHeight;
            }
        };

        ws.onerror = (err) => {
            console.warn('[WebSocket] Error, falling back to HTTP polling', err);
            startLogPolling();
        };

        ws.onclose = () => {
            startLogPolling();
        };
    } catch (e) {
        startLogPolling();
    }

    // Source buttons
    document.querySelectorAll('.log-source-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            document.querySelectorAll('.log-source-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            currentLogSource = btn.dataset.source;
            fetchLogsHttp();
        });
    });

    // Clear logs button
    document.getElementById('btn-clear-logs').addEventListener('click', () => {
        logOutput.textContent = '';
    });
}

function startLogPolling() {
    setInterval(() => {
        if (currentTab === 'logs') {
            fetchLogsHttp();
        }
    }, 4000);
}

async function fetchLogsHttp() {
    try {
        const res = await safeFetch(`/api/logs?source=${currentLogSource}&lines=200`);
        const data = await res.json();
        const logOutput = document.getElementById('log-output');
        logOutput.textContent = data.logs || 'No logs available.';

        if (document.getElementById('log-auto-scroll').checked) {
            const terminalWindow = document.getElementById('terminal-window');
            terminalWindow.scrollTop = terminalWindow.scrollHeight;
        }
    } catch (e) {}
}
