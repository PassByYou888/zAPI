<?php
/**
 * ZAPI Bridge HTTP Client for PHP
 * 
 * Provides methods to call ZAPI services and manage webhooks via the bridge.
 * Requires PHP 7.4+ with cURL extension.
 */
class ZAPIBridgeClient
{
    private string $baseUrl;
    private int $timeout;

    /**
     * @param string $baseUrl  Bridge base URL, e.g. "http://127.0.0.1:8080/v1"
     * @param int    $timeout  Default timeout in seconds for HTTP requests
     */
    public function __construct(string $baseUrl = 'http://127.0.0.1:8080/v1', int $timeout = 30)
    {
        $this->baseUrl = rtrim($baseUrl, '/');
        $this->timeout = $timeout;
    }

    /**
     * Perform a synchronous ZAPI call.
     *
     * @param string $app     Target application name
     * @param string $api     API name
     * @param array  $args    Arguments (will be JSON-encoded)
     * @param int    $timeout Timeout in milliseconds (passed to ZAPI)
     * @return mixed          The result from ZAPI (decoded JSON)
     * @throws RuntimeException on error
     */
    public function invoke(string $app, string $api, array $args = [], int $timeout = 5000)
    {
        $payload = [
            'app' => $app,
            'api' => $api,
            'args' => $args,
            'timeout' => $timeout
        ];
        $response = $this->httpPost('/invoke', $payload);
        $this->assertSuccess($response);
        return $response['result'] ?? null;
    }

    /**
     * Send a one-way notification.
     *
     * @param string $app  Target application name
     * @param string $api  API name
     * @param array  $args Arguments
     * @throws RuntimeException on error
     */
    public function notify(string $app, string $api, array $args = []): void
    {
        $payload = ['app' => $app, 'api' => $api, 'args' => $args];
        $response = $this->httpPost('/notify', $payload);
        $this->assertSuccess($response);
    }

    /**
     * Register a webhook callback.
     *
     * @param string $app          Application name
     * @param string $api          API name
     * @param string $callbackUrl  URL where the bridge will forward requests
     * @param string $mode         'call' (sync) or 'notify' (async)
     * @return array               Registration response
     * @throws RuntimeException on error
     */
    public function registerHook(string $app, string $api, string $callbackUrl, string $mode = 'call'): array
    {
        $payload = [
            'app' => $app,
            'api' => $api,
            'callback_url' => $callbackUrl,
            'mode' => $mode
        ];
        $response = $this->httpPost('/hooks/register', $payload);
        $this->assertSuccess($response);
        return $response;
    }

    /**
     * Unregister a webhook.
     *
     * @param string $app Application name
     * @param string $api API name
     * @return array      Unregister response
     * @throws RuntimeException on error
     */
    public function unregisterHook(string $app, string $api): array
    {
        $payload = ['app' => $app, 'api' => $api];
        $response = $this->httpPost('/hooks/unregister', $payload);
        $this->assertSuccess($response);
        return $response;
    }

    /**
     * List all registered hooks.
     *
     * @return array  List of hooks
     * @throws RuntimeException on error
     */
    public function listHooks(): array
    {
        $response = $this->httpGet('/hooks/list');
        $this->assertSuccess($response);
        return $response['hooks'] ?? [];
    }

    /**
     * Check bridge health.
     *
     * @return bool  True if bridge is healthy
     */
    public function health(): bool
    {
        try {
            $response = $this->httpGet('/health');
            return isset($response['status']) && $response['status'] === 'ok';
        } catch (Exception $e) {
            return false;
        }
    }

    // ---------- Internal HTTP helpers ----------

    private function httpPost(string $endpoint, array $data): array
    {
        $url = $this->baseUrl . $endpoint;
        $json = json_encode($data);
        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, $json);
        curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
        curl_setopt($ch, CURLOPT_TIMEOUT, $this->timeout);
        $response = curl_exec($ch);
        $error = curl_error($ch);
        $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        curl_close($ch);

        if ($response === false) {
            throw new RuntimeException("cURL error: $error");
        }

        $decoded = json_decode($response, true);
        if (!is_array($decoded)) {
            throw new RuntimeException("Invalid JSON response: $response");
        }

        return $decoded;
    }

    private function httpGet(string $endpoint): array
    {
        $url = $this->baseUrl . $endpoint;
        $ch = curl_init($url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_HTTPHEADER, ['Accept: application/json']);
        curl_setopt($ch, CURLOPT_TIMEOUT, $this->timeout);
        $response = curl_exec($ch);
        $error = curl_error($ch);
        curl_close($ch);

        if ($response === false) {
            throw new RuntimeException("cURL error: $error");
        }

        $decoded = json_decode($response, true);
        if (!is_array($decoded)) {
            throw new RuntimeException("Invalid JSON response: $response");
        }
        return $decoded;
    }

    private function assertSuccess(array $response): void
    {
        if (!isset($response['code']) || $response['code'] !== 0) {
            $error = $response['error'] ?? 'Unknown error';
            throw new RuntimeException("Bridge error: $error");
        }
    }
}