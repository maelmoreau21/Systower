const express = require('express');
const fs = require('fs');

const router = express.Router();
const LOG_FILE = '/var/log/systower.log';
const UI_LOG_FILE = '/var/log/systower-ui.log';

// Get recent log lines
router.get('/', (req, res) => {
    const linesCount = parseInt(req.query.lines || '200', 10);
    const source = req.query.source || 'systower';
    const targetFile = source === 'ui' ? UI_LOG_FILE : LOG_FILE;

    try {
        if (!fs.existsSync(targetFile)) {
            return res.json({ logs: '', lines: 0, file: targetFile });
        }

        const data = fs.readFileSync(targetFile, 'utf8');
        const allLines = data.split('\n');
        const recentLines = allLines.slice(-linesCount).join('\n');

        res.json({
            logs: recentLines,
            totalLines: allLines.length,
            file: targetFile
        });
    } catch (err) {
        res.status(500).json({ error: 'Failed to read logs', details: err.message });
    }
});

// Clear log file
router.post('/clear', (req, res) => {
    const source = req.query.source || 'systower';
    const targetFile = source === 'ui' ? UI_LOG_FILE : LOG_FILE;

    try {
        if (fs.existsSync(targetFile)) {
            fs.writeFileSync(targetFile, '', 'utf8');
        }
        res.json({ success: true, message: `Cleared ${targetFile}` });
    } catch (err) {
        res.status(500).json({ error: 'Failed to clear logs', details: err.message });
    }
});

module.exports = router;
