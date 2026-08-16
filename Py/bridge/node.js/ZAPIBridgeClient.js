// ZAPIBridgeClient.js
const http = require('http');
const https = require('https');

class ZAPIBridgeClient {
    constructor(baseUrl = 'http://127.0.0.1:8080/v1', timeout = 30) {
        this.baseUrl = baseUrl.replace(/\/+$/, '');
        this.timeout = timeout * 1000;
    }

    async invoke(app, api, args = [], timeoutMs = 5000) {
        const payload = { app, api, args, timeout: timeoutMs };
        const response = await this._httpPost('/invoke', payload);
        this._assertSuccess(response);
        return response.result;
    }

    async notify(app, api, args = []) {
        const payload = { app, api, args };
        const response = await this._httpPost('/notify', payload);
        this._assertSuccess(response);
    }

    async registerHook(app, api, callbackUrl, mode = 'call') {
        const payload = { app, api, callback_url: callbackUrl, mode };
        const response = await this._httpPost('/hooks/register', payload);
        this._assertSuccess(response);
        return response;
    }

    async unregisterHook(app, api) {
        const payload = { app, api };
        const response = await this._httpPost('/hooks/unregister', payload);
        this._assertSuccess(response);
        return response;
    }

    async listHooks() {
        const response = await this._httpGet('/hooks/list');
        this._assertSuccess(response);
        return response.hooks || [];
    }

    async health() {
        try {
            const response = await this._httpGet('/health');
            return response.status === 'ok';
        } catch {
            return false;
        }
    }

    _httpPost(endpoint, data) {
        return this._request('POST', endpoint, JSON.stringify(data), {
            'Content-Type': 'application/json'
        });
    }

    _httpGet(endpoint) {
        return this._request('GET', endpoint, null, {
            'Accept': 'application/json'
        });
    }

    _request(method, endpoint, body, headers) {
        return new Promise((resolve, reject) => {
            const fullUrl = this.baseUrl + endpoint;
            const parsed = new URL(fullUrl);
            const options = {
                hostname: parsed.hostname,
                port: parsed.port || (parsed.protocol === 'https:' ? 443 : 80),
                path: parsed.pathname + parsed.search,
                method: method,
                headers: headers || {},
                timeout: this.timeout
            };
            const client = parsed.protocol === 'https:' ? https : http;
            const req = client.request(options, (res) => {
                let data = '';
                res.on('data', chunk => { data += chunk; });
                res.on('end', () => {
                    try {
                        resolve(JSON.parse(data));
                    } catch (e) {
                        reject(new Error(`Invalid JSON response: ${data}`));
                    }
                });
            });
            req.on('error', (e) => reject(new Error(`Request error: ${e.message}`)));
            req.on('timeout', () => {
                req.destroy();
                reject(new Error(`Request timeout after ${this.timeout}ms`));
            });
            if (body) req.write(body);
            req.end();
        });
    }

    _assertSuccess(response) {
        if (response.code !== undefined && response.code !== 0) {
            throw new Error(`Bridge error: ${response.error || 'Unknown error'}`);
        }
    }
}

module.exports = { ZAPIBridgeClient };