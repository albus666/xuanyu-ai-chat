import 'dart:math' as math;
import 'dart:ui';

enum WishFishActivity { wandering, approaching, eating, searching, leaving }

enum WishFeedingStage { approaching, eating, dispersing, complete }

class WishPondFish {
  WishPondFish(this.index, this.position, this.heading);

  final int index;
  Offset position;
  double heading;
  double speed = 0;
  double tailPhase = 0;
  double reactAt = 0;
  double pauseUntil = 0;
  double searchUntil = 0;
  double biteUntil = 0;
  int? targetGrain;
  Offset? destination;
  Offset? approachPoint;
  WishFishActivity activity = WishFishActivity.wandering;

  double get width => const [27.0, 25.0, 30.0][index];
  double get length => width * 1.5;
  // The retained artwork's nose is 5% from the top of its transparent canvas.
  double get mouthReach => length * 0.445;
  Offset get forward => Offset(math.cos(heading), math.sin(heading));
  Offset get mouth => position + forward * mouthReach;
}

class WishFoodGrain {
  WishFoodGrain({
    required this.id,
    required this.landing,
    required this.releaseAt,
    required this.fallDuration,
    required this.radius,
  }) : position = landing;

  final int id;
  Offset landing;
  Offset position;
  final double releaseAt;
  final double fallDuration;
  final double radius;
  double? eatenAt;
  int? reservedBy;
  double get landsAt => releaseAt + fallDuration;
  bool isFloating(double time) => time >= landsAt && eatenAt == null;

  void update(double time) {
    if (eatenAt != null) return;
    final fall = ((time - releaseAt) / fallDuration).clamp(0.0, 1.0);
    final drift = math.max(0.0, time - landsAt);
    position = landing +
        Offset(
          (1 - fall) * ((id % 3) - 1) * 7 + math.sin(drift * 0.7 + id) * 1.8,
          -42 * (1 - fall * fall) + math.sin(drift * 0.55 + id * 2) * 0.8,
        );
  }
}

class WishPondBite {
  const WishPondBite(
      this.grainId, this.fishIndex, this.time, this.mouth, this.foodPosition);

  final int grainId;
  final int fishIndex;
  final double time;
  final Offset mouth;
  final Offset foodPosition;
}

/// Persistent positions and bounded steering keep feeding and idle movement
/// continuous. Food is removed only by a mouth/particle contact, never a timer.
class WishPondSimulation {
  WishPondSimulation({math.Random? random}) : _random = random ?? math.Random();

  final math.Random _random;
  Size size = Size.zero;
  double time = 0;
  double? _allEatenAt;
  bool isFeeding = false;
  final List<WishPondFish> fish = [];
  final List<WishFoodGrain> grains = [];
  final List<WishPondBite> bites = [];

  Rect get swimmingBounds => Rect.fromLTRB(size.width * 0.33,
      size.height * 0.75, size.width * 0.65, size.height * 0.93);

  WishFeedingStage get stage {
    if (!isFeeding) return WishFeedingStage.complete;
    if (_allEatenAt != null) return WishFeedingStage.dispersing;
    return bites.isEmpty
        ? WishFeedingStage.approaching
        : WishFeedingStage.eating;
  }

  void resize(Size value) {
    if (value == size || value.isEmpty) return;
    final previous = size;
    size = value;
    if (fish.isEmpty) {
      fish.addAll([
        WishPondFish(0, Offset(size.width * 0.38, size.height * 0.78), 0.7),
        WishPondFish(1, Offset(size.width * 0.62, size.height * 0.77), 2.2),
        WishPondFish(2, Offset(size.width * 0.57, size.height * 0.90), -2.0),
      ]);
      return;
    }
    Offset scale(Offset point) => Offset(point.dx * size.width / previous.width,
        point.dy * size.height / previous.height);
    for (final animal in fish) {
      animal.position = scale(animal.position);
      if (animal.destination != null) {
        animal.destination = scale(animal.destination!);
      }
      if (animal.approachPoint != null) {
        animal.approachPoint = scale(animal.approachPoint!);
      }
    }
    for (final grain in grains) {
      grain.landing = scale(grain.landing);
      grain.position = scale(grain.position);
    }
  }

  void feed(int quantity) {
    if (size.isEmpty || quantity <= 0) return;
    final continuing = isFeeding;
    if (!continuing) {
      grains.clear();
      bites.clear();
    }
    final firstId = grains.length;
    _allEatenAt = null;
    isFeeding = true;
    final count = 6 + quantity.clamp(1, 10) * 2;
    final rotation = _random.nextDouble() * math.pi * 2;
    for (var i = 0; i < count; i++) {
      // Spread the grains over the water instead of piling them at one point.
      final angle = rotation + i * 2.399963;
      final radius = math.sqrt((i + 0.5) / count);
      final landing = Offset(
        size.width * (0.51 + math.cos(angle) * radius * 0.085),
        size.height * (0.835 + math.sin(angle) * radius * 0.026),
      );
      grains.add(WishFoodGrain(
        id: firstId + i,
        landing: landing,
        releaseAt: time + 0.05 + i * 0.025 + _random.nextDouble() * 0.08,
        fallDuration: 0.38 + _random.nextDouble() * 0.2,
        radius: 1.1 + _random.nextDouble() * 0.55,
      ));
    }
    if (continuing) return;
    for (final animal in fish) {
      animal.reactAt =
          time + 0.35 + animal.index * 0.36 + _random.nextDouble() * 0.2;
      animal.targetGrain = null;
      animal.approachPoint = null;
      animal.pauseUntil = 0;
      animal.activity = WishFishActivity.approaching;
    }
  }

  void advance(double seconds) {
    if (size.isEmpty || seconds <= 0 || !seconds.isFinite) return;
    // Substeps also prevent a slow frame from skipping mouth contact.
    var remaining = seconds;
    while (remaining > 0.000001) {
      final dt = math.min(remaining, 1 / 60);
      time += dt;
      for (final grain in grains) {
        grain.update(time);
      }
      for (final animal in fish) {
        _advanceFish(animal, dt);
      }
      if (isFeeding && grains.every((grain) => grain.eatenAt != null)) {
        _allEatenAt ??= time;
        if (time - _allEatenAt! > 3.0) isFeeding = false;
      }
      remaining -= dt;
    }
  }

  void _advanceFish(WishPondFish animal, double dt) {
    if (isFeeding && _allEatenAt == null && time >= animal.reactAt) {
      if (time < animal.pauseUntil) {
        animal.tailPhase += dt * 4;
        animal.speed *= math.exp(-dt * 9);
        return;
      }
      final target = _findFood(animal);
      if (target != null) {
        animal.activity = WishFishActivity.eating;
        final distance = (target.position - animal.position).distance;
        if (animal.approachPoint == null && distance < animal.mouthReach - 2) {
          final away = animal.position - target.position;
          final direction =
              away.distance > 0.1 ? away / away.distance : animal.forward;
          animal.approachPoint = _constrain(
              target.position + direction * (animal.mouthReach + 22));
        }
        if (animal.approachPoint != null) {
          if ((animal.position - animal.approachPoint!).distance > 5) {
            _swim(animal, animal.approachPoint!, 17, dt);
            return;
          }
          animal.approachPoint = null;
        }
        _swim(animal, target.position,
            ((distance - animal.mouthReach + 0.8) * 3.5).clamp(0.5, 42.0), dt);
        final contact = (animal.mouth - target.position).distance;
        if (target.isFloating(time) && contact <= 3.0) {
          target.eatenAt = time;
          bites.add(WishPondBite(
              target.id, animal.index, time, animal.mouth, target.position));
          animal.targetGrain = null;
          animal.approachPoint = null;
          animal.biteUntil = time + 0.25;
          animal.pauseUntil = time + 0.22 + _random.nextDouble() * 0.35;
        }
        return;
      }
    }

    if (_allEatenAt != null &&
        (animal.activity == WishFishActivity.eating ||
            animal.activity == WishFishActivity.approaching)) {
      animal.activity = WishFishActivity.searching;
      animal.searchUntil =
          time + 0.45 + animal.index * 0.38 + _random.nextDouble() * 0.45;
      animal.destination = _nearbyPoint(animal.position, 17);
    }
    if (animal.activity == WishFishActivity.searching &&
        time >= animal.searchUntil) {
      animal.activity = WishFishActivity.leaving;
      final bounds = swimmingBounds;
      animal.destination = Offset(
        bounds.left + bounds.width * const [0.15, 0.85, 0.55][animal.index],
        bounds.top + bounds.height * const [0.25, 0.35, 0.85][animal.index],
      );
    }
    if (animal.destination == null ||
        (animal.destination! - animal.position).distance < 9) {
      if (animal.activity == WishFishActivity.leaving) {
        animal.activity = WishFishActivity.wandering;
      }
      animal.destination = _randomPoint();
    }
    final speed = animal.activity == WishFishActivity.searching
        ? 6.0
        : animal.activity == WishFishActivity.leaving
            ? 17.0
            : 10.0 + animal.index * 2;
    _swim(animal, animal.destination!, speed, dt);
  }

  WishFoodGrain? _findFood(WishPondFish animal) {
    if (animal.targetGrain != null) {
      final target = grains[animal.targetGrain!];
      if (target.eatenAt == null) return target;
      animal.targetGrain = null;
    }
    WishFoodGrain? nearest;
    var nearestDistance = double.infinity;
    for (final grain in grains) {
      if (grain.eatenAt != null ||
          grain.reservedBy != null ||
          time < grain.releaseAt) {
        continue;
      }
      final distance = (grain.position - animal.mouth).distance;
      if (distance < nearestDistance) {
        nearest = grain;
        nearestDistance = distance;
      }
    }
    if (nearest != null) {
      nearest.reservedBy = animal.index;
      animal.targetGrain = nearest.id;
    }
    return nearest;
  }

  void _swim(WishPondFish animal, Offset destination, double speed, double dt) {
    var direction = destination - animal.position;
    if (direction.distance < 0.01) return;
    // Give passing fish room; stop avoiding near food so contact is reachable.
    if (direction.distance > animal.mouthReach + 14) {
      for (final other in fish) {
        if (identical(other, animal)) continue;
        final away = animal.position - other.position;
        if (away.distance > 0.1 && away.distance < 22) {
          direction += away / away.distance * (22 - away.distance) * 0.6;
        }
      }
    }
    final desired = math.atan2(direction.dy, direction.dx);
    final difference = _angleDelta(desired, animal.heading);
    final turnRate = animal.activity == WishFishActivity.eating ? 2.6 : 1.35;
    animal.heading += difference.clamp(-turnRate * dt, turnRate * dt);
    final facing =
        math.max(0.04, math.cos(_angleDelta(desired, animal.heading)));
    final targetSpeed = speed * facing;
    animal.speed += (targetSpeed - animal.speed) * (1 - math.exp(-dt * 5));
    animal.position += animal.forward * animal.speed * dt;
    animal.position = _constrain(animal.position);
    animal.tailPhase += dt * (4.0 + animal.speed * 0.18);
  }

  Offset _constrain(Offset point) {
    final bounds = swimmingBounds;
    return Offset(point.dx.clamp(bounds.left, bounds.right),
        point.dy.clamp(bounds.top, bounds.bottom));
  }

  Offset _randomPoint() {
    final bounds = swimmingBounds;
    return Offset(
        bounds.left + (0.08 + _random.nextDouble() * 0.84) * bounds.width,
        bounds.top + (0.08 + _random.nextDouble() * 0.84) * bounds.height);
  }

  Offset _nearbyPoint(Offset point, double radius) => _constrain(point +
      Offset((_random.nextDouble() - 0.5) * radius * 2,
          (_random.nextDouble() - 0.5) * radius * 2));

  double _angleDelta(double a, double b) =>
      math.atan2(math.sin(a - b), math.cos(a - b));
}
