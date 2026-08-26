const express = require('express');
const http = require('http');
const path = require('path');
const fs = require('fs');
const cors = require('cors');
const cookieSession = require('cookie-session');
const WebSocket = require('ws');

const { initOidc, requireAuth, setupAuthRoutes } = require('./auth/oidc');
const configRouter = require('./api/config');
const containersRouter = require('./api/containers');
const systemRouter = require('./api/system');
const logsRouter = require('./api/logs');
const notificationsRouter = require('./api/notifications');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server, path: '/ws/logs' });

const PORT = parseInt(process.env.SYSTOWER_UI_PORT || '8080', 10);

// Basic middleware
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Session for OIDC and UI state
app.use(cookieSession({
    name: 'systower_session',
    keys: [process.env.SYSTOWER_SESSION_SECRET || 'systower-secret-key-change-in-production-12345'],
    maxAge: 24 * 60 * 60 * 1000, // 24 hours
    sameSite: 'lax',
    secure: process.env.NODE_ENV === 'production' && process.env.SYSTOWER_HTTPS === 'true'
}));

// Public routes & assets (accessible before login)
app.get('/login.html', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'login.html'));
});
app.use('/css', express.static(path.join(__dirname, 'public', 'css')));
app.use('/js', express.static(path.join(__dirname, 'public', 'js')));

// Authentication endpoints
setupAuthRoutes(app);

// Protect API routes
app.use('/api', requireAuth);

// Mount API routes
app.use('/api/config', configRouter);
app.use('/api/containers', containersRouter);
app.use('/api/system', systemRouter);
app.use('/api/logs', logsRouter);
app.use('/api/notifications', notificationsRouter);

// Protect main dashboard
app.get('/', requireAuth, (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// Protect all static assets & SPA routes
app.use(express.static(path.join(__dirname, 'public')));
app.get('*', requireAuth, (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

// WebSocket Live Logs Streaming
wss.on('connection', (ws) => {
    const logFile = '/var/log/systower.log';

    // Send recent lines immediately upon connection
    if (fs.existsSync(logFile)) {
        try {
            const data = fs.readFileSync(logFile, 'utf8');
            const initialLines = data.split('\n').slice(-50).join('\n');
            ws.send(JSON.stringify({ type: 'init', data: initialLines }));
        } catch (e) {}
    }

    // Watch log file for changes
    let watcher = null;
    if (fs.existsSync(logFile)) {
        let lastSize = fs.statSync(logFile).size;
        watcher = fs.watch(logFile, (eventType) => {
            if (eventType === 'change' && ws.readyState === WebSocket.OPEN) {
                try {
                    const stat = fs.statSync(logFile);
                    if (stat.size > lastSize) {
                        const stream = fs.createReadStream(logFile, {
                            start: lastSize,
                            end: stat.size,
                            encoding: 'utf8'
                        });
                        stream.on('data', (chunk) => {
                            ws.send(JSON.stringify({ type: 'append', data: chunk }));
                        });
                        lastSize = stat.size;
                    } else if (stat.size < lastSize) {
                        lastSize = stat.size;
                    }
                } catch (err) {}
            }
        });
    }

    ws.on('close', () => {
        if (watcher) watcher.close();
    });
});

// Start Server
async function start() {
    await initOidc();

    server.listen(PORT, '0.0.0.0', () => {
        console.log(`[Systower Web UI] Running on http://0.0.0.0:${PORT}`);
    });
}

start().catch(err => {
    console.error('Failed to start Systower Web UI:', err);
});
