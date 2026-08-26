const express = require('express');
const { exec } = require('child_process');

const router = express.Router();

function execCommand(cmd) {
    return new Promise((resolve, reject) => {
        exec(cmd, { maxBuffer: 1024 * 1024 * 5 }, (error, stdout, stderr) => {
            if (error) {
                return reject(new Error(stderr || error.message));
            }
            resolve(stdout.trim());
        });
    });
}

// Test notification channel
router.post('/test', async (req, res) => {
    const { type, webhookUrl, botToken, chatId } = req.body;
    // type: discord, slack, telegram, webhook

    let envVars = 'SYSTOWER_NOTIFY_ENABLED=true ';
    if (type === 'discord') {
        envVars += `SYSTOWER_NOTIFY_DISCORD="${webhookUrl}" `;
    } else if (type === 'slack') {
        envVars += `SYSTOWER_NOTIFY_SLACK="${webhookUrl}" `;
    } else if (type === 'telegram') {
        envVars += `SYSTOWER_NOTIFY_TELEGRAM_TOKEN="${botToken}" SYSTOWER_NOTIFY_TELEGRAM_CHAT="${chatId}" `;
    } else if (type === 'webhook') {
        envVars += `SYSTOWER_NOTIFY_WEBHOOK="${webhookUrl}" `;
    } else {
        return res.status(400).json({ error: 'Unsupported notification type' });
    }

    const testCmd = `${envVars} bash -c 'source /scripts/notifications.sh && notify "Test Notification" "This is a test notification from Systower Web UI." "info"'`;

    try {
        await execCommand(testCmd);
        res.json({ success: true, message: `Test notification sent to ${type}` });
    } catch (err) {
        res.status(500).json({ success: false, error: err.message });
    }
});

module.exports = router;
