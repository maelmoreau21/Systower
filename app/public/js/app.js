// ============================================================================
// Systower Web UI — Frontend SPA Controller (Bilingual FR / EN)
// ============================================================================

let currentTab = 'containers';
let containersData = [];
let activeFilter = 'all';
let currentLogSource = 'systower';
let ws = null;
let currentLang = localStorage.getItem('systower_lang') || (navigator.language.startsWith('fr') ? 'fr' : 'en');

// ============================================================================
// Complete Translations Dictionary
// ============================================================================
const i18n = {
    fr: {
        navContainers: "Conteneurs",
        navHostSystem: "Système Hôte",
        navConfig: "Configuration",
        navNotif: "Notifications",
        navLogs: "Logs en direct",
        daemonActive: "Démon Actif",
        runUpdatesNow: "Mettre à jour maintenant",
        searchPlaceholder: "Rechercher par nom, image ou stack...",
        filterAll: "Tous",
        filterActive: "Actifs",
        filterExcluded: "Exclus",
        filterCompose: "Stacks Compose",
        loadingContainers: "Chargement des conteneurs...",
        noContainers: "Aucun conteneur ne correspond aux critères.",
        hostTitle: "Machine Hôte",
        hostDesc: "Maintient le système d'exploitation Linux à jour avec les derniers correctifs de sécurité (Debian, Ubuntu, Raspberry Pi OS, Alpine).",
        hostOsLabel: "Système d'exploitation",
        hostKernelLabel: "Version du noyau",
        hostUptimeLabel: "Temps d'activité",
        hostStatusLabel: "Statut",
        hostOnline: "En ligne",
        hostRebootReq: "Redémarrage requis",
        updateHostBtn: "Mettre à jour le système hôte",
        cfgGeneralTitle: "Paramètres Généraux",
        cfgGeneralDesc: "Planification automatique et règles d'exécution",
        cfgCronLabel: "Planification Cron",
        cfgCronHelp: "Format cron standard à 5 champs (ex: 0 4 * * * = 4h00 tous les jours)",
        cfgLogLevelLabel: "Niveau de journalisation",
        cfgRunOnStart: "Exécuter une vérification dès le démarrage du conteneur",
        cfgDryRun: "Mode Simulation (vérifie sans appliquer les mises à jour)",
        cfgDockerTitle: "Mises à jour des Conteneurs Docker",
        cfgDockerDesc: "Comportement de téléchargement, recréation et nettoyage",
        cfgDockerEnabled: "Activer les mises à jour automatiques des conteneurs",
        cfgDockerCleanup: "Supprimer automatiquement les anciennes images après mise à jour",
        cfgDockerMonitor: "Mode Surveillance uniquement (détecte sans recréer)",
        cfgStopTimeout: "Délai d'arrêt gracieux (secondes)",
        cfgHealthTimeout: "Délai de vérification d'état de santé (secondes)",
        cfgHostSysTitle: "Mises à jour du Système Hôte",
        cfgHostSysDesc: "Mise à niveau des paquets du système hôte et redémarrage automatique",
        cfgSysEnabled: "Activer les mises à jour de paquets de la machine hôte (apt/apk)",
        cfgSysReboot: "Redémarrer automatiquement la machine si requis par les paquets mis à jour",
        btnSaveConfig: "Enregistrer la configuration",
        notifDiscordDesc: "Envoyer les alertes directement dans un salon Discord",
        notifSlackDesc: "Envoyer les alertes formatées dans une chaîne Slack",
        notifTelegramDesc: "Alertes instantanées dans un chat privé ou un canal Telegram",
        notifWebhookTitle: "Webhook Générique",
        notifWebhookDesc: "Payload JSON envoyé via HTTP POST (Home Assistant, n8n, etc.)",
        btnTestMsg: "Envoyer un message test",
        btnSaveNotif: "Enregistrer les notifications",
        logSourceEngine: "Logs du Moteur (systower.log)",
        logSourceUi: "Logs Web UI (systower-ui.log)",
        logAutoScroll: "Défilement auto",
        logClear: "Effacer la vue",
        modalClose: "Fermer",
        tabTitles: {
            containers: { title: "Conteneurs Docker", subtitle: "Surveillez et mettez à jour les conteneurs de ce serveur" },
            system: { title: "Système Hôte", subtitle: "Gestion des mises à jour du système d'exploitation de la machine locale" },
            settings: { title: "Configuration", subtitle: "Planification automatique, filtres et règles de mise à jour" },
            notifications: { title: "Notifications", subtitle: "Recevez des alertes lors des mises à jour de conteneurs ou du système" },
            logs: { title: "Logs en direct", subtitle: "Flux en temps réel du moteur Systower et du serveur web" }
        },
        toastTriggering: "Lancement du cycle de mise à jour complet...",
        toastSuccess: "Cycle de mise à jour terminé avec succès !",
        toastError: "Erreur lors du cycle de mise à jour",
        toastUpdatingCont: (name) => `Mise à jour du conteneur '${name}' en cours...`,
        toastContSuccess: (name) => `Conteneur '${name}' mis à jour avec succès !`,
        toastContFailed: (name, err) => `Échec de la mise à jour pour '${name}': ${err}`,
        toastHostUpdating: "Mise à jour des paquets du système hôte en cours...",
        toastHostSuccess: "Mise à jour du système hôte terminée avec succès !",
        toastHostFailed: (err) => `Échec de la mise à jour hôte: ${err}`,
        updateBtn: "Mettre à jour",
        excludeBtn: "Exclure",
        includeBtn: "Inclure",
        excludedTag: "Exclu"
    },
    en: {
        navContainers: "Containers",
        navHostSystem: "Host System",
        navConfig: "Configuration",
        navNotif: "Notifications",
        navLogs: "Live Logs",
        daemonActive: "Daemon Active",
        runUpdatesNow: "Run Updates Now",
        searchPlaceholder: "Search by name, image, or stack...",
        filterAll: "All",
        filterActive: "Active",
        filterExcluded: "Excluded",
        filterCompose: "Compose Stacks",
        loadingContainers: "Loading containers...",
        noContainers: "No containers match the current filter.",
        hostTitle: "Host Machine",
        hostDesc: "Keep the underlying Linux system up to date with the latest packages (Debian, Ubuntu, Raspberry Pi OS, Alpine).",
        hostOsLabel: "Operating System",
        hostKernelLabel: "Kernel Version",
        hostUptimeLabel: "Host Uptime",
        hostStatusLabel: "Status",
        hostOnline: "Online",
        hostRebootReq: "Reboot Required",
        updateHostBtn: "Update Host System Now",
        cfgGeneralTitle: "General Settings",
        cfgGeneralDesc: "Scheduler and execution policies",
        cfgCronLabel: "Cron Schedule",
        cfgCronHelp: "Standard 5-part cron syntax (e.g. 0 4 * * * = 4:00 AM daily)",
        cfgLogLevelLabel: "Log Level",
        cfgRunOnStart: "Run updates immediately on container startup",
        cfgDryRun: "Dry Run Mode (Simulate without applying updates)",
        cfgDockerTitle: "Docker Engine Settings",
        cfgDockerDesc: "Container update behaviors, health checks, and cleanup",
        cfgDockerEnabled: "Enable Docker Container Updates",
        cfgDockerCleanup: "Automatically remove old images after successful update",
        cfgDockerMonitor: "Monitor Only (Detect updates but do not recreate containers)",
        cfgStopTimeout: "Stop Timeout (Seconds)",
        cfgHealthTimeout: "Health Check Timeout (Seconds)",
        cfgHostSysTitle: "Host System Updates",
        cfgHostSysDesc: "Host OS package upgrades and automated reboots",
        cfgSysEnabled: "Enable package updates for host OS (apt/apk)",
        cfgSysReboot: "Auto-reboot host if required by packages after update",
        btnSaveConfig: "Save Configuration",
        notifDiscordDesc: "Post update notifications directly into a Discord channel",
        notifSlackDesc: "Send structured update summaries to a Slack workspace channel",
        notifTelegramDesc: "Instant alerts sent to your Telegram private chat or channel",
        notifWebhookTitle: "Generic Webhook",
        notifWebhookDesc: "HTTP POST JSON payload to custom automation endpoints (Home Assistant, n8n, etc.)",
        btnTestMsg: "Send Test Message",
        btnSaveNotif: "Save Notification Settings",
        logSourceEngine: "Engine Logs (systower.log)",
        logSourceUi: "Web UI Logs (systower-ui.log)",
        logAutoScroll: "Auto Scroll",
        logClear: "Clear View",
        modalClose: "Close",
        tabTitles: {
            containers: { title: "Docker Containers", subtitle: "Monitor and update containers running on this Docker engine" },
            system: { title: "Host System", subtitle: "Manage updates for the local host operating system" },
            settings: { title: "Configuration", subtitle: "Configure automated scheduling, Docker filters, and update policies" },
            notifications: { title: "Notifications", subtitle: "Receive alerts when container or system updates occur" },
            logs: { title: "Live Logs", subtitle: "Real-time engine and web service logs" }
        },
        toastTriggering: "Triggering full Systower update cycle...",
        toastSuccess: "Update cycle completed successfully!",
        toastError: "Update cycle finished with errors",
        toastUpdatingCont: (name) => `Starting update for container '${name}'...`,
        toastContSuccess: (name) => `Container '${name}' updated successfully!`,
        toastContFailed: (name, err) => `Update failed for '${name}': ${err}`,
        toastHostUpdating: "Starting system package update on host machine...",
        toastHostSuccess: "Host system update finished successfully!",
        toastHostFailed: (err) => `Host update error: ${err}`,
        updateBtn: "Update",
        excludeBtn: "Exclude",
        includeBtn: "Include",
        excludedTag: "Excluded"
    }
};

// Initialize on DOM ready
document.addEventListener('DOMContentLoaded', () => {
    initNavigation();
    initUserProfile();
    applyLanguage(currentLang);
    loadContainers();
    loadHostSystem();
    loadConfig();
    initLogStream();
    initTopActions();
});

// Language Switcher
function switchLanguage(lang) {
    currentLang = lang;
    localStorage.setItem('systower_lang', lang);
    applyLanguage(lang);
    renderContainers(document.getElementById('container-search')?.value || '');
}

function applyLanguage(lang) {
    const t = i18n[lang] || i18n.en;

    // Highlight active language button
    document.querySelectorAll('.lang-btn').forEach(btn => {
        const isActive = btn.dataset.lang === lang;
        btn.classList.toggle('active', isActive);
        btn.style.background = isActive ? 'var(--accent-primary)' : 'transparent';
        btn.style.color = isActive ? '#fff' : 'var(--text-muted)';
    });

    // Translate all elements with data-i18n attribute
    document.querySelectorAll('[data-i18n]').forEach(el => {
        const key = el.dataset.i18n;
        if (t[key]) {
            el.textContent = t[key];
        }
    });

    // Search placeholder
    const searchInput = document.getElementById('container-search');
    if (searchInput) searchInput.placeholder = t.searchPlaceholder;

    // Update Tab Titles
    const curTitle = t.tabTitles[currentTab];
    if (curTitle) {
        document.getElementById('page-title').textContent = curTitle.title;
        document.getElementById('page-subtitle').textContent = curTitle.subtitle;
    }
}

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

// User Profile
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
    const t = i18n[currentLang] || i18n.en;
    const curTitle = t.tabTitles[tabId];
    if (curTitle) {
        document.getElementById('page-title').textContent = curTitle.title;
        document.getElementById('page-subtitle').textContent = curTitle.subtitle;
    }

    // Refresh active tab data
    if (tabId === 'containers') loadContainers();
    if (tabId === 'system') loadHostSystem();
    if (tabId === 'settings') loadConfig();
}

// Topbar Actions
function initTopActions() {
    const triggerBtn = document.getElementById('btn-trigger-all');
    const t = () => i18n[currentLang] || i18n.en;

    triggerBtn.addEventListener('click', async () => {
        triggerBtn.disabled = true;
        triggerBtn.classList.add('loading');
        showToast(t().toastTriggering, 'info');

        try {
            const res = await safeFetch('/api/config/trigger-run', { method: 'POST' });
            const data = await res.json();
            if (data.success) {
                showToast(t().toastSuccess, 'success');
                loadContainers();
                loadHostSystem();
            } else {
                showToast(`${t().toastError}: ${data.error || 'Check logs'}`, 'error');
            }
        } catch (err) {
            showToast(`Error: ${err.message}`, 'error');
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
        showToast(t().toastHostUpdating, 'info');
        try {
            const res = await safeFetch('/api/system/update', { method: 'POST' });
            const data = await res.json();
            if (data.success) {
                showToast(t().toastHostSuccess, 'success');
                loadHostSystem();
            } else {
                showToast(t().toastHostFailed(data.error), 'error');
            }
        } catch (e) {
            showToast(t().toastHostFailed(e.message), 'error');
        }
    });
}

// ============================================================================
// 1. CONTAINERS
// ============================================================================

async function loadContainers() {
    const listEl = document.getElementById('containers-list');
    const t = i18n[currentLang] || i18n.en;

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
    const t = i18n[currentLang] || i18n.en;

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
        listEl.innerHTML = `<div class="empty-state">${t.noContainers}</div>`;
        return;
    }

    listEl.innerHTML = filtered.map(c => {
        const healthClass = c.health === 'healthy' || c.health === 'running' ? 'healthy' : (c.health === 'unhealthy' ? 'unhealthy' : 'starting');
        const excludeBtnText = c.isExcluded ? t.includeBtn : t.excludeBtn;

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
                    ${c.isExcluded ? `<span class="tag excluded-tag">🚫 ${t.excludedTag} (${c.excludeReason})</span>` : ''}
                </div>

                <div class="card-actions">
                    <button class="btn btn-primary btn-sm" onclick="updateContainer('${c.id}', '${c.name}')">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                            <polyline points="23 4 23 10 17 10"></polyline>
                            <path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"></path>
                        </svg>
                        <span>${t.updateBtn}</span>
                    </button>
                    <button class="btn btn-secondary btn-sm" onclick="toggleContainerExclude('${c.name}')">
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
    const t = i18n[currentLang] || i18n.en;
    showToast(t.toastUpdatingCont(name), 'info');
    try {
        const res = await safeFetch(`/api/containers/${id}/update`, { method: 'POST' });
        const data = await res.json();
        if (data.success) {
            showToast(t.toastContSuccess(name), 'success');
            loadContainers();
        } else {
            showToast(t.toastContFailed(name, data.error), 'error');
        }
    } catch (err) {
        showToast(t.toastContFailed(name, err.message), 'error');
    }
}

async function toggleContainerExclude(name) {
    try {
        const res = await safeFetch(`/api/containers/${encodeURIComponent(name)}/toggle-exclude`, { method: 'POST' });
        const data = await res.json();
        if (data.success) {
            showToast(`Container '${name}' ${data.isExcluded ? 'excluded' : 'included'}`, 'info');
            loadContainers();
        }
    } catch (err) {
        showToast(`Error: ${err.message}`, 'error');
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
    const t = i18n[currentLang] || i18n.en;
    try {
        const res = await safeFetch('/api/system/status');
        const data = await res.json();
        if (data.success && data.host) {
            document.getElementById('host-os-name').textContent = data.host.os;
            document.getElementById('host-kernel').textContent = data.host.kernel;
            document.getElementById('host-uptime').textContent = data.host.uptime;
            const badge = document.getElementById('host-status-badge');
            if (data.host.rebootRequired) {
                badge.innerHTML = `<span class="status-badge starting">${t.hostRebootReq}</span>`;
            } else {
                badge.innerHTML = `<span class="status-badge healthy">${t.hostOnline}</span>`;
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
