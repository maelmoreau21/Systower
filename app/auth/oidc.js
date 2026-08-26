const { Issuer, generators } = require('openid-client');

let oidcClient = null;
let isInitialized = false;

const isOidcEnabled = () => {
    return process.env.SYSTOWER_OIDC_ENABLED === 'true';
};

async function initOidc() {
    if (!isOidcEnabled()) {
        console.log('[Auth] OIDC SSO is disabled. Running in open access mode.');
        isInitialized = true;
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

        isInitialized = true;
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
    if (!isOidcEnabled()) {
        req.user = { name: 'Admin', email: 'admin@local', sub: 'local-admin' };
        return next();
    }

    if (req.session && req.session.user) {
        req.user = req.session.user;
        return next();
    }

    // Unauthenticated request
    if (req.path.startsWith('/api/')) {
        return res.status(401).json({ error: 'Unauthorized', loginUrl: '/auth/login' });
    }

    return res.redirect('/auth/login');
}

function setupAuthRoutes(app) {
    app.get('/auth/login', (req, res) => {
        if (!isOidcEnabled()) {
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

            // Clean up temporary auth session data
            delete req.session.code_verifier;
            delete req.session.state;
            delete req.session.nonce;

            res.redirect('/');
        } catch (err) {
            console.error('[Auth] Callback error:', err);
            res.status(500).send(`Authentication failed: ${err.message}`);
        }
    });

    app.get('/auth/logout', (req, res) => {
        req.session = null;
        res.redirect('/');
    });

    app.get('/auth/user', (req, res) => {
        if (!isOidcEnabled()) {
            return res.json({
                oidcEnabled: false,
                authenticated: true,
                user: { name: 'Admin', email: 'admin@local' },
            });
        }

        if (req.session && req.session.user) {
            return res.json({
                oidcEnabled: true,
                authenticated: true,
                user: req.session.user,
            });
        }

        return res.json({
            oidcEnabled: true,
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
};
