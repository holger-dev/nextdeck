abstract class SyncService {
  Future<void> initSyncOnAppStart();
  Future<void> periodicDeltaSync();
  Future<void> refreshUpcoming();
  Future<void> ensureBoardFresh(int boardId);
  Future<void> verifyAfterWrite({required int boardId, Set<int> stackIds});
}

