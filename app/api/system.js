const express = require('express');
const { exec } = require('child_process');
const fs = require('fs');

const router = express.Router();
const CONFIG_FILE = process.env.SYSTOWER_CONFIG_FILE || '/config/systower.json';

function execCommand(cmd) {
    return new Promise((resolve, reject) => {
        exec(cmd, { maxBuffer: 1024 * 1024 * 10 }, (error, stdout, stderr) => {
            if (error) {
                return reject(new Error(stderr || error.message));
            }
            resolve(stdout.trim());
        });
    });
}

function getHostsList() {
    let hosts = [];
    if (fs.existsSync(CONFIG_FILE)) {
        try {
            const cfg = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
            if (Array.isArray(cfg.system?.hosts)) {
                hosts = cfg.system.hosts;
            }
        } catch (e) {}
    }
    // Also include env hosts if config is empty
    if (hosts.length === 0 && process.env.SYSTOWER_SYSTEM_HOSTS) {
        hosts = process.env.SYSTOWER_SYSTEM_HOSTS.split(',').map(s => s.trim()).filter(Boolean);
    }
    return hosts;
}

// Get all configured hosts
router.get('/hosts', (req, res) => {
    res.json({ hosts: getHostsList() });
});

// Add a host
router.post('/hosts', (req, res) => {
    const { host } = req.body; // e.g. "pi@192.168.1.100:22"
    if (!host || typeof host !== 'string') {
        return res.status(400).json({ error: 'Valid host string required (e.g. user@hostname:port)' });
    }

    try {
        let cfg = { system: { hosts: [] } };
        if (fs.existsSync(CONFIG_FILE)) {
            cfg = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
        }
        if (!cfg.system) cfg.system = {};
        if (!Array.isArray(cfg.system.hosts)) cfg.system.hosts = [];

        if (!cfg.system.hosts.includes(host.trim())) {
            cfg.system.hosts.push(host.trim());
        }

        fs.writeFileSync(CONFIG_FILE, JSON.stringify(cfg, null, 2), 'utf8');
        res.json({ success: true, hosts: cfg.system.hosts });
    } catch (err) {
        res.status(500).json({ error: 'Failed to add host', details: err.message });
    }
});

// Delete a host
router.delete('/hosts', (req, res) => {
    const { host } = req.body;
    try {
        let cfg = { system: { hosts: [] } };
        if (fs.existsSync(CONFIG_FILE)) {
            cfg = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
        }
        if (cfg.system?.hosts) {
            cfg.system.hosts = cfg.system.hosts.filter(h => h !== host);
        }

        fs.writeFileSync(CONFIG_FILE, JSON.stringify(cfg, null, 2), 'utf8');
        res.json({ success: true, hosts: cfg.system?.hosts || [] });
    } catch (err) {
        res.status(500).json({ error: 'Failed to delete host', details: err.message });
    }
});

// Test SSH connection to a host
router.post('/test', async (req, res) => {
    const { host } = req.body; // user@host:port
    if (!host) {
        return res.status(400).json({ error: 'Host string required' });
    }

    const sshKey = process.env.SYSTOWER_SYSTEM_SSH_KEY || '/config/ssh/id_rsa';
    
    // Parse host
    let user = 'root';
    let target = host;
    let port = '22';

    if (target.includes('@')) {
        const parts = target.split('@');
        user = parts[0];
        target = parts[1];
    }
    if (target.includes(':')) {
        const parts = target.split(':');
        target = parts[0];
        port = parts[1];
    }

    const testCmd = `ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o BatchMode=yes -i "${sshKey}" -p "${port}" "${user}@${target}" "cat /etc/os-release 2>/dev/null || uname -a"`;

    try {
        const output = await execCommand(testCmd);
        res.json({
            success: true,
            message: `Connection successful to ${host}`,
            systemInfo: output
        });
    } catch (err) {
        res.status(500).json({
            success: false,
            error: `Connection failed: ${err.message}`,
            details: err.message
        });
    }
});

// Trigger system update for all hosts or a specific host
router.post('/update', async (req, res) => {
    const { host } = req.body; // optional single host
    const envPrefix = host ? `SYSTOWER_SYSTEM_HOSTS="${host}" ` : '';
    const cmd = `${envPrefix}SYSTOWER_SYSTEM_ENABLED=true SYSTOWER_DOCKER_ENABLED=false /scripts/systower.sh`;

    try {
        const output = await execCommand(cmd);
        res.json({ success: true, output });
    } catch (err) {
        res.status(500).json({ success: false, error: err.message });
    }
});

module.exports = router;
