const express = require('express');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');

const router = express.Router();
const CONFIG_FILE = process.env.SYSTOWER_CONFIG_FILE || '/config/systower.json';

function getDefaultConfig() {
    return {
        general: {
            cron: process.env.SYSTOWER_CRON || "0 4 * * *",
            runOnStart: process.env.SYSTOWER_RUN_ON_START === "true",
            logLevel: process.env.SYSTOWER_LOG_LEVEL || "info",
            dryRun: process.env.SYSTOWER_DRY_RUN === "true"
        },
        docker: {
            enabled: process.env.SYSTOWER_DOCKER_ENABLED !== "false",
            exclude: process.env.SYSTOWER_DOCKER_EXCLUDE ? process.env.SYSTOWER_DOCKER_EXCLUDE.split(',').map(s => s.trim()).filter(Boolean) : [],
            includeOnly: process.env.SYSTOWER_DOCKER_INCLUDE_ONLY ? process.env.SYSTOWER_DOCKER_INCLUDE_ONLY.split(',').map(s => s.trim()).filter(Boolean) : [],
            cleanup: process.env.SYSTOWER_DOCKER_CLEANUP !== "false",
            stopTimeout: parseInt(process.env.SYSTOWER_DOCKER_STOP_TIMEOUT || "30", 10),
            monitorOnly: process.env.SYSTOWER_DOCKER_MONITOR_ONLY === "true",
            healthcheckTimeout: parseInt(process.env.SYSTOWER_DOCKER_HEALTHCHECK_TIMEOUT || "30", 10),
            composeAware: process.env.SYSTOWER_DOCKER_COMPOSE_AWARE !== "false"
        },
        system: {
            enabled: process.env.SYSTOWER_SYSTEM_ENABLED === "true",
            hosts: process.env.SYSTOWER_SYSTEM_HOSTS ? process.env.SYSTOWER_SYSTEM_HOSTS.split(',').map(s => s.trim()).filter(Boolean) : [],
            sshKeyPath: process.env.SYSTOWER_SYSTEM_SSH_KEY || "/config/ssh/id_rsa",
            reboot: process.env.SYSTOWER_SYSTEM_REBOOT === "true"
        },
        notifications: {
            enabled: process.env.SYSTOWER_NOTIFY_ENABLED === "true",
            discord: { enabled: !!process.env.SYSTOWER_NOTIFY_DISCORD, webhookUrl: process.env.SYSTOWER_NOTIFY_DISCORD || "" },
            slack: { enabled: !!process.env.SYSTOWER_NOTIFY_SLACK, webhookUrl: process.env.SYSTOWER_NOTIFY_SLACK || "" },
            telegram: { enabled: !!process.env.SYSTOWER_NOTIFY_TELEGRAM_TOKEN, botToken: process.env.SYSTOWER_NOTIFY_TELEGRAM_TOKEN || "", chatId: process.env.SYSTOWER_NOTIFY_TELEGRAM_CHAT || "" },
            webhook: { enabled: !!process.env.SYSTOWER_NOTIFY_WEBHOOK, url: process.env.SYSTOWER_NOTIFY_WEBHOOK || "" }
        },
        ui: {
            enabled: process.env.SYSTOWER_UI_ENABLED !== "false",
            port: parseInt(process.env.SYSTOWER_UI_PORT || "8080", 10)
        }
    };
}

// Read current config
router.get('/', (req, res) => {
    try {
        if (fs.existsSync(CONFIG_FILE)) {
            const raw = fs.readFileSync(CONFIG_FILE, 'utf8');
            return res.json(JSON.parse(raw));
        }
        return res.json(getDefaultConfig());
    } catch (err) {
        console.error('Error reading config file:', err);
        return res.status(500).json({ error: 'Failed to read configuration', details: err.message });
    }
});

// Update config
router.put('/', (req, res) => {
    try {
        const newConfig = req.body;
        const dir = path.dirname(CONFIG_FILE);
        if (!fs.existsSync(dir)) {
            fs.mkdirSync(dir, { recursive: true });
        }
        fs.writeFileSync(CONFIG_FILE, JSON.stringify(newConfig, null, 2), 'utf8');
        return res.json({ success: true, message: 'Configuration saved successfully', config: newConfig });
    } catch (err) {
        console.error('Error saving config file:', err);
        return res.status(500).json({ error: 'Failed to save configuration', details: err.message });
    }
});

// Trigger full Systower manual run
router.post('/trigger-run', (req, res) => {
    exec('/scripts/systower.sh', (err, stdout, stderr) => {
        if (err) {
            console.error('Manual run error:', err, stderr);
            return res.status(500).json({ success: false, error: stderr || err.message, output: stdout });
        }
        return res.json({ success: true, output: stdout });
    });
});

module.exports = router;
