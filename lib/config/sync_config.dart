const int kSyncMaxConcurrency = 3; // 2–4 ok
const Duration kActivePollInterval = Duration(seconds: 60);
const Duration kInactivePollInterval = Duration(minutes: 10);
const Duration kRequestTimeout = Duration(seconds: 15);
const int kMaxRetries = 3;
const Duration kBaseBackoff = Duration(seconds: 2); // exponential backoff base

