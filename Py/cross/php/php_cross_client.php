<?php
/**
 * PHP 客户端调用 Cross Bridge
 */
class CrossBridgeClient
{
    private string $baseUrl;

    public function __construct(string $baseUrl = 'http://127.0.0.1:8081')
    {
        $this->baseUrl = rtrim($baseUrl, '/');
    }

    /**
     * 调用远程 API
     * @param string $api   API 名称 ('add' 或 'inv_seri')
     * @param array  $args  参数列表
     * @param int    $timeout 超时（毫秒）
     * @return mixed
     * @throws Exception
     */
    public function call(string $api, array $args = [], int $timeout = 2000)
    {
        $payload = json_encode(['api' => $api, 'args' => $args, 'timeout' => $timeout]);
        $ch = curl_init($this->baseUrl . '/cross');
        curl_setopt($ch, CURLOPT_POST, true);
        curl_setopt($ch, CURLOPT_POSTFIELDS, $payload);
        curl_setopt($ch, CURLOPT_HTTPHEADER, ['Content-Type: application/json']);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, max(1, $timeout / 1000 + 1));
        $response = curl_exec($ch);
        $error = curl_error($ch);
        curl_close($ch);

        if ($response === false) {
            throw new Exception("cURL 错误: $error");
        }
        $data = json_decode($response, true);
        if (!is_array($data)) {
            throw new Exception("无效 JSON 响应: $response");
        }
        if (isset($data['code']) && $data['code'] !== 0) {
            throw new Exception("Bridge 错误: " . ($data['error'] ?? '未知错误'));
        }
        return $data['result'] ?? null;
    }
}

// 使用示例
try {
    $client = new CrossBridgeClient('http://127.0.0.1:8081');
    
    // 调用 add
    $sum = $client->call('add', [10, 20]);
    echo "10 + 20 = $sum\n";

    // 调用 inv_seri
    $result = $client->call('inv_seri');
    echo "inv_seri 结果: $result\n";

} catch (Exception $e) {
    echo "错误: " . $e->getMessage() . "\n";
}