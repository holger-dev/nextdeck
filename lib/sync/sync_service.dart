abstract class SyncService {
  Future<void> initSyncOnAppStart();
  Future<void> periodicDeltaSync();
  Future<void> refreshUpcoming();
  Future<void> ensureBoardFresh(int boardId);
  Future<void> verifyAfterWrite({required int boardId, Set<int> stackIds});

  /// Schließt den HTTP-Client und gibt damit Keep-Alive-Connections frei.
  /// Muss aufgerufen werden, bevor die Instanz weggeworfen wird (z. B. bei
  /// Server-/Credential-Wechsel), sonst leakt der Socket-Pool.
  void dispose();
}

