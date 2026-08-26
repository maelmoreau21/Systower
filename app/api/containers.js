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

// Get all containers with detailed metadata
router.get('/', async (req, res) => {
    try {
        const psOutput = await execCommand('docker ps -a --no-trunc --format "{{.ID}}"');
        const containerIds = psOutput.split('\n').map(s => s.trim()).filter(Boolean);

        if (containerIds.length === 0) {
            return res.json({ containers: [] });
        }

        const inspectRaw = await execCommand(`docker inspect ${containerIds.join(' ')}`);
        const inspectList = JSON.parse(inspectRaw);

        // Read current config to check exclude lists
        let excludeList = [];
        let includeOnlyList = [];
        if (fs.existsSync(CONFIG_FILE)) {
            try {
                const cfg = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
                excludeList = cfg.docker?.exclude || [];
                includeOnlyList = cfg.docker?.includeOnly || [];
            } catch (e) {}
        }

        const containers = inspectList.map(c => {
            const name = (c.Name || '').replace(/^\//, '');
            const labels = c.Config?.Labels || {};
            const isExcludedByLabel = labels['systower.exclude'] === 'true';
            const isExcludedByList = excludeList.includes(name);
            const isIncludedOnly = includeOnlyList.length === 0 || includeOnlyList.includes(name);
            const isExcluded = isExcludedByLabel || isExcludedByList || !isIncludedOnly;

            const isCompose = !!labels['com.docker.compose.project'];
            const composeProject = labels['com.docker.compose.project'] || null;
            const composeService = labels['com.docker.compose.service'] || null;

            const health = c.State?.Health?.Status || (c.State?.Running ? 'running' : c.State?.Status || 'stopped');

            return {
                id: c.Id,
                shortId: c.Id.substring(0, 12),
                name,
                image: c.Config?.Image,
                imageId: c.Image,
                state: c.State?.Status,
                running: c.State?.Running,
                health,
                status: c.State?.Status,
                created: c.Created,
                isCompose,
                composeProject,
                composeService,
                customSchedule: labels['systower.schedule'] || null,
                stopTimeout: labels['systower.stop-timeout'] || null,
                isExcluded,
                excludeReason: isExcludedByLabel ? 'label' : (isExcludedByList ? 'config_exclude' : (!isIncludedOnly ? 'not_in_include_only' : null)),
                ports: c.HostConfig?.PortBindings || {},
                labels
            };
        });

        res.json({ containers });
    } catch (err) {
        console.error('Error fetching containers:', err);
        res.status(500).json({ error: 'Failed to fetch containers', details: err.message });
    }
});

// Check update status for a single container
router.get('/:id/check-update', async (req, res) => {
    const { id } = req.params;
    try {
        const inspectRaw = await execCommand(`docker inspect ${id}`);
        const inspect = JSON.parse(inspectRaw)[0];
        const image = inspect.Config?.Image;
        const currentImageId = inspect.Image;

        // Pull latest
        await execCommand(`docker pull ${image}`);
        const latestImageInspectRaw = await execCommand(`docker image inspect ${image}`);
        const latestImageId = JSON.parse(latestImageInspectRaw)[0]?.Id;

        const hasUpdate = currentImageId !== latestImageId;
        res.json({
            hasUpdate,
            currentImageId,
            latestImageId,
            image
        });
    } catch (err) {
        res.status(500).json({ error: 'Failed to check update for container', details: err.message });
    }
});

// Update specific container
router.post('/:id/update', async (req, res) => {
    const { id } = req.params;
    try {
        const inspectRaw = await execCommand(`docker inspect ${id}`);
        const inspect = JSON.parse(inspectRaw)[0];
        const name = (inspect.Name || '').replace(/^\//, '');

        // Call docker update logic by running systower in targeted mode or direct script
        const cmd = `SYSTOWER_DOCKER_INCLUDE_ONLY="${name}" SYSTOWER_RUN_ON_START="true" SYSTOWER_SYSTEM_ENABLED="false" /scripts/systower.sh`;
        const output = await execCommand(cmd);

        res.json({ success: true, message: `Update triggered for container ${name}`, output });
    } catch (err) {
        console.error('Error updating container:', err);
        res.status(500).json({ error: 'Failed to update container', details: err.message });
    }
});

// Toggle container exclusion in config
router.post('/:name/toggle-exclude', (req, res) => {
    const { name } = req.params;
    try {
        let cfg = { docker: { exclude: [] } };
        if (fs.existsSync(CONFIG_FILE)) {
            cfg = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
        }
        if (!cfg.docker) cfg.docker = {};
        if (!cfg.docker.exclude) cfg.docker.exclude = [];

        const index = cfg.docker.exclude.indexOf(name);
        let excluded = false;
        if (index >= 0) {
            cfg.docker.exclude.splice(index, 1);
            excluded = false;
        } else {
            cfg.docker.exclude.push(name);
            excluded = true;
        }

        fs.writeFileSync(CONFIG_FILE, JSON.stringify(cfg, null, 2), 'utf8');
        res.json({ success: true, name, isExcluded: excluded, excludeList: cfg.docker.exclude });
    } catch (err) {
        res.status(500).json({ error: 'Failed to toggle exclusion', details: err.message });
    }
});

// Inspect container
router.get('/:id/inspect', async (req, res) => {
    const { id } = req.params;
    try {
        const inspectRaw = await execCommand(`docker inspect ${id}`);
        res.json(JSON.parse(inspectRaw)[0]);
    } catch (err) {
        res.status(500).json({ error: 'Failed to inspect container', details: err.message });
    }
});

module.exports = router;
