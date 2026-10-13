import 'package:flutter_test/flutter_test.dart';
import 'package:wolves_club/lost_pet_service.dart';

void main() {
  group('lostPetMatchScore', () {
    test('ranks similar sightings above unrelated reports without confirming',
        () {
      final score = lostPetMatchScore(
        missionSpecies: 'dog',
        sightingSpecies: 'dog',
        missionColor: 'white and brown',
        sightingColor: 'white',
        missionSize: 'medium',
        sightingSize: 'medium',
        missionCity: 'San José',
        sightingCity: 'San José',
        missingAt: DateTime(2026, 10, 1),
        sightedAt: DateTime(2026, 10, 2),
      );

      expect(score, 10);
    });

    test('does not award matches for unknown fields or unrelated dates', () {
      final score = lostPetMatchScore(
        missionSpecies: 'dog',
        sightingSpecies: 'cat',
        missionColor: '',
        sightingColor: 'black',
        missionSize: 'unknown',
        sightingSize: 'large',
        missionCity: 'North',
        sightingCity: 'South',
        missingAt: DateTime(2026, 10, 10),
        sightedAt: DateTime(2026, 10, 1),
      );

      expect(score, 0);
    });
  });

  test('exposes the supported mission lifecycle states', () {
    expect(
      lostPetStatuses,
      {'active', 'sightings', 'verifying', 'reunited', 'closed'},
    );
  });
}
