import 'package:xuanyu/features/merit/models/merit_models.dart';

const int meritDefaultAutoKnockIntervalMs = 280;
const int meritFastestAutoKnockIntervalMs = 160;
const int meritSlowestAutoKnockIntervalMs = 650;

Duration meritAutoKnockIntervalFor(MeritSaveData data) => Duration(
      milliseconds: data.autoKnockIntervalMs.clamp(
        meritFastestAutoKnockIntervalMs,
        meritSlowestAutoKnockIntervalMs,
      ),
    );

double meritKnocksPerSecond(MeritSaveData data) =>
    1000 / meritAutoKnockIntervalFor(data).inMilliseconds;

void setMeritKnocksPerSecond(MeritSaveData data, double speed) {
  data.autoKnockIntervalMs = (1000 / speed.clamp(1.5, 6.0)).round();
}
