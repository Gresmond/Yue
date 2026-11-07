import 'dart:math' as math;

/// How a recall went.
enum Rating {
  again(1),
  hard(2),
  good(3),
  easy(4);

  const Rating(this.value);
  final int value;
}

/// What the scheduler knows about one thing you're learning.
class Memory {
  const Memory({required this.stability, required this.difficulty, required this.lastMs, required this.dueMs, this.reps = 1, this.lapses = 0});

  /// Days until recall falls to 90%.
  final double stability;
  final double difficulty;
  final int lastMs, dueMs, reps, lapses;

  /// It has come through at least one spaced review: a level's words must be
  /// held for the level to clear.
  bool get held => stability >= 7;
  bool get strong => stability >= 21;
}

/// FSRS-6 with its published default weights, from the open-spaced-repetition
/// project's py-fsrs. Aims to review each thing when recall is about 90%.
abstract final class Fsrs {
  static const w = <double>[
    0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483,
    0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
  ];
  static const retention = 0.9, _day = 86400000;

  /// How long something forgotten waits before it comes round again.
  static const relearnMs = 10 * 60 * 1000;

  static double get _decay => -w[20];
  static double get _factor => math.pow(0.9, 1 / _decay) - 1;

  static double _clampD(double d) => d.clamp(1.0, 10.0);
  static double _clampS(double s) => math.max(s, 0.001);

  static double _initialD(int r) => w[4] - math.exp(w[5] * (r - 1)) + 1;

  /// The chance of recalling it [elapsedDays] after its last review.
  static double recall(double stability, double elapsedDays) =>
      math.pow(1 + _factor * math.max(elapsedDays, 0) / stability, _decay).toDouble();

  static double recallAt(Memory m, int nowMs) => recall(m.stability, (nowMs - m.lastMs) / _day);

  static double _nextD(double d, int r) {
    final delta = -(w[6] * (r - 3));
    final damped = d + (10 - d) * delta / 9;
    return _clampD(w[7] * _initialD(4) + (1 - w[7]) * damped);
  }

  static double _shortTerm(double s, int r) {
    var inc = math.exp(w[17] * (r - 3 + w[18])) * math.pow(s, -w[19]);
    if (r >= 2) inc = math.max(inc, 1.0);
    return _clampS(s * inc);
  }

  static double _nextS(double d, double s, double ret, int r) {
    if (r == 1) {
      final long = w[11] * math.pow(d, -w[12]) * (math.pow(s + 1, w[13]) - 1) * math.exp((1 - ret) * w[14]);
      return _clampS(math.min(long, s / math.exp(w[17] * w[18])));
    }
    final penalty = r == 2 ? w[15] : 1.0, bonus = r == 4 ? w[16] : 1.0;
    return _clampS(s * (1 + math.exp(w[8]) * (11 - d) * math.pow(s, -w[9]) * (math.exp((1 - ret) * w[10]) - 1) * penalty * bonus));
  }

  /// Whole days until recall falls to [retention].
  static int interval(double stability) {
    final days = (stability / _factor) * (math.pow(retention, 1 / _decay) - 1);
    return days.round().clamp(1, 36500);
  }

  /// [before] (null if new) after a review rated [rating] at [nowMs]. [fuzz], from
  /// 0 to 1, spreads long intervals so a batch doesn't all come due together.
  /// The same fuzz for the same review on every device, so working a card's
  /// history out again always reaches the same answer.
  static double fuzzFor(String id, int atMs) {
    var hash = 0x811c9dc5;
    for (final unit in '$id@$atMs'.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash / 0xffffffff;
  }

  static Memory review(Memory? before, Rating rating, int nowMs, {double fuzz = 0.5}) {
    final r = rating.value;
    double s, d;
    if (before == null) {
      s = _clampS(w[r - 1]);
      d = _clampD(_initialD(r));
    } else {
      final elapsed = (nowMs - before.lastMs) / _day;
      s = elapsed < 1 ? _shortTerm(before.stability, r) : _nextS(before.difficulty, before.stability, recall(before.stability, elapsed), r);
      d = _nextD(before.difficulty, r);
    }
    var days = interval(s);
    if (days >= 3) days = (days * (0.95 + 0.1 * fuzz)).round();
    final due = rating == Rating.again ? nowMs + relearnMs : nowMs + days * _day;
    return Memory(
      stability: s,
      difficulty: d,
      lastMs: nowMs,
      dueMs: due,
      reps: (before?.reps ?? 0) + 1,
      lapses: (before?.lapses ?? 0) + (rating == Rating.again ? 1 : 0),
    );
  }
}
