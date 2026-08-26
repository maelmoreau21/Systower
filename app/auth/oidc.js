const { Issuer, generators } = require('openid-client');

let oidcClient = null;

const getAuthCredentials = () => {
    const user = process.env.SYSTOWER_AUTH_USERNAME || process.env.SYSTOWER_USERNAME || process.env.USERNAME || '';
    const pass = process.env.SYSTOWER_AUTH_PASSWORD || process.env.SYSTOWER_PASSWORD || process.env.PASSWORD || '';
    return { user: user.trim(), pass: pass.trim() };
};

const isOidcEnabled = () => {
    return process.env.SYSTOWER_OIDC_ENABLED === 'true';
};

const isBasicAuthEnabled = () => {
    const { user, pass } = getAuthCredentials();
    return Boolean(user && pass);
};

const isAuthRequired = () => {
    return isOidcEnabled() || isBasicAuthEnabled();
};

async function initOidc() {
    if (!isOidcEnabled()) {
        if (isBasicAuthEnabled()) {
            const { user } = getAuthCredentials();
            console.log(`[Auth] Password authentication enabled for user: ${user}`);
        } else {
            console.log('[Auth] No authentication configured. Running in open access mode.');
        }
        return;
    }

    const issuerUrl = process.env.SYSTOWER_OIDC_ISSUER;
    const clientId = process.env.SYSTOWER_OIDC_CLIENT_ID;
    const clientSecret = process.env.SYSTOWER_OIDC_CLIENT_SECRET;

    if (!issuerUrl || !clientId) {
        console.error('[Auth] OIDC is enabled but SYSTOWER_OIDC_ISSUER or SYSTOWER_OIDC_CLIENT_ID is missing.');
        return;
    }

    try {
        console.log(`[Auth] Discovering OIDC provider at ${issuerUrl}...`);
        const issuer = await Issuer.discover(issuerUrl);
        console.log(`[Auth] Discovered issuer: ${issuer.metadata.issuer}`);

        oidcClient = new issuer.Client({
            client_id: clientId,
            client_secret: clientSecret,
            response_types: ['code'],
        });

        console.log('[Auth] OIDC client initialized successfully.');
    } catch (err) {
        console.error('[Auth] Failed to initialize OIDC client:', err.message);
    }
}

function getRedirectUri(req) {
    if (process.env.SYSTOWER_OIDC_REDIRECT_URI) {
        return process.env.SYSTOWER_OIDC_REDIRECT_URI;
    }
    const host = req.get('host');
    const proto = req.headers['x-forwarded-proto'] || req.protocol;
    return `${proto}://${host}/auth/callback`;
}

function requireAuth(req, res, next) {
    // If no auth is configured, grant admin access
    if (!isAuthRequired()) {
        req.user = { name: 'Admin', email: 'admin@local', sub: 'local-admin' };
        return next();
    }

    // Check HTTP Basic Auth header (useful for API and automation)
    const authHeader = req.headers['authorization'];
    if (authHeader && authHeader.startsWith('Basic ') && isBasicAuthEnabled()) {
        const { user: expectedUser, pass: expectedPass } = getAuthCredentials();
        const base64Credentials = authHeader.split(' ')[1];
        const credentials = Buffer.from(base64Credentials, 'base64').toString('utf8');
        const [username, password] = credentials.split(':');

        if (username === expectedUser && password === expectedPass) {
            req.user = { name: username, sub: username, isBasic: true };
            return next();
        }
    }

    // Check Session User
    if (req.session && req.session.user) {
        req.user = req.session.user;
        return next();
    }

    // Unauthenticated API request -> return JSON 401
    if (req.path.startsWith('/api/')) {
        const loginUrl = isOidcEnabled() ? '/auth/login' : '/login.html';
        return res.status(401).json({ error: 'Unauthorized', authenticated: false, loginUrl });
    }

    // Allow public assets
    if (req.path === '/login.html' || req.path === '/auth/local-login' || req.path.startsWith('/css/') || req.path.startsWith('/js/')) {
        return next();
    }

    // Unauthenticated page request -> redirect to login
    if (isOidcEnabled()) {
        return res.redirect('/auth/login');
    } else {
        return res.redirect('/login.html');
    }
}

function setupAuthRoutes(app) {
    // OIDC Login
    app.get('/auth/login', (req, res) => {
        if (!isOidcEnabled()) {
            if (isBasicAuthEnabled()) {
                return res.redirect('/login.html');
            }
            return res.redirect('/');
        }

        if (!oidcClient) {
            return res.status(500).send('OIDC client is not initialized. Please check server logs.');
        }

        const code_verifier = generators.codeVerifier();
        const code_challenge = generators.codeChallenge(code_verifier);
        const state = generators.state();
        const nonce = generators.nonce();

        req.session.code_verifier = code_verifier;
        req.session.state = state;
        req.session.nonce = nonce;

        const redirectUri = getRedirectUri(req);
        const authorizationUrl = oidcClient.authorizationUrl({
            scope: process.env.SYSTOWER_OIDC_SCOPES || 'openid email profile',
            redirect_uri: redirectUri,
            code_challenge,
            code_challenge_method: 'S256',
            state,
            nonce,
        });

        res.redirect(authorizationUrl);
    });

    // OIDC Callback
    app.get('/auth/callback', async (req, res) => {
        if (!isOidcEnabled()) {
            return res.redirect('/');
        }

        if (!oidcClient) {
            return res.status(500).send('OIDC client is not initialized.');
        }

        try {
            const redirectUri = getRedirectUri(req);
            const params = oidcClient.callbackParams(req);
            const tokenSet = await oidcClient.callback(redirectUri, params, {
                code_verifier: req.session.code_verifier,
                state: req.session.state,
                nonce: req.session.nonce,
            });

            const claims = tokenSet.claims();
            req.session.user = {
                sub: claims.sub,
                name: claims.name || claims.preferred_username || claims.email || 'User',
                email: claims.email || '',
                picture: claims.picture || null,
            };

            delete req.session.code_verifier;
            delete req.session.state;
            delete req.session.nonce;

            res.redirect('/');
        } catch (err) {
            console.error('[Auth] Callback error:', err);
            res.status(500).send(`Authentication failed: ${err.message}`);
        }
    });

    // Username / Password Local Login
    app.post('/auth/local-login', (req, res) => {
        if (!isBasicAuthEnabled()) {
            return res.json({ success: true, redirect: '/' });
        }

        const { username, password } = req.body;
        const { user: expectedUser, pass: expectedPass } = getAuthCredentials();

        if (username === expectedUser && password === expectedPass) {
            req.session.user = {
                sub: username,
                name: username,
                email: `${username}@local`,
                isLocal: true
            };
            return res.json({ success: true, redirect: '/' });
        }

        return res.status(401).json({ success: false, error: 'Invalid username or password' });
    });

    // Logout
    app.get('/auth/logout', (req, res) => {
        req.session = null;
        res.redirect(isBasicAuthEnabled() ? '/login.html' : '/');
    });

    // Current user info endpoint
    app.get('/auth/user', (req, res) => {
        const oidc = isOidcEnabled();
        const basic = isBasicAuthEnabled();

        if (!isAuthRequired()) {
            return res.json({
                authRequired: false,
                oidcEnabled: false,
                basicAuthEnabled: false,
                authenticated: true,
                user: { name: 'Admin', email: 'admin@local' },
            });
        }

        if (req.session && req.session.user) {
            return res.json({
                authRequired: true,
                oidcEnabled: oidc,
                basicAuthEnabled: basic,
                authenticated: true,
                user: req.session.user,
            });
        }

        return res.json({
            authRequired: true,
            oidcEnabled: oidc,
            basicAuthEnabled: basic,
            authenticated: false,
            user: null,
        });
    });
}

module.exports = {
    initOidc,
    requireAuth,
    setupAuthRoutes,
    isOidcEnabled,
    isBasicAuthEnabled,
    isAuthRequired,
};
