const express = require('express');
const { exec } = require('child_process');
const fs = require('fs');

const router = express.Router();

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

// Get host system status and OS details
router.get('/status', async (req, res) => {
    try {
        let osName = 'Linux';
        let kernel = 'Unknown';
        let uptime = 'Unknown';
        let rebootRequired = false;

        // Detect OS
        try {
            const rawOs = await execCommand("bash -c 'source /scripts/system-update.sh && detect_host_os'");
            if (rawOs) osName = rawOs;
        } catch (e) {
            if (fs.existsSync('/etc/os-release')) {
                const data = fs.readFileSync('/etc/os-release', 'utf8');
                const match = data.match(/PRETTY_NAME="?([^"\n]+)"?/);
                if (match) osName = match[1];
            }
        }

        // Detect Kernel & Uptime
        try {
            kernel = await execCommand("bash -c 'source /scripts/system-update.sh && host_exec \"uname -r\"'");
            uptime = await execCommand("bash -c 'source /scripts/system-update.sh && host_exec \"uptime -p\" 2>/dev/null || uptime'");
            const rebootCheck = await execCommand("bash -c 'source /scripts/system-update.sh && host_exec \"[ -f /var/run/reboot-required ] && echo yes || echo no\"'");
            rebootRequired = rebootCheck === 'yes';
        } catch (e) {}

        res.json({
            success: true,
            host: {
                os: osName,
                kernel,
                uptime,
                rebootRequired,
                systemUpdatesEnabled: process.env.SYSTOWER_SYSTEM_ENABLED === 'true'
            }
        });
    } catch (err) {
        res.status(500).json({ success: false, error: err.message });
    }
});

// Trigger host system update
router.post('/update', async (req, res) => {
    const cmd = `SYSTOWER_SYSTEM_ENABLED=true SYSTOWER_DOCKER_ENABLED=false /scripts/systower.sh`;

    try {
        const output = await execCommand(cmd);
        res.json({ success: true, output });
    } catch (err) {
        res.status(500).json({ success: false, error: err.message });
    }
});

module.exports = router;
