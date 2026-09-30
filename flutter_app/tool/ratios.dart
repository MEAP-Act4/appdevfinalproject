import 'dart:math' as math;

double lin(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double lum(int rgb) {
  final r = ((rgb >> 16) & 0xFF) / 255;
  final g = ((rgb >> 8) & 0xFF) / 255;
  final b = (rgb & 0xFF) / 255;
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}

double ratio(int a, int b) {
  final la = lum(a);
  final lb = lum(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

double hslL(int rgb) {
  final r = ((rgb >> 16) & 0xFF) / 255;
  final g = ((rgb >> 8) & 0xFF) / 255;
  final b = (rgb & 0xFF) / 255;
  final mx = math.max(r, math.max(g, b));
  final mn = math.min(r, math.min(g, b));
  return (mx + mn) / 2;
}

double hslS(int rgb) {
  final r = ((rgb >> 16) & 0xFF) / 255;
  final g = ((rgb >> 8) & 0xFF) / 255;
  final b = (rgb & 0xFF) / 255;
  final mx = math.max(r, math.max(g, b));
  final mn = math.min(r, math.min(g, b));
  if (mx == mn) return 0;
  final l = (mx + mn) / 2;
  return (mx - mn) / (l > 0.5 ? 2 - mx - mn : mx + mn);
}

String f(double v) => v.toStringAsFixed(4);

void main() {
  const surface = 0x1E1E1E;
  const bg = 0x121212;
  const raised = 0x252525;
  const pairs = <String, (int, int)>{
    'accent#00E5FF on surface': (0x00E5FF, surface),
    'textSecondary#98989D on surface': (0x98989D, surface),
    'textSecondary#98989D on bg': (0x98989D, bg),
    'textSecondary#98989D on raised': (0x98989D, raised),
    'hcTextSecondary#C7C7CC on surface': (0xC7C7CC, surface),
    'hcTextSecondary#C7C7CC on bg': (0xC7C7CC, bg),
    'hcTextSecondary#C7C7CC on raised': (0xC7C7CC, raised),
    'border#2C2C2E on surface': (0x2C2C2E, surface),
    'hcBorder#48484A on surface': (0x48484A, surface),
    'border#2C2C2E on bg': (0x2C2C2E, bg),
    'hcBorder#48484A on bg': (0x48484A, bg),
    'lightAccent#0091A7 on white': (0x0091A7, 0xFFFFFF),
    'lightAccentText#00707F on white': (0x00707F, 0xFFFFFF),
    'lightAccentText#00707F on lightBg#F4F5F7': (0x00707F, 0xF4F5F7),
    'lightAccentText#00707F on lightRaised#ECEEF1': (0x00707F, 0xECEEF1),
    'lightTextPrimary on new normalFill#D8F5DF': (0x121212, 0xD8F5DF),
    'lightTextPrimary on old normalFill#E6F5E9': (0x121212, 0xE6F5E9),
    'lightNormal#1E8E33 on new normalFill#D8F5DF': (0x1E8E33, 0xD8F5DF),
    'lightNormal#1E8E33 on old normalFill#E6F5E9': (0x1E8E33, 0xE6F5E9),
    'lightTextSecondary#5B5F66 on new normalFill': (0x5B5F66, 0xD8F5DF),
    'lightAlert#D3261C on alertFill#FCE8E6': (0xD3261C, 0xFCE8E6),
    'lightWatch#9A7B00 on watchFill#FBF3D9': (0x9A7B00, 0xFBF3D9),
  };
  pairs.forEach((k, v) {
    print('$k -> ${ratio(v.$1, v.$2).toStringAsFixed(4)}');
  });

  print('');
  const hsl = <String, int>{
    'lightBackground#F4F5F7': 0xF4F5F7,
    'lightSurfaceRaised#ECEEF1': 0xECEEF1,
    'lightBorder#D9DDE3': 0xD9DDE3,
    'lightNormalBoxFill old#E6F5E9': 0xE6F5E9,
    'lightNormalBoxFill new#D8F5DF': 0xD8F5DF,
    'lightAlertBoxFill#FCE8E6': 0xFCE8E6,
    'lightWatchBoxFill#FBF3D9': 0xFBF3D9,
    'lightSurface#FFFFFF': 0xFFFFFF,
    'hcTextSecondary#C7C7CC': 0xC7C7CC,
    'hcBorder#48484A': 0x48484A,
    'lightAccentText#00707F': 0x00707F,
  };
  hsl.forEach((k, v) {
    print('$k -> L=${f(hslL(v))} S=${f(hslS(v))}');
  });
}
