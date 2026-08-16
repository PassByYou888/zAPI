<?php
// webhook_server.php - Simple webhook receiver for ZAPI bridge

// Log received request
file_put_contents('php://stdout', "Webhook received: " . file_get_contents('php://input') . "\n");

// Parse JSON body
$input = json_decode(file_get_contents('php://input'), true);
if (!$input) {
    http_response_code(400);
    echo json_encode(['error' => 'Invalid JSON']);
    exit;
}

// Extract data
$app = $input['app'] ?? '';
$api = $input['api'] ?? '';
$args = $input['args'] ?? [];
$timestamp = $input['timestamp'] ?? 0;

// Prepare response (echo back for demonstration)
$response = [
    'status' => 'ok',
    'received' => [
        'app' => $app,
        'api' => $api,
        'args' => $args,
        'timestamp' => $timestamp
    ],
    'message' => 'Webhook processed successfully'
];

// For 'call' mode, we must return a JSON response
header('Content-Type: application/json');
echo json_encode($response);