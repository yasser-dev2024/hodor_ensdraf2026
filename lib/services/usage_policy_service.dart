import '../repositories/key_value_store.dart';

abstract final class UsagePolicy {
  static const version = '2026-08-21.1';
  static const acceptedVersionKey = 'usage_policy_accepted_version';
}

class UsagePolicyService {
  UsagePolicyService(this._store);

  final KeyValueStore _store;

  Future<bool> isCurrentVersionAccepted() async =>
      await _store.get(UsagePolicy.acceptedVersionKey) == UsagePolicy.version;

  Future<void> acceptCurrentVersion() =>
      _store.set(UsagePolicy.acceptedVersionKey, UsagePolicy.version);
}
