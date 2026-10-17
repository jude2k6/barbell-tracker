import 'dart:math' as math;

import 'package:barbell_app/analysis/dsp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('butter(4,[0.25 4]/50) matches the constants baked into the native lib', () {
    final f = butter(4, [0.25 / 50, 4 / 50], type: 'bandpass');
    const k = 0.00014412022407538452;
    final b = [k, 0, -4 * k, 0, 6 * k, 0, -4 * k, 0, k];
    const a = [
      1, -7.370332381485367, 23.79578457254215, -43.95961643549418,
      50.82674996737485, -37.66476395739411, 17.470170337982,
      -4.637347231624153, 0.5393551282803056,
    ];
    for (var i = 0; i < 9; i++) {
      expect(f.b[i], closeTo(b[i], 1e-12), reason: 'b[$i]');
      expect(f.a[i], closeTo(a[i], 1e-9), reason: 'a[$i]');
    }
  });

  test('6th-order high-pass has the binomial numerator pattern', () {
    final f = butter(6, [10 / 100], type: 'high');
    const pattern = [1, -6, 15, -20, 15, -6, 1];
    for (var i = 0; i < 7; i++) {
      expect(f.b[i] / f.b[0], closeTo(pattern[i].toDouble(), 1e-9));
    }
    // Unity gain at Nyquist.
    final gNyq = sum([for (var i = 0; i < 7; i++) f.b[i] * math.pow(-1, i)]) /
        sum([for (var i = 0; i < 7; i++) f.a[i] * math.pow(-1, i)]);
    expect(gNyq, closeTo(1, 1e-9));
  });

  test('filtfilt keeps a constant through a low-pass and removes it with a high-pass', () {
    final x = List<double>.filled(400, 3);
    final lp = filtfilt(butter(2, [0.1], type: 'low'), x);
    final hp = filtfilt(butter(2, [0.1], type: 'high'), x);
    for (var i = 0; i < x.length; i++) {
      expect(lp[i], closeTo(3, 1e-9));
      expect(hp[i], closeTo(0, 1e-9));
    }
  });

  test('movmean follows MATLAB windowing for odd and even k', () {
    final x = <double>[1, 2, 3, 4, 5];
    expect(movmean(x, 3), [1.5, 2, 3, 4, 4.5]);
    // k = 4: 2 back, 1 forward.
    expect(movmean(x, 4), [1.5, 2, 2.5, 3.5, 4]);
  });

  test('detrend, cumtrapz, interp1, median', () {
    for (final v in detrend([1.0, 3, 5, 7])) {
      expect(v, closeTo(0, 1e-12));
    }
    expect(cumtrapz([0.0, 2, 4]), [0, 1, 4]);
    final q = interp1([0.0, 10, 20], [0.0, 1, 0], [-1, 5, 15, 20, 21]);
    expect(q[0].isNaN && q[4].isNaN, isTrue);
    expect(q.sublist(1, 4), [0.5, 0.5, 0]);
    expect(median([3.0, 1, 2, 10]), 2.5);
  });
}
