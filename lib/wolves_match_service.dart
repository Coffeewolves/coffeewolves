import 'package:cloud_functions/cloud_functions.dart';

class WolvesMatchService {
  WolvesMatchService({FirebaseFunctions? functions})
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> getState() async {
    final result = await _functions.httpsCallable('getWolvesMatchState').call();
    return Map<String, dynamic>.from(result.data as Map);
  }

  Future<void> saveProfile({
    required String status,
    required String displayName,
    required String bio,
    required String intention,
    required List<String> interests,
    bool consent = false,
  }) async {
    await _functions.httpsCallable('saveWolvesMatchProfile').call({
      'status': status,
      'displayName': displayName,
      'bio': bio,
      'intention': intention,
      'interests': interests,
      'consent': consent,
    });
  }

  Future<String> sendInterest(String profileId) async {
    final result = await _functions
        .httpsCallable('sendWolvesMatchInterest')
        .call<Map<String, dynamic>>({'profileId': profileId});
    return result.data['status'] as String;
  }

  Future<String> startCoffeePupGame({
    required String profileId,
    required String gameType,
  }) async {
    final result = await _functions
        .httpsCallable('startCoffeePupGame')
        .call<Map<String, dynamic>>({
      'profileId': profileId,
      'gameType': gameType,
    });
    return result.data['sessionId'] as String;
  }

  Future<void> respondToInterest({
    required String profileId,
    required bool accept,
  }) async {
    await _functions.httpsCallable('respondWolvesMatchInterest').call({
      'profileId': profileId,
      'accept': accept,
    });
  }

  Future<void> dismissProfile(String profileId) async {
    await _functions
        .httpsCallable('dismissWolvesMatchProfile')
        .call({'profileId': profileId});
  }

  Future<void> blockProfile(String profileId) async {
    await _functions
        .httpsCallable('blockWolvesMatchProfile')
        .call({'profileId': profileId});
  }

  Future<void> reportProfile({
    required String profileId,
    required String reason,
    required String details,
  }) async {
    await _functions.httpsCallable('reportWolvesMatchProfile').call({
      'profileId': profileId,
      'reason': reason,
      'details': details,
    });
  }
}
